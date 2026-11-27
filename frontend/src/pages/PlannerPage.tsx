import { LoadingScreen } from '../components/LoadingScreen'
import { scrollBehavior } from '../components/scrollToTop'
import { useEffect, useRef, useState } from 'react'
import { CalendarDays, ChevronLeft, ChevronRight } from 'lucide-react'
import { Link, useNavigate } from 'react-router-dom'
import { mockPlannerRepository } from '../features/planner/data/MockPlannerRepository'
import { localDateKey, meals, weekDates, type Meal, type PlannedMeal } from '../features/planner/domain/planner'
import type { Recipe } from '../features/recipes/domain/Recipe'
import { RecipePicker } from '../features/planner/ui/RecipePicker'
import { MealBadge } from '../features/planner/ui/MealBadge'
import { plannerSlotPresentation } from '../features/planner/ui/plannerPresentation'
import { RecipeImage } from '../features/recipes/ui/RecipeImage'
import { useNotifications } from '../shared/notifications/NotificationProvider'
import { writeFailureMessage } from '../shared/data/writeFailure'

const dayFormatter = new Intl.DateTimeFormat('es-AR', { weekday: 'long', day: 'numeric', month: 'short' })
const weekRangeFormatter = new Intl.DateTimeFormat('es-AR', { day: 'numeric', month: 'long' })
const weekRangeWithYearFormatter = new Intl.DateTimeFormat('es-AR', { day: 'numeric', month: 'long', year: 'numeric' })

type PlannerDay = { date: string; headingId: string; label: string }

function jumpToDay(headingId: string) {
  const heading = document.getElementById(headingId)
  if (!heading) return
  heading.focus({ preventScroll: true })
  heading.scrollIntoView({ behavior: scrollBehavior(window.matchMedia('(prefers-reduced-motion: reduce)').matches), block: 'start' })
}

function DayShortcuts({ days, disabled, replaced = false }: { days: PlannerDay[]; disabled: boolean; replaced?: boolean }) {
  return <nav aria-label="Ir a un día de la semana" className="planner-day-shortcuts" inert={replaced}>
    {days.map(({ date, headingId, label }) => <button aria-label={`Ir a ${label}`} disabled={disabled} key={date} onClick={() => jumpToDay(headingId)} type="button">
      <span>{label[0].toLocaleUpperCase('es-AR')}</span>
    </button>)}
  </nav>
}

export function PlannerPage() {
  const navigate = useNavigate()
  const { notify } = useNotifications()
  const [weekOffset, setWeekOffset] = useState(0)
  const [plan, setPlan] = useState<PlannedMeal[]>([])
  const [loading, setLoading] = useState(true)
  const [loadFailed, setLoadFailed] = useState(false)
  const [saving, setSaving] = useState(false)
  const [knownRecipes, setKnownRecipes] = useState<Recipe[]>([])
  const [availableRecipes, setAvailableRecipes] = useState<Recipe[]>([])
  const [shortcutsPinned, setShortcutsPinned] = useState(false)
  const weekActions = useRef<HTMLDivElement>(null)
  const savingRef = useRef(false)
  const [picker, setPicker] = useState<{ date: string; meal: Meal; label: string } | null>(null)
  const target = new Date()
  target.setDate(target.getDate() + weekOffset * 7)
  const [loadAttempt, setLoadAttempt] = useState(0)
  const dates = weekDates(target)
  const days = dates.map((date) => ({ date, headingId: `planner-day-${date}`, label: dayFormatter.format(new Date(`${date}T12:00:00`)) }))
  const weekStart = dates[0]
  const firstDay = new Date(`${weekStart}T12:00:00`)
  const lastDay = new Date(`${dates[6]}T12:00:00`)
  const weekYear = firstDay.getFullYear() === lastDay.getFullYear() ? firstDay.getFullYear() : null
  const weekRange = (weekYear === null ? weekRangeWithYearFormatter : weekRangeFormatter).formatRange(firstDay, lastDay)
  const recipesById = new Map(knownRecipes.map((recipe) => [recipe.id, recipe]))

  useEffect(() => {
    const actions = weekActions.current
    const header = actions?.closest('.main-content')?.querySelector('.mobile-brand')
    if (!actions || !header) return

    let positionObserver: IntersectionObserver | undefined
    const headerObserver = new ResizeObserver(() => {
      positionObserver?.disconnect()
      const headerHeight = header.getBoundingClientRect().height
      if (!headerHeight) {
        setShortcutsPinned(false)
        return
      }
      positionObserver = new IntersectionObserver(([entry]) => {
        setShortcutsPinned(entry.boundingClientRect.top < headerHeight)
      }, { rootMargin: `-${headerHeight}px 0px 0px`, threshold: [0, 1] })
      positionObserver.observe(actions)
    })
    headerObserver.observe(header)
    return () => { headerObserver.disconnect(); positionObserver?.disconnect() }
  }, [])

  useEffect(() => {
    let active = true
    setLoading(true)
    setLoadFailed(false)
    Promise.all([mockPlannerRepository.list(weekStart), mockPlannerRepository.loadRecipes()])
      .then(([value, recipes]) => {
        if (!active) return
        setPlan(value)
        setKnownRecipes(recipes.known)
        setAvailableRecipes(recipes.available)
      })
      .catch(() => { if (active) setLoadFailed(true) })
      .finally(() => { if (active) setLoading(false) })
    return () => { active = false }
  }, [weekStart, loadAttempt])

  function goToWeek(offset: number) {
    if (offset === weekOffset) return
    setPicker(null)
    setLoading(true)
    setWeekOffset(offset)
  }

  function reloadWeek() {
    setPicker(null)
    setLoading(true)
    setLoadAttempt((value) => value + 1)
  }

  async function assign(date: string, meal: Meal, recipeId: string, portions?: number): Promise<boolean> {
    if (savingRef.current || loading) return false
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
    catch (error) { void notify({ type: 'error', title: 'No se pudo guardar el plan', message: writeFailureMessage(error, 'Recargá la semana para revisar los datos actuales.') ?? (error instanceof Error ? error.message : 'No se confirmó el guardado. Recargá la semana para revisar los datos actuales.') }); return false }
    finally { savingRef.current = false; setSaving(false) }
  }

  async function sendWeekToShopping() {
    if (savingRef.current || loading) return
    savingRef.current = true; setSaving(true)
    try { await mockPlannerRepository.generateShopping(dates); void notify({ type: 'success', title: 'Compras generadas', message: 'La lista de compras se actualizó con las porciones del plan.' }); navigate('/shopping') }
    catch { void notify({ type: 'error', title: 'No se pudieron generar las compras', message: 'Intentá nuevamente.' }) }
    finally { savingRef.current = false; setSaving(false) }
  }

  async function removeUnavailable() {
    if (savingRef.current || loading) return
    const unavailable = plan.filter((item) => item.available === false)
    if (!unavailable.length) return
    if (!await notify({ type: 'warning', title: 'Quitar recetas no disponibles', message: `Se quitarán ${unavailable.length} entradas de esta semana.`, confirmLabel: 'Quitar', cancelLabel: 'Cancelar' })) return
    savingRef.current = true; setSaving(true)
    try { await mockPlannerRepository.save(plan.filter((item) => item.available !== false)); setPlan(await mockPlannerRepository.list(dates[0])); void notify({ type: 'success', title: 'Plan actualizado', message: 'Se quitaron las recetas no disponibles.' }) }
    catch (error) { void notify({ type: 'error', title: 'No se pudo actualizar el plan', message: writeFailureMessage(error, 'Recargá la semana e intentá nuevamente.') ?? (error instanceof Error ? error.message : 'Recargá la semana e intentá nuevamente.') }) }
    finally { savingRef.current = false; setSaving(false) }
  }

  return <div className="page planner-page">
    <header className="page-heading">
      <div>
        <p className="eyebrow">ORGANIZÁ TUS COMIDAS</p>
        <h1>Planificación semanal</h1>
        <p className="page-lead">Asigná recetas de lunes a domingo para desayuno, almuerzo, merienda y cena. Cada semana se guarda por separado.</p>
      </div>
      <div className="planner-head-actions">
        <button className="button button-primary" disabled={loading || loadFailed || saving} onClick={sendWeekToShopping} type="button">Generar compras de esta semana</button>
        <Link className="button button-quiet" to="/recipes">Explorar recetas</Link>
      </div>
    </header>
    <section aria-labelledby="planner-week-title" className="planner-calendar">
      <div className="planner-toolbar">
        <div className="planner-week-summary">
          <h2 id="planner-week-title">
            <span className="planner-week-title-desktop">Semana del {firstDay.toLocaleDateString('es-AR')} al {lastDay.toLocaleDateString('es-AR')}</span>
            <span className="planner-week-title-mobile">
              <span aria-hidden="true" className="planner-week-title-icon"><CalendarDays size={19} /></span>
              <span>
                <span className="planner-week-title-meta">{weekYear === null ? 'Semana' : `Semana · ${weekYear}`}</span>
                <span className="planner-week-title-range">{weekRange}</span>
              </span>
            </span>
          </h2>
          <div className="planner-week-actions" ref={weekActions}>
            <button className="button button-quiet" disabled={saving || loading} onClick={reloadWeek} type="button">Recargar semana</button>
            <DayShortcuts days={days} disabled={loading || loadFailed} replaced={shortcutsPinned} />
          </div>
        </div>
        <div className="planner-week-navigation">
          <button aria-label="Semana anterior" disabled={saving} className="button button-quiet" onClick={() => goToWeek(weekOffset - 1)} type="button"><ChevronLeft size={18} /></button>
          <button className="button button-quiet" disabled={saving} onClick={() => goToWeek(0)} type="button">Esta semana</button>
          <button aria-label="Semana siguiente" disabled={saving} className="button button-quiet" onClick={() => goToWeek(weekOffset + 1)} type="button"><ChevronRight size={18} /></button>
        </div>
      </div>
      {shortcutsPinned && <div className="planner-pinned-shortcuts"><DayShortcuts days={days} disabled={loading || loadFailed} /></div>}
      {loading ? <LoadingScreen message="Cargando plan semanal…" variant="section" /> : loadFailed ? (
        <p role="alert">No se pudo cargar el plan semanal. Usá «Recargar semana» para volver a intentarlo.</p>
      ) : <>
        {plan.some((item) => item.available === false) && <p role="status">Hay recetas que ya no están disponibles. Para editar la semana, quitá explícitamente esas entradas. <button className="text-link" disabled={saving} onClick={() => void removeUnavailable()} type="button">Quitar recetas no disponibles</button></p>}
        {saving && <p role="status">Guardando cambio…</p>}
        <div className="planner-grid">
          {days.map(({ date, headingId, label: dayLabel }) => {
            const isToday = date === localDateKey(new Date())
            const isSelected = picker?.date === date
            return <article aria-labelledby={headingId} className={`planner-day${isToday ? ' is-today' : ''}${isSelected ? ' is-selected' : ''}`} key={date}>
              <h3 id={headingId} tabIndex={-1}><span>{dayLabel}</span>{isToday && <span className="planner-today">Hoy</span>}</h3>
              {meals.map((meal) => {
                const assignment = plan.find((item) => item.date === date && item.meal === meal)
                const recipeId = assignment?.recipeId ?? ''
                const recipe = recipeId ? recipesById.get(recipeId) : undefined
                const recipeIsActive = Boolean(recipe && availableRecipes.some((item) => item.id === recipe.id))
                const presentation = plannerSlotPresentation(Boolean(recipe))
                const isEditing = picker?.date === date && picker.meal === meal
                return <div aria-label={`${meal} del ${dayLabel}: ${recipe?.name ?? presentation.state}`} className={`planner-slot ${recipe ? 'has-recipe' : 'empty'}${isEditing ? ' is-editing' : ''}`} key={meal}>
                  <div className="planner-slot-heading">
                    <MealBadge meal={meal} />
                    <button className="planner-pick-button" disabled={loading || saving} onClick={() => setPicker({ date, meal, label: dayLabel })} type="button">{presentation.primaryAction}</button>
                  </div>
                  {recipe ? <>
                    <div className="planner-recipe-summary">
                      <RecipeImage className="planner-assignment-image" recipe={recipe} />
                      <div className="planner-recipe-caption">
                        <p className={`planner-assignment${recipeIsActive ? '' : ' inactive'}`} title={recipe.name}>{recipe.name}{recipeIsActive ? '' : ' (inactiva)'}</p>
                        <p className="planner-recipe-meta">{recipe.minutes} min · {recipe.difficulty}</p>
                      </div>
                    </div>
                    <div className="planner-slot-links">
                      <Link className="text-link" to={`/recipes/${recipe.id}?portions=${assignment?.portions ?? recipe.portions}`}>Ver receta</Link>
                      {recipeIsActive && <Link className="text-link" to={`/recipes/${recipe.id}/cook?portions=${assignment?.portions ?? recipe.portions}`}>Cocinar receta</Link>}
                      <button aria-label={`Quitar ${meal} del ${dayLabel}`} className="text-link planner-remove" disabled={saving} onClick={() => assign(date, meal, '')} type="button">Quitar receta</button>
                    </div>
                  </> : <p className="planner-slot-state">{presentation.state}</p>}
                </div>
              })}
            </article>
          })}
        </div>
      </>}
    </section>
    {picker && <RecipePicker meal={picker.meal} onClose={() => setPicker(null)} onSelect={(id, portions) => assign(picker.date, picker.meal, id, portions)} recipes={availableRecipes} selectedId={plan.find((item) => item.date === picker.date && item.meal === picker.meal)?.recipeId} selectedPortions={plan.find((item) => item.date === picker.date && item.meal === picker.meal)?.portions} title={`${picker.meal} del ${picker.label}`} />}
  </div>
}
