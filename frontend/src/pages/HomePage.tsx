import { Clock3, History, PackageCheck, SunMedium } from 'lucide-react'
import { Link } from 'react-router-dom'
import { readHistory } from '../features/cooking/data/localCookingStore'
import { buildCookingSuggestions, recentPreparations, recommendRecipeForTime } from '../features/dashboard/domain/dashboard'
import { readPantryItems } from '../features/pantry/data/localPantryStore'
import { getAvailableRecipes, getRecipeById } from '../features/recipes/data/availableRecipes'
import { readFavoriteIds } from '../features/recipes/data/localFavoritesStore'
import type { Recipe } from '../features/recipes/domain/Recipe'
import { RecipeImage } from '../features/recipes/ui/RecipeImage'

function Artwork({ recipe, compact = false }: { recipe: Recipe; compact?: boolean }) {
  return <RecipeImage className={`dashboard-suggestion-art${compact ? ' compact' : ''}`} recipe={recipe} />
}

export function HomePage() {
  const recipes = getAvailableRecipes()
  const pantry = readPantryItems()
  const history = readHistory()
  const now = new Date()
  const suggestions = buildCookingSuggestions(recipes, pantry, now)
  const timeSuggestion = recommendRecipeForTime(recipes, now.getHours(), { pantry, favoriteIds: readFavoriteIds(), history, today: now })
  const recent = recentPreparations(history, recipes.map((recipe) => recipe.id))

  return <div className="page dashboard-page dashboard-focus-page">
    <header className="dashboard-focus-heading"><div><p className="eyebrow">MI COCINA</p><h1>Panel</h1><p>Ideas basadas en tu despensa, tu horario y tus preparaciones.</p></div></header>

    <section aria-labelledby="cook-today-title" className="dashboard-panel-section">
      <div className="section-header"><div><p className="dashboard-recommendation-kicker"><PackageCheck aria-hidden="true" size={17} /> Según tu despensa</p><h2 id="cook-today-title">Qué podés cocinar hoy</h2></div></div>
      {suggestions.length === 0 ? <div className="recipe-rail-empty"><PackageCheck aria-hidden="true" size={20} /><span>No hay recetas completas o con hasta dos ingredientes faltantes.</span></div> : <div className="dashboard-suggestion-list">{suggestions.map((suggestion) => <article className="dashboard-recommendation" key={suggestion.recipe.id}><div className="dashboard-recommendation-copy"><h3>{suggestion.recipe.name}</h3><p>{suggestion.reason}</p><div className="dashboard-recommendation-meta"><span>{suggestion.availableCount} disponibles</span><span>{suggestion.missingNames.length} faltantes</span><span><Clock3 aria-hidden="true" size={15} /> {suggestion.recipe.minutes} min</span></div><div className="dashboard-recommendation-actions"><Link className="button button-quiet" to={`/recipes/${suggestion.recipe.id}`}>Ver detalle</Link><Link className="button button-primary" to={`/recipes/${suggestion.recipe.id}/cook`}>Cocinar</Link></div></div><Artwork recipe={suggestion.recipe} /></article>)}</div>}
    </section>

    <section aria-labelledby="recent-title" className="dashboard-panel-section">
      <div className="section-header"><div><p className="dashboard-recommendation-kicker"><History aria-hidden="true" size={17} /> Historial local</p><h2 id="recent-title">Cocinaste hace poco</h2></div></div>
      {recent.length === 0 ? <div className="recipe-rail-empty"><History aria-hidden="true" size={20} /><span>Todavía no completaste ninguna receta.</span></div> : <div className="dashboard-recent-list">{recent.map((event) => { const recipe = getRecipeById(event.recipeId, true); if (!recipe) return null; const active = recipes.some((item) => item.id === recipe.id); return <article className="history-row" key={event.id}><Artwork compact recipe={recipe} /><div className="history-copy"><h3>{recipe.name}</h3><p>{new Date(event.cookedAt).toLocaleString('es-AR', { dateStyle: 'medium', timeStyle: 'short' })} · {event.portions} {event.portions === 1 ? 'porción' : 'porciones'}</p></div><div className="history-actions"><Link className="button button-quiet" to={`/recipes/${recipe.id}`}>Ver detalle</Link>{active && <Link className="button button-primary" to={`/recipes/${recipe.id}/cook`}>Volver a cocinar</Link>}</div></article> })}</div>}
    </section>

    <section aria-labelledby="time-title" className="dashboard-panel-section">
      <div className="section-header"><div><p className="dashboard-recommendation-kicker"><SunMedium aria-hidden="true" size={17} /> {timeSuggestion.meal} detectado</p><h2 id="time-title">Recomendación según la hora</h2></div></div>
      {timeSuggestion.recipe ? <article className="dashboard-recommendation dashboard-recommendation-featured"><div className="dashboard-recommendation-copy"><h3>{timeSuggestion.recipe.name}</h3><p>{timeSuggestion.reason}</p><div className="dashboard-recommendation-meta"><span><Clock3 aria-hidden="true" size={15} /> {timeSuggestion.recipe.minutes} min</span><span>{timeSuggestion.recipe.difficulty}</span></div><Link className="button button-dark" to={`/recipes/${timeSuggestion.recipe.id}`}>Ver receta</Link></div><Artwork recipe={timeSuggestion.recipe} /></article> : <div className="recipe-rail-empty"><span>No hay recetas activas para recomendar.</span></div>}
    </section>
  </div>
}
