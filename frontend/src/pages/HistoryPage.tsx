import { LoadingScreen } from '../components/LoadingScreen'
import { useEffect, useState } from 'react'
import { ArrowLeft, CookingPot, Trash2 } from 'lucide-react'
import { Link } from 'react-router-dom'
import { mockCookingRepository } from '../features/cooking/data/MockCookingRepository'
import type { PreparationEvent } from '../features/cooking/domain/cooking'
import { mockRecipeRepository } from '../features/recipes/data/MockRecipeRepository'
import type { Recipe } from '../features/recipes/domain/Recipe'
import { RecipeImage } from '../features/recipes/ui/RecipeImage'
import { useNotifications } from '../shared/notifications/NotificationProvider'

export function HistoryPage() {
  const { notify } = useNotifications()
  const [history, setHistory] = useState<PreparationEvent[]>([])
  const [recipes, setRecipes] = useState<Recipe[]>([])
  const [activeRecipes, setActiveRecipes] = useState<Recipe[]>([])
  const [loading, setLoading] = useState(true)
  const [loadFailed, setLoadFailed] = useState(false)
  const [loadAttempt, setLoadAttempt] = useState(0)
  const recent = [...history].sort((a, b) => b.cookedAt.localeCompare(a.cookedAt))

  useEffect(() => {
    let current = true
    void Promise.all([mockCookingRepository.getHistory(), mockRecipeRepository.listKnown(), mockRecipeRepository.list()])
      .then(([events, known, active]) => { if (current) { setHistory(events); setRecipes(known); setActiveRecipes(active) } })
      .catch(() => { if (current) { setLoadFailed(true); void notify({ type: 'error', title: 'No se pudo cargar el historial', message: 'Intentá volver a abrir el historial.' }) } })
      .finally(() => { if (current) setLoading(false) })
    return () => { current = false }
  }, [loadAttempt, notify])

  function retryLoad() {
    setLoadFailed(false)
    setLoading(true)
    setLoadAttempt((attempt) => attempt + 1)
  }

  async function remove(event: PreparationEvent) {
    if (!await notify({ type: 'warning', title: 'Eliminar preparación', message: '¿Eliminar esta preparación del historial?', confirmLabel: 'Eliminar', cancelLabel: 'Cancelar' })) return
    try { await mockCookingRepository.removeHistoryEntry(event.id); setHistory((entries) => entries.filter((item) => item.id !== event.id)) }
    catch { await notify({ type: 'error', title: 'No se pudo actualizar el historial', message: 'Revisá el espacio disponible del navegador e intentá de nuevo.' }) }
  }

  async function clear() {
    if (!await notify({ type: 'warning', title: 'Limpiar historial', message: '¿Eliminar todo el historial de preparaciones?', confirmLabel: 'Limpiar historial', cancelLabel: 'Cancelar' })) return
    try { await mockCookingRepository.clearHistory(); setHistory([]) }
    catch { await notify({ type: 'error', title: 'No se pudo actualizar el historial', message: 'Revisá el espacio disponible del navegador e intentá de nuevo.' }) }
  }

  return <div className="page history-page"><header className="page-heading"><div><Link className="back-link" to="/recipes"><ArrowLeft size={16} /> Recetas</Link><p className="eyebrow">TU COCINA</p><h1>Historial de preparaciones</h1><p className="page-lead">Recetas que cocinaste en este navegador.</p></div>{history.length > 0 && <button className="button button-quiet" onClick={() => void clear()} type="button"><Trash2 size={17} /> Limpiar historial</button>}</header>{loading ? <LoadingScreen message="Cargando historial…" variant="section" /> : loadFailed ? <section className="pantry-empty"><h2>No se pudo cargar el historial</h2><p>Volvé a intentarlo para consultar tus preparaciones.</p><button className="button button-primary" onClick={retryLoad} type="button">Reintentar</button></section> : recent.length === 0 ? <section className="pantry-empty"><CookingPot size={34} aria-hidden="true" /><h2>Todavía no cocinaste una receta</h2><p>Elegí una receta y empezá el modo cocina.</p><Link className="button button-primary" to="/recipes">Explorar recetas</Link></section> : <section aria-label="Preparaciones recientes" className="history-list">{recent.map((event) => { const recipe = recipes.find((item) => item.id === event.recipeId); if (!recipe) return null; const active = activeRecipes.some((item) => item.id === recipe.id); const count = history.filter((item) => item.recipeId === event.recipeId).length; return <article className="history-row" key={event.id}><RecipeImage className="history-symbol" recipe={recipe} /><div className="history-copy"><h2>{recipe.name}</h2><p>{new Date(event.cookedAt).toLocaleString('es-AR', { dateStyle: 'medium', timeStyle: 'short' })} · {event.portions} {event.portions === 1 ? 'porción' : 'porciones'} · {count} {count === 1 ? 'vez' : 'veces'} preparada{!active && ' · Inactiva'}</p></div><div className="history-actions"><Link className="button button-quiet" to={`/recipes/${recipe.id}`}>Ver receta</Link>{active && <Link className="button button-primary" to={`/recipes/${recipe.id}/cook`}>Cocinar otra vez</Link>}<button aria-label={`Eliminar preparación de ${recipe.name}`} className="pantry-icon-button" onClick={() => void remove(event)} type="button"><Trash2 size={17} /></button></div></article> })}</section>}</div>
}
