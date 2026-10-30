import { LoadingScreen } from '../components/LoadingScreen'
import { useEffect, useRef, useState } from 'react'
import { AlertTriangle, Check, ChevronLeft, ChevronRight, Clock3, CookingPot, Lightbulb, Minus, Plus, Thermometer, UtensilsCrossed, X } from 'lucide-react'
import { Link, useNavigate, useParams, useSearchParams } from 'react-router-dom'
import { formatPantryAmount } from '../features/pantry/domain/pantry'
import { mockCookingRepository } from '../features/cooking/data/MockCookingRepository'
import { advanceStep, completeStep, cookingCompletionPath, createSession, getStepGuidance, moveStep, pauseStepTimer, remainingRecipeMinutes, remainingTimerMs, resetStepTimer, scaleIngredients, startStepTimer, type CookingSession } from '../features/cooking/domain/cooking'
import { mockRecipeRepository } from '../features/recipes/data/MockRecipeRepository'
import type { IngredientDeficit } from '../features/recipes/domain/recipeRules'
import type { Recipe } from '../features/recipes/domain/Recipe'
import { RecipeImage } from '../features/recipes/ui/RecipeImage'
import { parseRecipePortions } from '../features/recipes/domain/recipeRules'
import { useNotifications } from '../shared/notifications/NotificationProvider'

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
  const [searchParams, setSearchParams] = useSearchParams()
  const requestedPortions = parseRecipePortions(searchParams.get('portions'))
  return <CookingRecipePage id={id} requestedPortions={requestedPortions} setSearchParams={setSearchParams} key={id} />
}

function CookingRecipePage({ id, requestedPortions, setSearchParams }: { id: string; requestedPortions?: number; setSearchParams: ReturnType<typeof useSearchParams>[1] }) {
  const navigate = useNavigate()
  const { notify } = useNotifications()
  const [recipe, setRecipe] = useState<Recipe | null>(null)
  const [resumeMessage, setResumeMessage] = useState('')
  const [session, setSession] = useState<CookingSession | null>(null)
  const [stockCheck, setStockCheck] = useState<IngredientDeficit[]>([])
  const [stockVerified, setStockVerified] = useState(false)
  const [stockCheckError, setStockCheckError] = useState(false)
  const [loading, setLoading] = useState(true)
  const [finishing, setFinishing] = useState(false)
  const [saving, setSaving] = useState(false)
  const [persistingProgress, setPersistingProgress] = useState(false)
  const [now, setNow] = useState(Date.now)
  const finishingRef = useRef(false)
  const progressWriteRef = useRef(false)
  const chimedRef = useRef('')
  const notifiedTimerRef = useRef('')
  const audioRef = useRef<AudioContext | null>(null)

  useEffect(() => {
    let current = true
    void Promise.all([mockRecipeRepository.getById(id), mockCookingRepository.getSession(id)]).then(async ([found, saved]) => {
      if (!current) return
      setRecipe(found ?? null)
      if (found) {
        const activeSession = saved ? { ...saved, portions: requestedPortions ?? saved.portions } : { ...createSession(found), portions: requestedPortions ?? found.portions }
        setSession(activeSession)
        setResumeMessage(saved ? requestedPortions && requestedPortions !== saved.portions ? `Retomaste el paso guardado; las porciones se ajustaron de ${saved.portions} a ${requestedPortions}.` : 'Retomaste una sesión interrumpida. Tu paso y temporizador quedaron guardados.' : '')
        if (!saved || activeSession.portions !== saved.portions) {
          progressWriteRef.current = true
          setPersistingProgress(true)
          try { await mockCookingRepository.saveSession(activeSession) }
          catch { if (current) void notify({ type: 'error', title: 'No se pudo guardar el progreso', message: 'Revisá el espacio disponible del navegador e intentá de nuevo.' }) }
          finally { progressWriteRef.current = false; if (current) setPersistingProgress(false) }
        }
      }
    }).catch(() => { if (current) void notify({ type: 'error', title: 'No se pudo recuperar la receta', message: 'No se pudo recuperar la receta o el progreso guardado.' }) }).finally(() => { if (current) setLoading(false) })
    return () => { current = false }
  }, [id, requestedPortions, notify])

  useEffect(() => {
    if (!session?.timer?.deadlineAt) return
    const interval = window.setInterval(() => setNow(currentTimestamp()), 250)
    return () => window.clearInterval(interval)
  }, [session?.recipeId, session?.timer?.deadlineAt])

  useEffect(() => () => { void audioRef.current?.close().catch(() => { /* Sound is optional during cleanup. */ }) }, [])

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

  useEffect(() => {
    if (!session || !activeTimer?.deadlineAt || !finishedTimer) return
    const key = `${session.recipeId}:${activeTimer.deadlineAt}`
    if (notifiedTimerRef.current === key) return
    notifiedTimerRef.current = key
    void notify({ type: 'info', title: 'Temporizador terminado', message: 'Podés continuar cuando estés listo.' })
  }, [session, activeTimer, finishedTimer, notify])

  if (!recipe) {
    if (loading) return <LoadingScreen message="Cargando receta y progreso…" variant="fullscreen" />
    return <main className="cooking-missing"><h1>Receta no encontrada</h1><Link className="button button-primary" to="/recipes">Volver a recetas</Link></main>
  }
  if (!session || session.recipeId !== recipe.id || recipe.steps.length === 0) {
    return <main className="cooking-missing"><h1>Esta receta no tiene pasos válidos</h1><p>Podés volver a su detalle o elegir otra receta para cocinar.</p><Link className="button button-primary" to={`/recipes/${recipe.id}`}>Volver a la receta</Link></main>
  }

  const stepCount = recipe.steps.length
  const completedCount = session.completed.length
  const ingredients = scaleIngredients(recipe, session.portions)
  const guidance = getStepGuidance(recipe, session.stepIndex, session.portions)
  const estimatedRemaining = remainingRecipeMinutes(recipe, session.stepIndex, activeTimer ? remainingMs : undefined)

  async function update(next: CookingSession): Promise<boolean> {
    if (progressWriteRef.current) return false
    progressWriteRef.current = true
    setPersistingProgress(true)
    try {
      await mockCookingRepository.saveSession(next)
      setSession(next)
      return true
    } catch { void notify({ type: 'error', title: 'No se pudo guardar el progreso', message: 'Revisá el espacio disponible del navegador e intentá de nuevo.' }); return false }
    finally { progressWriteRef.current = false; setPersistingProgress(false) }
  }

  async function startTimer() {
    if (!guidance.durationMinutes) return
    try {
      audioRef.current ??= new AudioContext()
      void audioRef.current.resume().catch(() => { /* Timer remains usable without audio. */ })
    } catch { /* Sound is optional in browsers that block audio. */ }
    const startedAt = currentTimestamp()
    if (await update(startStepTimer(session!, guidance.durationMinutes * 60_000, startedAt))) setNow(startedAt)
  }

  function pauseTimer() {
    if (!activeTimer?.deadlineAt || finishedTimer) return
    void update(pauseStepTimer(session!, now))
  }

  async function leave() {
    if (persistingProgress || progressWriteRef.current) return
    if (await update({ ...session!, timer: undefined })) navigate(`/recipes/${recipe!.id}`)
  }

  async function completeAndConfirm() {
    const completed = { ...completeStep(session!, session!.stepIndex, stepCount), timer: undefined }
    if (await update(completed)) {
      setStockCheckError(false)
      try { setStockCheck(await mockCookingRepository.checkStock(recipe!, completed.portions)); setStockVerified(true); setFinishing(true) }
      catch { void notify({ type: 'error', title: 'No se pudo verificar la despensa', message: 'Podés finalizar sin descontar ingredientes.' }); setStockCheckError(true); setStockVerified(false); setFinishing(true); setStockCheck([]) }
    }
  }

  async function updatePortions(portions: number) {
    if (await update({ ...session!, portions })) setSearchParams((previous) => { const next = new URLSearchParams(previous); next.set('portions', String(portions)); return next }, { replace: true })
  }

  async function finish(discount: boolean) {
    if (finishingRef.current) return
    finishingRef.current = true
    setSaving(true)
    try {
      if (discount) {
        const currentCheck = await mockCookingRepository.checkStock(recipe!, session!.portions)
        const missing = currentCheck.filter((item) => item.missing > 0)
        if (missing.length > 0) {
          setStockCheck(currentCheck)
          setSaving(false)
          finishingRef.current = false
          return
        }
      }
      const result = await mockCookingRepository.finalize(recipe!, session!, discount)
      const exhausted = discount && result.exhaustedIngredients.length > 0 ? ` Se agotó el stock de ${result.exhaustedIngredients.join(', ')}.` : ''
      navigate(cookingCompletionPath, { replace: true, state: { completionMessage: `Terminaste ${recipe!.name}. Se agregó a tu historial.${exhausted}` } })
    } catch {
      finishingRef.current = false
      setSaving(false)
      setFinishing(false)
      void notify({ type: 'error', title: 'No se pudo finalizar', message: 'Revisá la despensa y el espacio disponible del navegador.' })
    }
  }

  return <div className="cooking-page">
    <header className="cooking-header"><button aria-label="Salir del modo cocina" className="cooking-icon-button" disabled={persistingProgress || saving} onClick={leave} type="button"><X size={23} /></button><div><span>COCINANDO</span><strong>{recipe.name}</strong></div><span aria-hidden="true" className="cooking-header-spacer" /></header>
    <div aria-label={`${completedCount} de ${stepCount} pasos completados`} className="cooking-progress" role="progressbar" aria-valuemax={stepCount} aria-valuemin={0} aria-valuenow={completedCount}><div style={{ width: `${completedCount / stepCount * 100}%` }} /></div>
    <main className="cooking-main">
      <section aria-labelledby="cooking-step-title" className="cooking-step">
        {resumeMessage && <p className="cooking-resumed" role="status">{resumeMessage}</p>}
        <p className="eyebrow">PASO {session.stepIndex + 1} DE {stepCount}</p>
        <div className="cooking-step-symbol"><CookingPot size={35} aria-hidden="true" /></div>
        <h1 id="cooking-step-title">{recipe.steps[session.stepIndex]}</h1>
        {session.completed.includes(session.stepIndex) && <p className="cooking-step-status"><Check size={17} aria-hidden="true" /> Paso completado</p>}
        {guidance.specialInstructions && <p className="cooking-special-instruction">{guidance.specialInstructions}</p>}
        <div className="cooking-guidance-grid">
          <section className="cooking-guidance-card" aria-labelledby="step-ingredients-title"><strong id="step-ingredients-title">Ingredientes de este paso</strong>{guidance.stepIngredients.length > 0 ? <ul>{guidance.stepIngredients.map((ingredient) => <li key={`${ingredient.name}-${ingredient.unit}`}><span>{ingredient.name}</span><b>{formatPantryAmount(ingredient.quantity, ingredient.unit)}</b></li>)}</ul> : <p>No hay ingredientes específicos indicados para este paso.</p>}</section>
          <section className="cooking-guidance-card" aria-labelledby="step-utensils-title"><strong id="step-utensils-title"><UtensilsCrossed size={17} aria-hidden="true" /> Necesitás</strong>{guidance.utensils.length > 0 ? <ul>{guidance.utensils.map((utensil) => <li key={utensil}>{utensil}</li>)}</ul> : <p>No se indicaron utensilios especiales.</p>}</section>
          {(guidance.temperature || guidance.durationMinutes > 0) && <section className="cooking-guidance-card"><strong><Clock3 size={17} aria-hidden="true" /> Tiempo y cocción</strong>{guidance.durationMinutes > 0 && <p>{guidance.durationMinutes} min para este paso</p>}{guidance.temperature && <p><Thermometer size={16} aria-hidden="true" /> {guidance.temperature}</p>}</section>}
          {guidance.tip && <aside className="cooking-guidance-card cooking-tip"><strong><Lightbulb size={17} aria-hidden="true" /> Tip de cocina</strong><p>{guidance.tip}</p></aside>}
          {guidance.warning && <aside className="cooking-guidance-card cooking-warning"><strong><AlertTriangle size={17} aria-hidden="true" /> Atención</strong><p>{guidance.warning}</p></aside>}
          {guidance.nextStepPreview && <section className="cooking-guidance-card"><strong>Próximo paso</strong><p>{guidance.nextStepPreview}</p></section>}
        </div>
        <p className="cooking-remaining"><Clock3 size={16} aria-hidden="true" /> Tiempo estimado restante: {estimatedRemaining > 0 ? `${estimatedRemaining} min` : 'sin estimación'}</p>
        {guidance.durationMinutes > 0 && <section aria-label="Temporizador del paso" className={`cooking-timer${finishedTimer ? ' finished' : ''}`}><span>Temporizador · {guidance.durationMinutes} min sugeridos</span><output aria-label="Tiempo restante" aria-live={finishedTimer ? 'assertive' : 'off'}>{formatTime(activeTimer ? remainingMs : guidance.durationMinutes * 60_000)}</output><div className="cooking-timer-actions">{activeTimer?.deadlineAt && !finishedTimer ? <button className="button button-quiet" disabled={persistingProgress} onClick={pauseTimer} type="button">Pausar</button> : !finishedTimer ? <button className="button button-quiet" disabled={persistingProgress} onClick={startTimer} type="button">{activeTimer ? 'Reanudar' : 'Iniciar'}</button> : null}{activeTimer && <button className="button button-quiet" disabled={persistingProgress} onClick={() => void update(resetStepTimer(session))} type="button">Reiniciar</button>}</div></section>}
      </section>
      <aside className="cooking-side"><RecipeImage className="cooking-recipe-image" recipe={recipe} /><div className="cooking-portions"><div><strong>Porciones</strong><small>Cantidades para esta preparación</small></div><div><button aria-label="Disminuir porciones" disabled={persistingProgress || session.portions <= 1} onClick={() => void updatePortions(session.portions - 1)} type="button"><Minus size={17} /></button><output aria-live="polite">{session.portions}</output><button aria-label="Aumentar porciones" disabled={persistingProgress || session.portions >= 20} onClick={() => void updatePortions(session.portions + 1)} type="button"><Plus size={17} /></button></div></div><details open><summary>Ingredientes necesarios</summary><ul>{ingredients.map((ingredient, index) => <li key={`${ingredient.name}-${ingredient.unit}-${index}`}><span>{ingredient.name}</span><strong>{formatPantryAmount(ingredient.quantity, ingredient.unit)}</strong></li>)}</ul></details></aside>
    </main>
    <footer className="cooking-footer"><button className="button button-quiet" disabled={persistingProgress || session.stepIndex === 0} onClick={() => void update(moveStep(session, -1, stepCount))} type="button"><ChevronLeft size={19} /> Anterior</button><span aria-live="polite">{persistingProgress ? 'Guardando progreso…' : `${completedCount} de ${stepCount} completados`}</span>{session.stepIndex === stepCount - 1 ? <button className="button button-primary" disabled={persistingProgress || saving} onClick={completeAndConfirm} type="button"><Check size={19} /> Finalizar</button> : <button className="button button-primary" disabled={persistingProgress || saving} onClick={() => void update(advanceStep(session, stepCount))} type="button">Siguiente <ChevronRight size={19} /></button>}</footer>
    {finishing && <dialog aria-labelledby="finish-cooking-title" className="pantry-dialog cooking-finish-dialog" onCancel={(event) => { if (saving) event.preventDefault(); else setFinishing(false) }} ref={(node) => { if (node && !node.open) node.showModal() }}><h2 id="finish-cooking-title">Finalizar preparación</h2><p>Se guardarán {session.portions} porciones en tu historial. ¿Querés descontar los ingredientes usados de la despensa?</p>{stockCheckError && <div className="form-message error" role="alert"><strong>No se pudo verificar la despensa.</strong><p>Podés finalizar sin descontar ingredientes.</p></div>}{stockVerified && <section aria-labelledby="cooking-stock-check-title" className="cooking-stock-check"><h3 id="cooking-stock-check-title">Control de despensa antes del descuento</h3><ul>{stockCheck.map((item, index) => <li key={`${item.ingredient.name}-${item.ingredient.unit}-${index}`}><strong>{item.ingredient.name}</strong><dl><div><dt>Disponible</dt><dd>{formatPantryAmount(item.available, item.ingredient.unit)}</dd></div><div><dt>Requerido</dt><dd>{formatPantryAmount(item.required, item.ingredient.unit)}</dd></div><div><dt>Faltante</dt><dd>{formatPantryAmount(item.missing, item.ingredient.unit)}</dd></div></dl><span>{item.missing === 0 ? 'Stock suficiente' : 'Stock insuficiente'}</span></li>)}</ul></section>}{stockVerified && stockCheck.some((item) => item.missing > 0) && <div className="form-message error" role="alert"><strong>No se puede descontar porque falta stock.</strong><p>Podés actualizar la despensa o finalizar sin descuento.</p></div>}<div className="cooking-finish-actions"><button className="button button-quiet" disabled={saving} onClick={() => setFinishing(false)} type="button">Seguir cocinando</button><button className="button button-quiet" disabled={saving} onClick={() => void finish(false)} type="button">Sin descuento</button><button className="button button-primary" disabled={saving || !stockVerified || stockCheck.some((item) => item.missing > 0)} onClick={() => void finish(true)} type="button">Descontar y finalizar</button></div></dialog>}
  </div>
}
