import { useEffect, useRef, useState } from 'react'
import { ChevronLeft, ChevronRight } from 'lucide-react'
import { Link, useNavigate } from 'react-router-dom'
import { mockPlannerRepository } from '../features/planner/data/MockPlannerRepository'
import { localDateKey, meals, weekDates, type Meal, type PlannedMeal } from '../features/planner/domain/planner'
import type { Recipe } from '../features/recipes/domain/Recipe'
import { RecipePicker } from '../features/planner/ui/RecipePicker'
import { MealBadge } from '../features/planner/ui/MealBadge'
import { plannerSlotPresentation } from '../features/planner/ui/plannerPresentation'
import { RecipeImage } from '../features/recipes/ui/RecipeImage'
import { useNotifications } from '../shared/notifications/NotificationProvider'

const dayFormatter = new Intl.DateTimeFormat('es-AR', { weekday: 'long', day: 'numeric', month: 'short' })

export function PlannerPage() {
  const navigate = useNavigate()
  const { notify } = useNotifications()
  const [weekOffset, setWeekOffset] = useState(0)
  const [plan, setPlan] = useState<PlannedMeal[]>([])
  const [loading, setLoading] = useState(true)
  const [saving, setSaving] = useState(false)
  const [knownRecipes, setKnownRecipes] = useState<Recipe[]>([])
  const [availableRecipes, setAvailableRecipes] = useState<Recipe[]>([])
  const savingRef = useRef(false)
  const [picker, setPicker] = useState<{ date: string; meal: Meal; label: string } | null>(null)
  const target = new Date()
  target.setDate(target.getDate() + weekOffset * 7)
  const dates = weekDates(target)
  const recipesById = new Map(knownRecipes.map((recipe) => [recipe.id, recipe]))

  useEffect(() => { let active = true; Promise.all([mockPlannerRepository.list(), mockPlannerRepository.loadRecipes()]).then(([value, recipes]) => { if (active) { setPlan(value); setKnownRecipes(recipes.known); setAvailableRecipes(recipes.available) } }).catch(() => { if (active) void notify({ type: 'error', title: 'No se pudo cargar el plan', message: 'No se pudo cargar el plan semanal y las recetas.' }) }).finally(() => { if (active) setLoading(false) }); return () => { active = false } }, [notify])

  async function assign(date: string, meal: Meal, recipeId: string, portions?: number): Promise<boolean> {
    if (savingRef.current) return false
    if (recipeId && !availableRecipes.some((recipe) => recipe.id === recipeId)) {
      void notify({ type: 'warning', title: 'Receta no disponible', message: 'Esa receta ya no está disponible para nuevas asignaciones.' })
      return false
    }
    savingRef.current = true
    setSaving(true)
    try {
      const next = await mockPlannerRepository.assign(date, meal, recipeId, portions ?? (availableRecipes.find((recipe) => recipe.id === recipeId)?.portions ?? 2))
      setPlan(next)
      const recipeName = recipeId ? recipesById.get(recipeId)?.name : undefined
      void notify({ type: 'success', title: 'Plan actualizado', message: recipeName ? `${meal}: ${recipeName} quedó planificada.` : `${meal}: se quitó la receta planificada.` })
      return true
    }
    catch { void notify({ type: 'error', title: 'No se pudo guardar el plan', message: 'Intentá nuevamente.' }); return false }
    finally { savingRef.current = false; setSaving(false) }
  }

  async function sendWeekToShopping() {
    if (savingRef.current || loading) return
    savingRef.current = true; setSaving(true)
    try { await mockPlannerRepository.generateShopping(dates); void notify({ type: 'success', title: 'Compras generadas', message: 'La lista de compras se actualizó con las porciones del plan.' }); navigate('/shopping') }
    catch { void notify({ type: 'error', title: 'No se pudieron generar las compras', message: 'Intentá nuevamente.' }) }
    finally { savingRef.current = false; setSaving(false) }
  }

  return <div className="page planner-page">
    <header className="page-heading"><div><p className="eyebrow">ORGANIZÁ TUS COMIDAS</p><h1>Planificación semanal</h1><p className="page-lead">Asigná recetas de lunes a domingo para desayuno, almuerzo, merienda y cena. Cada semana se guarda por separado.</p></div><div className="planner-head-actions"><Link className="button button-quiet" to="/recipes">Explorar recetas</Link><button className="button button-primary" disabled={loading || saving} onClick={sendWeekToShopping} type="button">Generar compras de esta semana</button></div></header>
    <div className="planner-toolbar"><h2>Semana del {new Date(`${dates[0]}T12:00:00`).toLocaleDateString('es-AR')} al {new Date(`${dates[6]}T12:00:00`).toLocaleDateString('es-AR')}</h2><div><button aria-label="Semana anterior" className="button button-quiet" onClick={() => setWeekOffset(weekOffset - 1)} type="button"><ChevronLeft size={18} /></button><button className="button button-quiet" onClick={() => setWeekOffset(0)} type="button">Esta semana</button><button aria-label="Semana siguiente" className="button button-quiet" onClick={() => setWeekOffset(weekOffset + 1)} type="button"><ChevronRight size={18} /></button></div></div>
    {loading && <p role="status">Cargando plan semanal…</p>}{saving && <p role="status">Guardando cambio…</p>}
    <section aria-label="Calendario de comidas de la semana" className="planner-grid">
      {dates.map((date) => {
        const dayLabel = dayFormatter.format(new Date(`${date}T12:00:00`))
        const isToday = date === localDateKey(new Date())
        const isSelected = picker?.date === date
        return <article aria-labelledby={`planner-day-${date}`} className={`planner-day${isToday ? ' is-today' : ''}${isSelected ? ' is-selected' : ''}`} key={date}>
          <h3 id={`planner-day-${date}`}><span>{dayLabel}</span>{isToday && <span className="planner-today">Hoy</span>}</h3>
          {meals.map((meal) => {
            const assignment = plan.find((item) => item.date === date && item.meal === meal)
            const recipeId = assignment?.recipeId ?? ''
            const recipe = recipeId ? recipesById.get(recipeId) : undefined
            const recipeIsActive = Boolean(recipe && availableRecipes.some((item) => item.id === recipe.id))
            const presentation = plannerSlotPresentation(Boolean(recipe))
            const isEditing = picker?.date === date && picker.meal === meal
            return <div aria-label={`${meal} del ${dayLabel}: ${recipe?.name ?? presentation.state}`} className={`planner-slot ${recipe ? 'has-recipe' : 'empty'}${isEditing ? ' is-editing' : ''}`} key={meal}>
              <div className="planner-slot-heading"><MealBadge meal={meal} /><span className="planner-slot-state">{isEditing ? 'Seleccionando receta' : presentation.state}</span></div>
              <button className="planner-pick-button" disabled={loading || saving} onClick={() => setPicker({ date, meal, label: dayLabel })} type="button">{presentation.primaryAction}</button>
              {recipe && <><RecipeImage className="planner-assignment-image" recipe={recipe} /><p className={`planner-assignment${recipeIsActive ? '' : ' inactive'}`}>{recipe.name}{recipeIsActive ? '' : ' (inactiva)'}</p><p className="planner-recipe-meta">{recipe.minutes} min · {recipe.difficulty}</p><div className="planner-slot-links"><Link className="text-link" to={`/recipes/${recipe.id}?portions=${assignment?.portions ?? recipe.portions}`}>Ver receta</Link>{recipeIsActive && <Link className="text-link" to={`/recipes/${recipe.id}/cook?portions=${assignment?.portions ?? recipe.portions}`}>Cocinar receta</Link>}<button aria-label={`Quitar ${meal} del ${dayLabel}`} className="text-link planner-remove" disabled={saving} onClick={() => assign(date, meal, '')} type="button">Quitar receta</button></div></>}
            </div>
          })}
        </article>
      })}
    </section>
    {picker && <RecipePicker meal={picker.meal} onClose={() => setPicker(null)} onSelect={(id, portions) => assign(picker.date, picker.meal, id, portions)} recipes={availableRecipes} selectedId={plan.find((item) => item.date === picker.date && item.meal === picker.meal)?.recipeId} selectedPortions={plan.find((item) => item.date === picker.date && item.meal === picker.meal)?.portions} title={`${picker.meal} del ${picker.label}`} />}
  </div>
}
