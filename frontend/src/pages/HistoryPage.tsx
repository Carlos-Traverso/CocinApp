import { useState } from 'react'
import { ArrowLeft, CookingPot, Trash2 } from 'lucide-react'
import { Link } from 'react-router-dom'
import { readHistory, writeHistory } from '../features/cooking/data/localCookingStore'
import type { PreparationEvent } from '../features/cooking/domain/cooking'
import { getAvailableRecipes, getRecipeById } from '../features/recipes/data/availableRecipes'
import { RecipeImage } from '../features/recipes/ui/RecipeImage'

export function HistoryPage() {
  const [history, setHistory] = useState<PreparationEvent[]>(readHistory)
  const [error, setError] = useState('')
  const recent = [...history].sort((a, b) => b.cookedAt.localeCompare(a.cookedAt))

  function persist(next: PreparationEvent[]) {
    try { writeHistory(next); setHistory(next); setError('') }
    catch { setError('No se pudo actualizar el historial en este navegador.') }
  }

  function remove(event: PreparationEvent) {
    if (window.confirm('¿Eliminar esta preparación del historial?')) persist(history.filter((item) => item.id !== event.id))
  }

  function clear() {
    if (window.confirm('¿Eliminar todo el historial de preparaciones?')) persist([])
  }

  return <div className="page history-page"><header className="page-heading"><div><Link className="back-link" to="/recipes"><ArrowLeft size={16} /> Recetas</Link><p className="eyebrow">TU COCINA</p><h1>Historial de preparaciones</h1><p className="page-lead">Recetas que cocinaste en este navegador.</p></div>{history.length > 0 && <button className="button button-quiet" onClick={clear} type="button"><Trash2 size={17} /> Limpiar historial</button>}</header>{error && <p className="form-message error" role="alert">{error}</p>}{recent.length === 0 ? <section className="pantry-empty"><CookingPot size={34} aria-hidden="true" /><h2>Todavía no cocinaste una receta</h2><p>Elegí una receta y empezá el modo cocina.</p><Link className="button button-primary" to="/recipes">Explorar recetas</Link></section> : <section aria-label="Preparaciones recientes" className="history-list">{recent.map((event) => { const recipe = getRecipeById(event.recipeId, true); if (!recipe) return null; const active = getAvailableRecipes().some((item) => item.id === recipe.id); const count = history.filter((item) => item.recipeId === event.recipeId).length; return <article className="history-row" key={event.id}><RecipeImage className="history-symbol" recipe={recipe} /><div className="history-copy"><h2>{recipe.name}</h2><p>{new Date(event.cookedAt).toLocaleString('es-AR', { dateStyle: 'medium', timeStyle: 'short' })} · {event.portions} {event.portions === 1 ? 'porción' : 'porciones'} · {count} {count === 1 ? 'vez' : 'veces'} preparada{!active && ' · Inactiva'}</p></div><div className="history-actions"><Link className="button button-quiet" to={`/recipes/${recipe.id}`}>Ver receta</Link>{active && <Link className="button button-primary" to={`/recipes/${recipe.id}/cook`}>Cocinar otra vez</Link>}<button aria-label={`Eliminar preparación de ${recipe.name}`} className="pantry-icon-button" onClick={() => remove(event)} type="button"><Trash2 size={17} /></button></div></article> })}</section>}</div>
}
