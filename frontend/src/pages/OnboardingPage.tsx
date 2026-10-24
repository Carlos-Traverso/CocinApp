import { ArrowLeft, ArrowRight, CircleAlert } from 'lucide-react'
import { type FormEvent, useEffect, useRef, useState } from 'react'
import { useNavigate } from 'react-router-dom'
import { BrandLogo } from '../components/BrandLogo'
import { profileRepository } from '../features/profile/data/ProfileRepository'
import { calculateAge, estimateForProfile, profileIsComplete, type ProfileDraft } from '../features/profile/domain/profile'
import { EnergySummary } from '../features/profile/ui/EnergySummary'
import { ProfileFields } from '../features/profile/ui/ProfileFields'
import { useNotifications } from '../shared/notifications/NotificationProvider'

function profileFieldValidationMessage(field: HTMLInputElement | HTMLSelectElement): string {
  if (field.validity.valueMissing) return 'Completá los campos obligatorios del perfil.'
  if (field.validity.typeMismatch) return 'Ingresá un correo electrónico válido.'
  if (field.validity.rangeUnderflow || field.validity.rangeOverflow || field.validity.stepMismatch || field.validity.badInput) return 'Revisá el rango y el formato de las medidas.'
  return 'Revisá el dato ingresado.'
}

export function OnboardingPage() {
  const navigate = useNavigate()
  const { notify } = useNotifications()
  const [profile, setProfile] = useState<ProfileDraft>({})
  const [loading, setLoading] = useState(true)
  const [saving, setSaving] = useState(false)
  const [validationError, setValidationError] = useState('')
  const invalidFieldRef = useRef<HTMLInputElement | HTMLSelectElement | null>(null)
  const formRef = useRef<HTMLFormElement>(null)
  useEffect(() => { void profileRepository.getProfile().then(setProfile).catch(() => { void notify({ type: 'error', title: 'No se pudo cargar el perfil', message: 'No se pudo cargar el perfil.' }) }).finally(() => setLoading(false)) }, [notify])

  const age = profile.birthDate ? calculateAge(profile.birthDate) : undefined
  const estimate = estimateForProfile(profile)

  async function saveAndContinue(event: FormEvent<HTMLFormElement>) {
    event.preventDefault()
    const form = event.currentTarget
    clearValidationError()
    if (!form.checkValidity()) {
      const invalidField = form.querySelector<HTMLInputElement | HTMLSelectElement>(':invalid')
      invalidField?.focus()
      showValidationError(invalidField, invalidField ? profileFieldValidationMessage(invalidField) : 'Revisá los datos ingresados.')
      return
    }
    if (!profileIsComplete(profile) || age === undefined || age < 18 || age > 100) {
      const field = formRef.current?.querySelector<HTMLInputElement>('[name="birthDate"]') ?? null
      field?.focus()
      showValidationError(field, 'Completá los datos requeridos. La configuración inicial está orientada a personas adultas.')
      return
    }
    setSaving(true)
    try { await profileRepository.saveProfile(profile); navigate('/profile') }
    catch { await notify({ type: 'error', title: 'No se pudo guardar el perfil', message: 'Revisá el espacio disponible del navegador e intentá de nuevo.' }) }
    finally { setSaving(false) }
  }

  function showValidationError(field: HTMLInputElement | HTMLSelectElement | null, message: string) {
    invalidFieldRef.current = field
    if (field) {
      const ids = field.getAttribute('aria-describedby')?.split(/\s+/).filter(Boolean) ?? []
      if (!ids.includes('setup-validation-error')) field.setAttribute('aria-describedby', [...ids, 'setup-validation-error'].join(' '))
    }
    setValidationError(message)
  }

  function clearValidationError() {
    const field = invalidFieldRef.current
    if (field) {
      const ids = field.getAttribute('aria-describedby')?.split(/\s+/).filter((id) => id && id !== 'setup-validation-error') ?? []
      if (ids.length) field.setAttribute('aria-describedby', ids.join(' '))
      else field.removeAttribute('aria-describedby')
    }
    invalidFieldRef.current = null
    setValidationError('')
  }

  return <main className="setup-page">
    <header className="setup-header"><a aria-label="CocinAPP, inicio" className="access-wordmark" href="/"><BrandLogo /></a><span>Configuración inicial</span></header>
    <section className="setup-card" aria-labelledby="setup-title">
      <div className="setup-progress"><span>Configuración inicial</span><strong>Perfil y preferencias</strong><div><i /></div></div>
      <p className="eyebrow">PRIMEROS PASOS</p>
      <h1 id="setup-title">Organicemos tu perfil</h1>
      <p className="setup-lead">Estos datos permiten mostrar una referencia de energía y priorizar recetas compatibles. Podés modificarlos cuando quieras.</p>
      <form noValidate onInput={clearValidationError} onChange={clearValidationError} onSubmit={saveAndContinue} ref={formRef}>
        {validationError && <p className="form-message error" id="setup-validation-error" role="alert">{validationError}</p>}
        {loading ? <p role="status">Cargando preferencias…</p> : <ProfileFields profile={profile} onChange={(changes) => { setProfile({ ...profile, ...changes }) }} />}
        {age !== undefined && <p className="calculated-age">Edad calculada: <strong>{age} años</strong></p>}
        {estimate && <EnergySummary estimate={estimate} />}
        <p className="medical-note"><CircleAlert size={17} /> Esta estimación es informativa; no reemplaza el asesoramiento de un profesional de nutrición. Las etiquetas dietéticas no garantizan ausencia de contaminación cruzada.</p>
        <div className="setup-actions"><button className="button button-quiet" onClick={() => navigate('/')} type="button"><ArrowLeft size={17} /> Volver</button><button className="button button-primary" disabled={loading || saving} type="submit">{saving ? 'Guardando…' : 'Guardar y continuar'} <ArrowRight size={17} /></button></div>
      </form>
    </section>
  </main>
}
