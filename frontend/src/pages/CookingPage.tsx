import { useEffect, useState } from 'react'
import { Check, ChevronLeft, ChevronRight, CookingPot, Minus, Plus, X } from 'lucide-react'
import { Link, useNavigate, useParams } from 'react-router-dom'
import { readPantryItems, writePantryItems } from '../features/pantry/data/localPantryStore'
import { formatPantryAmount } from '../features/pantry/domain/pantry'
import { clearCookingSession, readCookingSession, readHistory, saveCookingSession, writeHistory } from '../features/cooking/data/localCookingStore'
import { completeStep, createSession, deductIngredients, moveStep, recordPreparation, scaleIngredients, type CookingSession } from '../features/cooking/domain/cooking'
import { getRecipeById } from '../features/recipes/data/availableRecipes'

export function CookingPage() {
  const { id = '' } = useParams()
  const navigate = useNavigate()
  const recipe = getRecipeById(id)
  const [session, setSession] = useState<CookingSession | null>(() => recipe ? readCookingSession(recipe.id) ?? createSession(recipe) : null)
  const [finishing, setFinishing] = useState(false)
  const [error, setError] = useState('')

  useEffect(() => {
    if (session && !readCookingSession(session.recipeId)) {
      try { saveCookingSession(session) } catch { /* Changes will show a storage error when attempted. */ }
    }
  }, [session])

  if (!recipe || !session || session.recipeId !== recipe.id) return <main className="cooking-missing"><h1>Receta no encontrada</h1><Link className="button button-primary" to="/recipes">Volver a recetas</Link></main>

  const currentSession = session
  const stepCount = recipe.steps.length
  const completedCount = session.completed.length
  const allDone = completedCount === stepCount
  const ingredients = scaleIngredients(recipe, session.portions)

  function update(next: CookingSession) {
    try { saveCookingSession(next); setSession(next); setError('') }
    catch { setError('No se pudo guardar el progreso en este navegador.') }
  }

  function leave() {
    if ((completedCount > 0 || currentSession.stepIndex > 0) && !window.confirm('¿Salir del modo cocina? El progreso quedará guardado.')) return
    navigate(`/recipes/${recipe!.id}`)
  }

  function finish(discount: boolean) {
    const beforeHistory = readHistory()
    const beforePantry = readPantryItems()
    let historySaved = false
    let pantrySaved = false
    try {
      writeHistory(recordPreparation(beforeHistory, session!))
      historySaved = true
      if (discount) { writePantryItems(deductIngredients(beforePantry, recipe!, session!.portions)); pantrySaved = true }
      clearCookingSession(recipe!.id)
      navigate('/history')
    } catch {
      try {
        if (historySaved) writeHistory(beforeHistory)
        if (pantrySaved) writePantryItems(beforePantry)
      } catch { /* Keep the original error visible. */ }
      setFinishing(false)
      setError('No se pudo finalizar. Revisá el espacio disponible del navegador.')
    }
  }

  return <div className="cooking-page">
    <header className="cooking-header"><button aria-label="Salir del modo cocina" className="cooking-icon-button" onClick={leave} type="button"><X size={23} /></button><div><span>COCINANDO</span><strong>{recipe.name}</strong></div><span aria-hidden="true" className="cooking-header-spacer" /></header>
    <div aria-label={`${completedCount} de ${stepCount} pasos completados`} className="cooking-progress" role="progressbar" aria-valuemax={stepCount} aria-valuemin={0} aria-valuenow={completedCount}><div style={{ width: `${completedCount / stepCount * 100}%` }} /></div>
    <main className="cooking-main"><section aria-labelledby="cooking-step-title" className="cooking-step"><p className="eyebrow">PASO {session.stepIndex + 1} DE {stepCount}</p><div className="cooking-step-symbol"><CookingPot size={35} aria-hidden="true" /></div><h1 id="cooking-step-title">{recipe.steps[session.stepIndex]}</h1><label className="cooking-complete"><input checked={session.completed.includes(session.stepIndex)} onChange={() => update(completeStep(session, session.stepIndex, stepCount))} type="checkbox" /> <span>{session.completed.includes(session.stepIndex) ? 'Paso completado' : 'Marcar paso como completado'}</span></label>{error && <p className="form-message error" role="alert">{error}</p>}</section>
    <aside className="cooking-side"><div className="cooking-portions"><div><strong>Porciones</strong><small>Cantidades para esta preparación</small></div><div><button aria-label="Disminuir porciones" disabled={session.portions <= 1} onClick={() => update({ ...session, portions: session.portions - 1 })} type="button"><Minus size={17} /></button><output aria-live="polite">{session.portions}</output><button aria-label="Aumentar porciones" disabled={session.portions >= 20} onClick={() => update({ ...session, portions: session.portions + 1 })} type="button"><Plus size={17} /></button></div></div><details open><summary>Ingredientes necesarios</summary><ul>{ingredients.map((ingredient) => <li key={ingredient.name}><span>{ingredient.name}</span><strong>{formatPantryAmount(ingredient.quantity, ingredient.unit)}</strong></li>)}</ul></details></aside></main>
    <footer className="cooking-footer"><button className="button button-quiet" disabled={session.stepIndex === 0} onClick={() => update(moveStep(session, -1, stepCount))} type="button"><ChevronLeft size={19} /> Anterior</button><span>{completedCount} de {stepCount} completados</span>{session.stepIndex === stepCount - 1 ? <button className="button button-primary" disabled={!allDone} onClick={() => setFinishing(true)} type="button"><Check size={19} /> Finalizar</button> : <button className="button button-primary" onClick={() => update(moveStep(session, 1, stepCount))} type="button">Siguiente <ChevronRight size={19} /></button>}</footer>
    {finishing && <dialog aria-labelledby="finish-cooking-title" className="pantry-dialog cooking-finish-dialog" onCancel={() => setFinishing(false)} ref={(node) => { if (node && !node.open) node.showModal() }}><h2 id="finish-cooking-title">Finalizar preparación</h2><p>Se guardarán {session.portions} porciones en tu historial. ¿Querés descontar los ingredientes disponibles de la despensa?</p><div className="cooking-finish-actions"><button className="button button-quiet" onClick={() => setFinishing(false)} type="button">Seguir cocinando</button><button className="button button-quiet" onClick={() => finish(false)} type="button">Sin descuento</button><button className="button button-primary" onClick={() => finish(true)} type="button">Descontar y finalizar</button></div></dialog>}
  </div>
}
