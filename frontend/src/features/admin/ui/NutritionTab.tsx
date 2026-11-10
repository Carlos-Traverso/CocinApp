import { useCallback, useEffect, useState } from 'react'
import { nutritionRepository, type NutritionConfigInput } from '../../profile/data/NutritionRepository'
import type { NutritionConfig } from '../../profile/domain/profile'
import { useNotifications } from '../../../shared/notifications/NotificationProvider'

const activities = [['sedentary', 'Sedentaria'], ['light', 'Ligera'], ['moderate', 'Moderada'], ['active', 'Activa'], ['very-active', 'Muy activa']] as const
const goals = [['lose', 'Perder peso'], ['maintain', 'Mantener'], ['gain', 'Ganar peso'], ['gain-muscle', 'Ganar masa muscular']] as const
type Draft = { factors: Record<string, string>; goals: Record<string, { minimum: string; maximum: string }>; source: string; effectiveAt: string }
const emptyDraft = (): Draft => ({ factors: {}, goals: {}, source: '', effectiveAt: '' })
const toDraft = (config: NutritionConfig): Draft => ({
  factors: Object.fromEntries(activities.map(([key]) => [key, String(config.activityFactors[key])])),
  goals: Object.fromEntries(goals.map(([key]) => [key, { minimum: String(config.goalAdjustments[key].minimum), maximum: String(config.goalAdjustments[key].maximum) }])),
  source: config.sourceNote, effectiveAt: '',
})

export function NutritionTab() {
  const [versions, setVersions] = useState<NutritionConfig[]>([])
  const [draft, setDraft] = useState<Draft>(emptyDraft)
  const [loading, setLoading] = useState(true)
  const [publishing, setPublishing] = useState(false)
  const [pending, setPending] = useState<{ config: NutritionConfigInput; expected: number } | null>(null)
  const [error, setError] = useState('')
  const { notify } = useNotifications()
  const currentlyEffective = versions.filter((item) => Date.parse(item.effectiveAt) <= Date.now()).sort((a, b) => Date.parse(b.effectiveAt) - Date.parse(a.effectiveAt) || b.configVersion - a.configVersion)[0]
  const nextVersion = versions[0]?.configVersion ?? 0
  const reload = useCallback(async () => {
    setLoading(true); setError('')
    try {
      const result = await nutritionRepository.list()
      setVersions(result)
      if (!draft.source && result[0]) setDraft(toDraft(result[0]))
    } catch (cause) { setError(cause instanceof Error ? cause.message : 'No se pudieron cargar las versiones.') }
    finally { setLoading(false) }
  }, [])
  useEffect(() => { void reload() }, [reload])

  function prepare(): { config: NutritionConfigInput; expected: number } {
    const activityFactors = Object.fromEntries(activities.map(([key]) => {
      const value = Number(draft.factors[key]);
      if (!draft.factors[key] || !Number.isFinite(value) || value <= 0 || value > 10 || Math.round(value * 1e6) !== value * 1e6) throw new Error(`Ingresá un factor válido para actividad ${key}.`)
      return [key, value]
    })) as NutritionConfigInput['activityFactors']
    const goalAdjustments = Object.fromEntries(goals.map(([key]) => {
      const minimum = Number(draft.goals[key]?.minimum); const maximum = Number(draft.goals[key]?.maximum)
      if (!draft.goals[key]?.minimum || !draft.goals[key]?.maximum || !Number.isInteger(minimum) || !Number.isInteger(maximum) || minimum < -10000 || maximum > 10000 || minimum > maximum) throw new Error(`Revisá los límites del objetivo ${key}.`)
      return [key, { minimum, maximum }]
    })) as NutritionConfigInput['goalAdjustments']
    if (!draft.source.trim() || draft.source.trim().length > 2000) throw new Error('Indicá una fuente de hasta 2000 caracteres.')
    if (!draft.effectiveAt) throw new Error('Indicá cuándo entra en vigencia la configuración.')
    const date = new Date(draft.effectiveAt)
    if (!Number.isFinite(date.getTime())) throw new Error('La fecha de vigencia no es válida.')
    return { config: { activityFactors, goalAdjustments, sourceNote: draft.source.trim(), effectiveAt: date.toISOString() }, expected: versions[0]?.configVersion ?? 0 }
  }

  async function publish(request: { config: NutritionConfigInput; expected: number }) {
    setPublishing(true); setError('')
    try {
      const saved = await nutritionRepository.publish(request.config, request.expected)
      setPending(null); setVersions((current) => [saved, ...current.filter((item) => item.configVersion !== saved.configVersion)].sort((a, b) => b.configVersion - a.configVersion))
      await notify({ type: 'success', title: 'Configuración publicada', message: `Versión ${saved.configVersion} publicada.` })
    } catch (cause) {
      setPending(request)
      const message = cause instanceof Error ? cause.message : 'No se pudo publicar la configuración.'
      setError(message)
      const code = cause && typeof cause === 'object' ? (cause as { code?: unknown }).code : undefined
      if (code === '40001' || /40001|cambió|recargá/i.test(message)) await reload()
    } finally { setPublishing(false) }
  }

  return <section className="admin-form-stack" aria-label="Configuración nutricional">
    <div className="section-heading"><div><h2>Configuración nutricional</h2><p>Las estimaciones son informativas y usan únicamente una versión vigente publicada.</p></div><button className="button button-quiet" disabled={loading} onClick={() => void reload()} type="button">Actualizar versiones</button></div>
    {error && <p className="form-message error" role="alert">{error}</p>}
    {!loading && (currentlyEffective ? <p>Configuración vigente: versión {currentlyEffective.configVersion} desde {new Date(currentlyEffective.effectiveAt).toLocaleString()}.</p> : <p>No hay configuración vigente; la estimación nutricional está desactivada.</p>)}
    {!loading && versions[0] && Date.parse(versions[0].effectiveAt) > Date.now() && <p>La versión más reciente ({versions[0].configVersion}) todavía es futura; continúa vigente la versión anterior indicada arriba.</p>}
    {loading ? <p>Cargando versiones…</p> : versions.length === 0 ? <p>No hay ninguna configuración publicada. No se aplicará una estimación hasta que publiques una.</p> : <ol>{versions.map((item) => <li key={item.configVersion}>Versión {item.configVersion} · vigente desde {new Date(item.effectiveAt).toLocaleString()} · {item.sourceNote}</li>)}</ol>}
    <form className="surface admin-form-stack" onSubmit={(event) => { event.preventDefault(); if (pending) void publish(pending); else { try { const request = prepare(); setPending(request); void publish(request) } catch (cause) { setError(cause instanceof Error ? cause.message : 'Revisá la configuración.') } } }}>
      <h3>{pending ? 'Reintentar publicación' : 'Nueva versión'}</h3>
      <fieldset disabled={publishing || Boolean(pending)}><legend>Factores de actividad</legend>{activities.map(([key, label]) => <label className="field" key={key}><span>{label}</span><input inputMode="decimal" onChange={(e) => setDraft({ ...draft, factors: { ...draft.factors, [key]: e.target.value } })} required value={draft.factors[key] ?? ''} /></label>)}</fieldset>
      <fieldset disabled={publishing || Boolean(pending)}><legend>Ajustes por objetivo (kcal/día)</legend>{goals.map(([key, label]) => <div key={key}><strong>{label}</strong><div className="admin-form-grid"><label className="field"><span>Mínimo</span><input inputMode="numeric" onChange={(e) => setDraft({ ...draft, goals: { ...draft.goals, [key]: { ...draft.goals[key], minimum: e.target.value } } })} required value={draft.goals[key]?.minimum ?? ''} /></label><label className="field"><span>Máximo</span><input inputMode="numeric" onChange={(e) => setDraft({ ...draft, goals: { ...draft.goals, [key]: { ...draft.goals[key], maximum: e.target.value } } })} required value={draft.goals[key]?.maximum ?? ''} /></label></div></div>)}</fieldset>
      <label className="field"><span>Fuente / nota</span><textarea disabled={publishing || Boolean(pending)} maxLength={2000} onChange={(e) => setDraft({ ...draft, source: e.target.value })} required value={draft.source} /></label>
      <label className="field"><span>Fecha y hora de vigencia (hora local)</span><input disabled={publishing || Boolean(pending)} onChange={(e) => setDraft({ ...draft, effectiveAt: e.target.value })} required type="datetime-local" value={draft.effectiveAt} /></label>
      {pending && <p>Se conserva la misma fecha, contenido y versión esperada para que el reintento sea idempotente.</p>}
      {!pending && <p>Se publicará sobre la última versión {nextVersion}.</p>}
      <button className="button button-primary" disabled={publishing || loading} type="submit">{publishing ? 'Publicando…' : pending ? 'Reintentar publicación' : 'Publicar versión'}</button>
      {pending && <button className="button button-quiet" disabled={publishing} onClick={() => { setPending(null); setError('') }} type="button">Descartar reintento y editar</button>}
    </form>
  </section>
}
