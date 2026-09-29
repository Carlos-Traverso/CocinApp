import { useEffect, useRef, useState } from 'react'
import { Check, ChevronLeft, ChevronRight, CookingPot, Minus, Plus, X } from 'lucide-react'
import { Link, useNavigate, useParams } from 'react-router-dom'
import { formatPantryAmount } from '../features/pantry/domain/pantry'
import { finalizeCookingSession, readCookingSession, saveCookingSession } from '../features/cooking/data/localCookingStore'
import { advanceStep, completeStep, cookingCompletionPath, createSession, moveStep, remainingTimerMs, scaleIngredients, type CookingSession } from '../features/cooking/domain/cooking'
import { getRecipeById } from '../features/recipes/data/availableRecipes'
import { RecipeImage } from '../features/recipes/ui/RecipeImage'

function formatTime(milliseconds: number): string {
  const seconds = Math.ceil(milliseconds / 1000)
  return `${String(Math.floor(seconds / 60)).padStart(2, '0')}:${String(seconds % 60).padStart(2, '0')}`
}

function currentTimestamp(): number { return Date.now() }

function playTimerSound(context: AudioContext | null) {
  if (!context || context.state !== 'running') return
  try {
    const oscillator = context.createOscillator()
    const gain = context.createGain()
    oscillator.frequency.value = 880
    gain.gain.setValueAtTime(0.08, context.currentTime)
    gain.gain.exponentialRampToValueAtTime(0.001, context.currentTime + 0.35)
    oscillator.connect(gain)
    gain.connect(context.destination)
    oscillator.start()
    oscillator.stop(context.currentTime + 0.35)
  } catch { /* The visual completion notice remains available. */ }
}

export function CookingPage() {
  const { id = '' } = useParams()
  return <CookingRecipePage id={id} key={id} />
}

function CookingRecipePage({ id }: { id: string }) {
  const navigate = useNavigate()
  const recipe = getRecipeById(id)
  const [session, setSession] = useState<CookingSession | null>(() => recipe ? readCookingSession(recipe.id) ?? createSession(recipe) : null)
  const [finishing, setFinishing] = useState(false)
  const [saving, setSaving] = useState(false)
  const [error, setError] = useState('')
  const [now, setNow] = useState(Date.now)
  const finishingRef = useRef(false)
  const chimedRef = useRef('')
  const audioRef = useRef<AudioContext | null>(null)

  useEffect(() => {
    if (session && !readCookingSession(session.recipeId)) {
      try { saveCookingSession(session) } catch { /* A later action will show the storage error. */ }
    }
  }, [session])

  useEffect(() => {
    if (!session?.timer?.deadlineAt) return
    const interval = window.setInterval(() => setNow(currentTimestamp()), 250)
    return () => window.clearInterval(interval)
  }, [session?.recipeId, session?.timer?.deadlineAt])

  useEffect(() => () => { void audioRef.current?.close() }, [])

  const activeTimer = session && session.timer?.stepIndex === session.stepIndex ? session.timer : undefined
  const remainingMs = activeTimer ? remainingTimerMs(activeTimer, now) : 0
  const finishedTimer = Boolean(activeTimer?.deadlineAt && remainingMs === 0)
  useEffect(() => {
    if (!session || !activeTimer?.deadlineAt || !finishedTimer) return
    const key = `${session.recipeId}:${activeTimer.deadlineAt}`
    if (chimedRef.current === key) return
    chimedRef.current = key
    playTimerSound(audioRef.current)
  }, [session, activeTimer, finishedTimer])

  if (!recipe || !session || session.recipeId !== recipe.id || recipe.steps.length === 0) {
    return <main className="cooking-missing"><h1>Receta no encontrada</h1><Link className="button button-primary" to="/recipes">Volver a recetas</Link></main>
  }

  const stepCount = recipe.steps.length
  const completedCount = session.completed.length
  const stepMeta = recipe.stepMeta?.[session.stepIndex]
  const ingredients = scaleIngredients(recipe, session.portions)

  function update(next: CookingSession): boolean {
    try { saveCookingSession(next); setSession(next); setError(''); return true }
    catch { setError('No se pudo guardar el progreso en este navegador.'); return false }
  }

  function startTimer() {
    if (!stepMeta?.minutes) return
    try {
      audioRef.current ??= new AudioContext()
      void audioRef.current.resume()
    } catch { /* Sound is optional in browsers that block audio. */ }
    const duration = activeTimer && remainingMs > 0 ? remainingMs : stepMeta.minutes * 60_000
    const startedAt = currentTimestamp()
    if (update({ ...session!, timer: { stepIndex: session!.stepIndex, remainingMs: duration, deadlineAt: startedAt + duration } })) setNow(startedAt)
  }

  function pauseTimer() {
    if (!activeTimer?.deadlineAt || finishedTimer) return
    update({ ...session!, timer: { stepIndex: session!.stepIndex, remainingMs } })
  }

  function leave() {
    if ((completedCount > 0 || session!.stepIndex > 0) && !window.confirm('¿Salir del modo cocina? El progreso quedará guardado.')) return
    if (update({ ...session!, timer: undefined })) navigate(`/recipes/${recipe!.id}`)
  }

  function completeAndConfirm() {
    if (update({ ...completeStep(session!, session!.stepIndex, stepCount), timer: undefined })) setFinishing(true)
  }

  function finish(discount: boolean) {
    if (finishingRef.current) return
    finishingRef.current = true
    setSaving(true)
    try {
      finalizeCookingSession(recipe!, session!, discount)
      navigate(cookingCompletionPath, { replace: true, state: { completionMessage: `Terminaste ${recipe!.name}. Se agregó a tu historial.` } })
    } catch {
      finishingRef.current = false
      setSaving(false)
      setFinishing(false)
      setError('No se pudo finalizar. Revisá el espacio disponible del navegador.')
    }
  }

  return <div className="cooking-page">
    <header className="cooking-header"><button aria-label="Salir del modo cocina" className="cooking-icon-button" onClick={leave} type="button"><X size={23} /></button><div><span>COCINANDO</span><strong>{recipe.name}</strong></div><span aria-hidden="true" className="cooking-header-spacer" /></header>
    <div aria-label={`${completedCount} de ${stepCount} pasos completados`} className="cooking-progress" role="progressbar" aria-valuemax={stepCount} aria-valuemin={0} aria-valuenow={completedCount}><div style={{ width: `${completedCount / stepCount * 100}%` }} /></div>
    <main className="cooking-main">
      <section aria-labelledby="cooking-step-title" className="cooking-step">
        <p className="eyebrow">PASO {session.stepIndex + 1} DE {stepCount}</p>
        <div className="cooking-step-symbol"><CookingPot size={35} aria-hidden="true" /></div>
        <h1 id="cooking-step-title">{recipe.steps[session.stepIndex]}</h1>
        {session.completed.includes(session.stepIndex) && <p className="cooking-step-status"><Check size={17} aria-hidden="true" /> Paso completado</p>}
        {stepMeta?.tip && <aside className="cooking-tip"><strong>Consejo para este paso</strong><p>{stepMeta.tip}</p></aside>}
        {stepMeta?.minutes && <section aria-label="Temporizador del paso" className="cooking-timer"><span>Tiempo sugerido: {stepMeta.minutes} min</span><output aria-label="Tiempo restante" aria-live="off">{formatTime(activeTimer ? remainingMs : stepMeta.minutes * 60_000)}</output>{finishedTimer && <p role="alert">Tiempo terminado. Podés continuar cuando estés listo.</p>}<div className="cooking-timer-actions">{activeTimer?.deadlineAt && !finishedTimer ? <button className="button button-quiet" onClick={pauseTimer} type="button">Pausar</button> : !finishedTimer ? <button className="button button-quiet" onClick={startTimer} type="button">{activeTimer ? 'Reanudar' : 'Iniciar'}</button> : null}{activeTimer && <button className="button button-quiet" onClick={() => update({ ...session, timer: undefined })} type="button">Reiniciar</button>}</div></section>}
        {error && <p className="form-message error" role="alert">{error}</p>}
      </section>
      <aside className="cooking-side"><RecipeImage className="cooking-recipe-image" recipe={recipe} /><div className="cooking-portions"><div><strong>Porciones</strong><small>Cantidades para esta preparación</small></div><div><button aria-label="Disminuir porciones" disabled={session.portions <= 1} onClick={() => update({ ...session, portions: session.portions - 1 })} type="button"><Minus size={17} /></button><output aria-live="polite">{session.portions}</output><button aria-label="Aumentar porciones" disabled={session.portions >= 20} onClick={() => update({ ...session, portions: session.portions + 1 })} type="button"><Plus size={17} /></button></div></div><details open><summary>Ingredientes necesarios</summary><ul>{ingredients.map((ingredient) => <li key={ingredient.name}><span>{ingredient.name}</span><strong>{formatPantryAmount(ingredient.quantity, ingredient.unit)}</strong></li>)}</ul></details></aside>
    </main>
    <footer className="cooking-footer"><button className="button button-quiet" disabled={session.stepIndex === 0} onClick={() => update(moveStep(session, -1, stepCount))} type="button"><ChevronLeft size={19} /> Anterior</button><span>{completedCount} de {stepCount} completados</span>{session.stepIndex === stepCount - 1 ? <button className="button button-primary" onClick={completeAndConfirm} type="button"><Check size={19} /> Finalizar</button> : <button className="button button-primary" onClick={() => update(advanceStep(session, stepCount))} type="button">Siguiente <ChevronRight size={19} /></button>}</footer>
    {finishing && <dialog aria-labelledby="finish-cooking-title" className="pantry-dialog cooking-finish-dialog" onCancel={() => setFinishing(false)} ref={(node) => { if (node && !node.open) node.showModal() }}><h2 id="finish-cooking-title">Finalizar preparación</h2><p>Se guardarán {session.portions} porciones en tu historial. ¿Querés descontar los ingredientes disponibles de la despensa?</p><div className="cooking-finish-actions"><button className="button button-quiet" disabled={saving} onClick={() => setFinishing(false)} type="button">Seguir cocinando</button><button className="button button-quiet" disabled={saving} onClick={() => finish(false)} type="button">Sin descuento</button><button className="button button-primary" disabled={saving} onClick={() => finish(true)} type="button">Descontar y finalizar</button></div></dialog>}
  </div>
}
