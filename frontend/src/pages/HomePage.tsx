import { ArrowRight, Clock3, History, PackageCheck, Sparkles, SunMedium } from 'lucide-react'
import { Link } from 'react-router-dom'
import { useAuth } from '../features/auth/data/localAuthStore'
import { readHistory } from '../features/cooking/data/localCookingStore'
import { buildDashboardSummary, recommendRecipeForTime } from '../features/dashboard/domain/dashboard'
import { readPantryItems } from '../features/pantry/data/localPantryStore'
import { readMealPlan } from '../features/planner/data/localMealPlanStore'
import { readFavoriteIds } from '../features/recipes/data/localFavoritesStore'
import { getAvailableRecipes, getKnownRecipes } from '../features/recipes/data/availableRecipes'
import { readShoppingItems } from '../features/shopping/data/localShoppingStore'
import type { Recipe } from '../features/recipes/domain/Recipe'

function SuggestionArtwork({ recipe }: { recipe: Recipe }) {
  return <div aria-hidden="true" className={`dashboard-suggestion-art ${recipe.color}`}><span>{recipe.symbol}</span></div>
}

export function HomePage() {
  const session = useAuth()
  const availableRecipes = getAvailableRecipes()
  const summary = buildDashboardSummary({
    pantry: readPantryItems(),
    recipes: availableRecipes,
    knownRecipes: getKnownRecipes(),
    favoriteIds: readFavoriteIds(),
    plan: readMealPlan(),
    shopping: readShoppingItems(),
    history: readHistory(),
  })
  const pantrySuggestion = summary.suggestedRecipes[0]
  const historySuggestion = summary.discovery.basedOnHistory[0] ?? summary.discovery.recook[0]
  const historyIsNew = summary.discovery.basedOnHistory.some((recipe) => recipe.id === historySuggestion?.id)
  const timeSuggestion = recommendRecipeForTime(availableRecipes, new Date().getHours())
  const firstName = session?.name.trim().split(/\s+/)[0]

  return <div className="page dashboard-page dashboard-focus-page">
    <header className="dashboard-focus-heading"><div><p className="eyebrow">MI COCINA</p><h1>{firstName ? `Hola, ${firstName}.` : 'Tu cocina, en orden.'}</h1><p>Elegimos tres ideas concretas para ayudarte a decidir qué cocinar hoy.</p></div><Link className="button button-primary" to="/recipes">Explorar todas las recetas <ArrowRight aria-hidden="true" size={17} /></Link></header>

    <div className="dashboard-focus-grid">
      <section aria-labelledby="dashboard-pantry-suggestion" className="dashboard-recommendation dashboard-recommendation-featured">
        <div className="dashboard-recommendation-copy"><p className="dashboard-recommendation-kicker"><PackageCheck aria-hidden="true" size={17} /> Según tu despensa</p>
          {pantrySuggestion ? <><h2 id="dashboard-pantry-suggestion">{pantrySuggestion.recipe.name}</h2><p>{pantrySuggestion.canCook ? 'Tenés todos los ingredientes disponibles para empezar ahora.' : `Es la opción que mejor aprovecha tu stock. Te ${pantrySuggestion.missingNames.length === 1 ? 'falta' : 'faltan'} ${pantrySuggestion.missingNames.slice(0, 2).join(' y ')}${pantrySuggestion.missingNames.length > 2 ? ' y algunos ingredientes más' : ''}.`}</p><div className="dashboard-recommendation-meta"><span><Clock3 aria-hidden="true" size={15} /> {pantrySuggestion.recipe.minutes} min</span><span>{pantrySuggestion.availableCount} de {pantrySuggestion.recipe.ingredients.length} ingredientes</span></div><div className="dashboard-recommendation-actions"><Link className="button button-dark" to={`/recipes/${pantrySuggestion.recipe.id}`}>Ver receta <ArrowRight aria-hidden="true" size={16} /></Link>{!pantrySuggestion.canCook && <Link className="text-link" to="/pantry">Revisar despensa</Link>}</div></> : <><h2 id="dashboard-pantry-suggestion">Tu despensa está esperando</h2><p>Agregá lo que tenés en casa y te mostraremos qué recetas aprovechan mejor esos ingredientes.</p><Link className="button button-dark" to="/pantry">Cargar ingredientes <ArrowRight aria-hidden="true" size={16} /></Link></>}
        </div>{pantrySuggestion && <SuggestionArtwork recipe={pantrySuggestion.recipe} />}
      </section>

      <section aria-labelledby="dashboard-history-suggestion" className="dashboard-recommendation">
        <div className="dashboard-recommendation-copy"><p className="dashboard-recommendation-kicker"><History aria-hidden="true" size={17} /> Basado en tu historial</p>
          {historySuggestion ? <><h2 id="dashboard-history-suggestion">{historySuggestion.name}</h2><p>{historyIsNew ? 'Una idea nueva relacionada con las recetas que cocinaste últimamente.' : 'Una preparación reciente que podés volver a disfrutar.'}</p><div className="dashboard-recommendation-meta"><span><Clock3 aria-hidden="true" size={15} /> {historySuggestion.minutes} min</span><span>{historySuggestion.difficulty}</span></div><Link className="dashboard-recommendation-link" to={`/recipes/${historySuggestion.id}`}>{historyIsNew ? 'Descubrir receta' : 'Volver a cocinar'} <ArrowRight aria-hidden="true" size={16} /></Link></> : <><h2 id="dashboard-history-suggestion">Empezá tu historial</h2><p>Cuando completes una receta, vas a recibir nuevas ideas relacionadas y accesos para repetir tus favoritas.</p><Link className="dashboard-recommendation-link" to="/recipes">Elegir una receta <ArrowRight aria-hidden="true" size={16} /></Link></>}
        </div>{historySuggestion ? <SuggestionArtwork recipe={historySuggestion} /> : <div aria-hidden="true" className="dashboard-empty-art"><History size={42} /></div>}
      </section>

      <section aria-labelledby="dashboard-time-suggestion" className="dashboard-recommendation">
        <div className="dashboard-recommendation-copy"><p className="dashboard-recommendation-kicker"><SunMedium aria-hidden="true" size={17} /> Para este momento</p>
          {timeSuggestion.recipe ? <><h2 id="dashboard-time-suggestion">{timeSuggestion.recipe.name}</h2><p>Una opción de {timeSuggestion.meal.toLocaleLowerCase('es')} elegida por su popularidad y tiempo de preparación.</p><div className="dashboard-recommendation-meta"><span><Clock3 aria-hidden="true" size={15} /> {timeSuggestion.recipe.minutes} min</span><span>{timeSuggestion.recipe.portions} {timeSuggestion.recipe.portions === 1 ? 'porción' : 'porciones'}</span></div><Link className="dashboard-recommendation-link" to={`/recipes/${timeSuggestion.recipe.id}`}>Ver sugerencia <ArrowRight aria-hidden="true" size={16} /></Link></> : <><h2 id="dashboard-time-suggestion">Próximamente habrá una sugerencia</h2><p>Publicá recetas desde Administración para activar recomendaciones según el momento del día.</p></>}
        </div>{timeSuggestion.recipe ? <SuggestionArtwork recipe={timeSuggestion.recipe} /> : <div aria-hidden="true" className="dashboard-empty-art"><Sparkles size={42} /></div>}
      </section>
    </div>
  </div>
}
