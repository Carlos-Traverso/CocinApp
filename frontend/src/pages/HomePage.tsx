import { useEffect, useState } from 'react'
import { Clock3, History, PackageCheck, SunMedium } from 'lucide-react'
import { Link } from 'react-router-dom'
import { mockDashboardRepository, type DashboardHomeData } from '../features/dashboard/data/DashboardRepository'
import { buildCookingSuggestions, recentPreparations, recommendRecipeForTime } from '../features/dashboard/domain/dashboard'
import type { Recipe } from '../features/recipes/domain/Recipe'
import { RecipeImage } from '../features/recipes/ui/RecipeImage'
import { buildRecipeRecommendations } from '../features/recipes/domain/recipeRecommendations'
import { RecipeRecommendationsView } from '../features/recipes/ui/RecipeRecommendations'
import { getPlannedMealsForDate } from '../features/planner/domain/planner'
import { TodayPlanSection } from '../features/dashboard/ui/TodayPlanSection'
import { matchesDietaryPreferences } from '../features/recipes/domain/recipeRules'
import { useNotifications } from '../shared/notifications/NotificationProvider'
import '../features/dashboard/ui/DashboardLayout.css'

function Artwork({ recipe, compact = false }: { recipe: Recipe; compact?: boolean }) {
  return <RecipeImage className={`dashboard-suggestion-art${compact ? ' compact' : ''}`} recipe={recipe} />
}

function DietaryTags({ recipe }: { recipe: Recipe }) {
  return <p className="recipe-dietary-tags">{recipe.dietaryTags?.length ? recipe.dietaryTags.join(' · ') : 'Sin etiquetas dietéticas declaradas'}</p>
}

function RecommendationIngredients({ recipe }: { recipe: Recipe }) {
  return <p className="dashboard-recommendation-ingredients"><strong>Ingredientes:</strong> {recipe.ingredients.map((ingredient) => ingredient.name).join(' · ')}</p>
}

export function HomePage() {
  const { notify } = useNotifications()
  const [data, setData] = useState<DashboardHomeData | null>(null)
  const [loadFailed, setLoadFailed] = useState(false)
  const [loadAttempt, setLoadAttempt] = useState(0)
  useEffect(() => { let current = true; void mockDashboardRepository.loadHome().then((loaded) => { if (current) setData(loaded) }).catch(() => { if (current) { setLoadFailed(true); void notify({ type: 'error', title: 'No se pudo cargar el panel', message: 'Probá de nuevo más tarde.' }) } }); return () => { current = false } }, [loadAttempt, notify])
  if (loadFailed) return <div className="page dashboard-page"><header className="dashboard-focus-heading"><div><p className="eyebrow">MI COCINA</p><h1>Panel</h1><p>No se pudo cargar tu cocina.</p><button className="button button-primary" onClick={() => { setLoadFailed(false); setLoadAttempt((attempt) => attempt + 1) }} type="button">Reintentar</button></div></header></div>
  if (!data) return <div className="page dashboard-page"><p role="status">Cargando tu cocina…</p></div>
  const preferences = data.profile.preferences ?? []
  const recipes = data.recipes.filter((recipe) => matchesDietaryPreferences(recipe, preferences))
  const history = data.history
  const now = new Date()
  const suggestions = buildCookingSuggestions(recipes, data.pantry, now, 4, data.units)
  const timeSuggestion = recommendRecipeForTime(recipes, now.getHours(), { pantry: data.pantry, favoriteIds: data.favoriteIds, history, today: now, units: data.units })
  const recent = recentPreparations(history, recipes.map((recipe) => recipe.id))
  const recommendations = buildRecipeRecommendations(data.recipes, data.knownRecipes, data.pantry, data.favoriteIds, history, now, preferences, data.units)
  const plannedMeals = getPlannedMealsForDate(data.plannedMeals, now)

  return <div className="page dashboard-page dashboard-focus-page">
    <header className="dashboard-focus-heading"><div><p className="eyebrow">MI COCINA</p><h1>Panel</h1><p>Ideas basadas en tu despensa, tu horario y tus preparaciones.</p></div></header>

    {preferences.length > 0 && <p className="form-message" role="status">Sugerencias filtradas según tus {preferences.length} preferencias dietéticas activas. <Link to="/profile">Editar preferencias</Link></p>}
    <div className="dashboard-highlight-layout">
      <div className="dashboard-highlight-grid">
        <TodayPlanSection activeRecipeIds={new Set(data.recipes.map((recipe) => recipe.id))} knownRecipes={data.knownRecipes} plannedMeals={plannedMeals} />
        <section aria-labelledby="time-title" className="dashboard-panel-section dashboard-time-section">
          <div className="section-header"><div><p className="dashboard-recommendation-kicker"><SunMedium aria-hidden="true" size={17} /> {timeSuggestion.meal} detectado</p><h2 id="time-title">Recomendación según la hora</h2></div></div>
          {timeSuggestion.recipe ? <article className="dashboard-recommendation dashboard-recommendation-featured"><div className="dashboard-recommendation-copy"><h3>{timeSuggestion.recipe.name}</h3><DietaryTags recipe={timeSuggestion.recipe} /><RecommendationIngredients recipe={timeSuggestion.recipe} /><p>{timeSuggestion.reason}</p><div className="dashboard-recommendation-meta"><span><Clock3 aria-hidden="true" size={15} /> {timeSuggestion.recipe.minutes} min</span><span>{timeSuggestion.recipe.difficulty}</span></div><Link className="button button-dark" to={`/recipes/${timeSuggestion.recipe.id}`}>Ver receta</Link></div><Artwork recipe={timeSuggestion.recipe} /></article> : <div className="recipe-rail-empty"><span>No hay recetas activas para recomendar.</span></div>}
        </section>
      </div>
    </div>

    {preferences.length > 0 && recipes.length === 0
      ? <p className="recipe-rail-empty" role="status">Ninguna receta activa coincide con tus preferencias actuales. <Link to="/profile">Ajustar preferencias</Link></p>
      : <RecipeRecommendationsView pantry={data.pantry} recommendations={recommendations} today={now} units={data.units} />}

    <section aria-labelledby="cook-today-title" className="dashboard-panel-section">
      <div className="section-header"><div><p className="dashboard-recommendation-kicker"><PackageCheck aria-hidden="true" size={17} /> Según tu despensa</p><h2 id="cook-today-title">Qué podés cocinar hoy</h2></div></div>
      {suggestions.length === 0 ? <div className="recipe-rail-empty"><PackageCheck aria-hidden="true" size={20} /><span>No hay recetas completas o con hasta dos ingredientes faltantes.</span></div> : <div className="dashboard-suggestion-list">{suggestions.map((suggestion) => <article className="dashboard-recommendation" key={suggestion.recipe.id}><div className="dashboard-recommendation-copy"><h3>{suggestion.recipe.name}</h3><DietaryTags recipe={suggestion.recipe} /><RecommendationIngredients recipe={suggestion.recipe} /><p>{suggestion.reason}</p><div className="dashboard-recommendation-meta"><span>{suggestion.availableCount} disponibles</span><span>{suggestion.missingNames.length} faltantes</span><span><Clock3 aria-hidden="true" size={15} /> {suggestion.recipe.minutes} min</span></div><div className="dashboard-recommendation-actions"><Link className="button button-quiet" to={`/recipes/${suggestion.recipe.id}`}>Ver detalle</Link><Link className="button button-primary" to={`/recipes/${suggestion.recipe.id}/cook`}>Cocinar</Link></div></div><Artwork recipe={suggestion.recipe} /></article>)}</div>}
    </section>

    <section aria-labelledby="recent-title" className="dashboard-panel-section">
      <div className="section-header"><div><p className="dashboard-recommendation-kicker"><History aria-hidden="true" size={17} /> Historial local</p><h2 id="recent-title">Cocinaste hace poco</h2></div></div>
      {recent.length === 0 ? <div className="recipe-rail-empty"><History aria-hidden="true" size={20} /><span>Todavía no completaste ninguna receta.</span></div> : <div className="dashboard-recent-list">{recent.map((event) => { const recipe = data.knownRecipes.find((item) => item.id === event.recipeId); if (!recipe) return null; const active = recipes.some((item) => item.id === recipe.id); return <article className="history-row" key={event.id}><Artwork compact recipe={recipe} /><div className="history-copy"><h3>{recipe.name}</h3><DietaryTags recipe={recipe} /><p>{new Date(event.cookedAt).toLocaleString('es-AR', { dateStyle: 'medium', timeStyle: 'short' })} · {event.portions} {event.portions === 1 ? 'porción' : 'porciones'}</p></div><div className="history-actions"><Link className="button button-quiet" to={`/recipes/${recipe.id}`}>Ver detalle</Link>{active && <Link className="button button-primary" to={`/recipes/${recipe.id}/cook`}>Volver a cocinar</Link>}</div></article> })}</div>}
    </section>

  </div>
}
