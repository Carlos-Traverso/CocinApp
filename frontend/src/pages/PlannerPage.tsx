import { useState } from 'react'
import { ChevronLeft, ChevronRight } from 'lucide-react'
import { Link, useNavigate } from 'react-router-dom'
import { readPantryItems } from '../features/pantry/data/localPantryStore'
import { readMealPlan, writeMealPlan } from '../features/planner/data/localMealPlanStore'
import { setPlannedMeal, weekDates, type Meal, type PlannedMeal } from '../features/planner/domain/planner'
import { getAvailableRecipes, getRecipeById } from '../features/recipes/data/availableRecipes'
import { appendShoppingSuggestions } from '../features/shopping/data/localShoppingStore'
import { suggestForRecipes } from '../features/shopping/domain/shopping'

const meals: Meal[] = ['Almuerzo', 'Cena']
const dayFormatter = new Intl.DateTimeFormat('es-AR', { weekday: 'long', day: 'numeric', month: 'short' })

export function PlannerPage() {
  const navigate = useNavigate()
  const [weekOffset, setWeekOffset] = useState(0)
  const [plan, setPlan] = useState<PlannedMeal[]>(readMealPlan)
  const [error, setError] = useState('')
  const target = new Date()
  target.setDate(target.getDate() + weekOffset * 7)
  const dates = weekDates(target)
  const availableRecipes = getAvailableRecipes()

  function assign(date: string, meal: Meal, recipeId: string) {
    const next = setPlannedMeal(plan, date, meal, recipeId)
    try { writeMealPlan(next); setPlan(next); setError('') }
    catch { setError('No se pudo guardar el plan en este navegador.') }
  }

  function sendWeekToShopping() {
    const week = new Set(dates)
    const selectedRecipes = plan.filter((entry) => week.has(entry.date))
      .map((entry) => getRecipeById(entry.recipeId))
      .filter((recipe): recipe is (typeof availableRecipes)[number] => Boolean(recipe))
    try { appendShoppingSuggestions(suggestForRecipes(selectedRecipes, readPantryItems(), 'plan')); navigate('/shopping') }
    catch { setError('No se pudo guardar la lista de compras en este navegador.') }
  }

  return <div className="page planner-page"><header className="page-heading"><div><p className="eyebrow">ORGANIZÁ TUS COMIDAS</p><h1>Planificación semanal</h1><p className="page-lead">Asigná una receta a cada almuerzo o cena. Tu plan se guarda en este navegador.</p></div><div className="planner-head-actions"><Link className="button button-quiet" to="/recipes">Explorar recetas</Link><button className="button button-primary" onClick={sendWeekToShopping} type="button">Generar compras de esta semana</button></div></header><div className="planner-toolbar"><h2>Semana del {new Date(`${dates[0]}T12:00:00`).toLocaleDateString('es-AR')} al {new Date(`${dates[6]}T12:00:00`).toLocaleDateString('es-AR')}</h2><div><button aria-label="Semana anterior" className="button button-quiet" onClick={() => setWeekOffset(weekOffset - 1)} type="button"><ChevronLeft size={18} /></button><button className="button button-quiet" onClick={() => setWeekOffset(0)} type="button">Esta semana</button><button aria-label="Semana siguiente" className="button button-quiet" onClick={() => setWeekOffset(weekOffset + 1)} type="button"><ChevronRight size={18} /></button></div></div>{error && <p className="form-message error" role="alert">{error}</p>}<section aria-label="Comidas de la semana" className="planner-grid">{dates.map((date) => <article className="planner-day" key={date}><h3>{dayFormatter.format(new Date(`${date}T12:00:00`))}</h3>{meals.map((meal) => { const recipeId = plan.find((item) => item.date === date && item.meal === meal)?.recipeId ?? ''; const recipe = recipeId ? getRecipeById(recipeId, true) : null; const recipeIsActive = Boolean(recipe && availableRecipes.some((item) => item.id === recipe.id)); return <div className="planner-slot" key={meal}><label className="field"><span>{meal}</span><select onChange={(event) => assign(date, meal, event.currentTarget.value)} value={recipeIsActive ? recipeId : ''}><option value="">{recipe && !recipeIsActive ? `${recipe.name} (inactiva)` : 'Sin receta'}</option>{availableRecipes.map((option) => <option key={option.id} value={option.id}>{option.name}</option>)}</select></label>{recipe && <div className="planner-slot-links"><Link className="text-link" to={`/recipes/${recipe.id}`}>Ver receta →</Link>{recipeIsActive && <Link className="text-link" to={`/recipes/${recipe.id}/cook`}>Cocinar ahora →</Link>}</div>}</div> })}</article>)}</section></div>
}
