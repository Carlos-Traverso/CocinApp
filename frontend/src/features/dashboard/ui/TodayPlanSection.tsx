import { CalendarDays, Clock3 } from 'lucide-react'
import { Link } from 'react-router-dom'
import type { PlannedMeal } from '../../planner/domain/planner'
import { MealBadge } from '../../planner/ui/MealBadge'
import { RecipeImage } from '../../recipes/ui/RecipeImage'
import type { Recipe } from '../../recipes/domain/Recipe'

interface TodayPlanSectionProps {
  activeRecipeIds: Set<string>
  knownRecipes: Recipe[]
  plannedMeals: PlannedMeal[]
}

export function TodayPlanSection({ activeRecipeIds, knownRecipes, plannedMeals }: TodayPlanSectionProps) {
  return <section aria-labelledby="today-plan-title" className="dashboard-panel-section dashboard-today-section">
    <div className="section-header">
      <div>
        <p className="dashboard-recommendation-kicker"><CalendarDays aria-hidden="true" size={17} /> Tu organización</p>
        <h2 id="today-plan-title">Planificado para hoy</h2>
      </div>
      <Link className="text-link" to="/planner">Ver planificación</Link>
    </div>

    {plannedMeals.length === 0
      ? <div className="dashboard-today-empty">
          <CalendarDays aria-hidden="true" size={24} />
          <div><h3>Todavía no planificaste comidas para hoy</h3><p>Organizá desayuno, almuerzo, merienda o cena desde tu planificación semanal.</p></div>
          <Link className="button button-primary" to="/planner">Planificar comidas</Link>
        </div>
      : <div className="dashboard-today-grid">
          {plannedMeals.map((entry) => {
            const recipe = knownRecipes.find((item) => item.id === entry.recipeId || item.relationalId === entry.relationalId)
            const isActive = !!recipe && activeRecipeIds.has(recipe.id)
            return <article className="dashboard-today-card" key={`${entry.date}:${entry.meal}:${entry.position ?? 1}`}>
              {recipe && <RecipeImage className="dashboard-today-image" recipe={recipe} />}
              <div className="dashboard-today-copy">
                <MealBadge meal={entry.meal} />
                <h3>{recipe?.name ?? 'Receta no disponible'}</h3>
                {recipe && <p><Clock3 aria-hidden="true" size={15} /> {recipe.minutes} min · {recipe.difficulty}</p>}
                {(!recipe || !isActive || entry.available === false) && <span className="dashboard-today-inactive">{recipe ? 'Receta inactiva' : 'Conservamos la referencia del plan'}</span>}
                <div className="dashboard-today-actions">
                  {recipe && <Link className="button button-quiet" to={`/recipes/${recipe.id}?portions=${entry.portions}`}>Ver detalle</Link>}
                  {recipe && isActive && entry.available !== false && <Link className="button button-primary" to={`/recipes/${recipe.id}/cook?portions=${entry.portions}`}>Cocinar</Link>}
                </div>
              </div>
            </article>
          })}
        </div>}
  </section>
}
