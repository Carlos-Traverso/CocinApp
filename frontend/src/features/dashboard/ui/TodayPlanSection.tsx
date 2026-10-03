import { CalendarDays, Clock3 } from 'lucide-react'
import { Link } from 'react-router-dom'
import type { PlannedMeal } from '../../planner/domain/planner'
import { MealBadge } from '../../planner/ui/MealBadge'
import { getRecipeById } from '../../recipes/data/availableRecipes'
import { RecipeImage } from '../../recipes/ui/RecipeImage'

interface TodayPlanSectionProps {
  activeRecipeIds: Set<string>
  plannedMeals: PlannedMeal[]
}

export function TodayPlanSection({ activeRecipeIds, plannedMeals }: TodayPlanSectionProps) {
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
            const recipe = getRecipeById(entry.recipeId, true)
            if (!recipe) return null
            const isActive = activeRecipeIds.has(recipe.id)
            return <article className="dashboard-today-card" key={`${entry.date}:${entry.meal}`}>
              <RecipeImage className="dashboard-today-image" recipe={recipe} />
              <div className="dashboard-today-copy">
                <MealBadge meal={entry.meal} />
                <h3>{recipe.name}</h3>
                <p><Clock3 aria-hidden="true" size={15} /> {recipe.minutes} min · {recipe.difficulty}</p>
                {!isActive && <span className="dashboard-today-inactive">Receta inactiva</span>}
                <div className="dashboard-today-actions">
                  <Link className="button button-quiet" to={`/recipes/${recipe.id}`}>Ver detalle</Link>
                  {isActive && <Link className="button button-primary" to={`/recipes/${recipe.id}/cook`}>Cocinar</Link>}
                </div>
              </div>
            </article>
          })}
        </div>}
  </section>
}
