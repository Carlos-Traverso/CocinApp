import { isRelationalPlanningEnabled, supabase } from '../../../shared/data/supabaseClient'
import { assertPersonalDataOwner, assertPersonalDataSessionCurrent, capturePersonalDataSession, type PersonalDataSession } from '../../../shared/data/personalDataSession'
import { supabaseRecipeRepository } from '../../recipes/data/SupabaseRecipeRepository'
import type { Recipe } from '../../recipes/domain/Recipe'
import { setPlannedMeal, weekDates, type Meal, type PlannedMeal } from '../domain/planner'
import type { PlannerRepository } from './PlannerRepository'
import { supabaseShoppingRepository } from '../../shopping/data/supabaseShoppingRepository'

type Json = Record<string, unknown>
interface PlanRow { id: string; week_start: string; version: number | string }
interface SlotRow { id: string; meal_date: string; meal_shift: string; recipe_id: string; portions: number | string; position: number | string; available: boolean; recipe: Json | null }
interface Envelope { plan: PlanRow | null; slots: SlotRow[] }
interface Dependencies {
  getClient(): NonNullable<typeof supabase>
  capture(): PersonalDataSession
  assertCurrent(session: PersonalDataSession): void
  assertOwner(session: PersonalDataSession, userId: string): void
  knownRecipes(): Promise<Recipe[]>
  suggestions(dates: string[]): Promise<unknown[]>
  appendSuggestions(suggestions: unknown[]): Promise<unknown[]>
}

const shiftForMeal: Record<Meal, string> = { Desayuno: 'breakfast', Almuerzo: 'lunch', Merienda: 'snack', Cena: 'dinner' }
const mealForShift: Record<string, Meal> = { breakfast: 'Desayuno', lunch: 'Almuerzo', snack: 'Merienda', dinner: 'Cena' }
const weekStart = (date: string) => weekDates(new Date(`${date}T12:00:00`))[0]

function client() { if (!supabase) throw new Error('Falta configurar la conexión con Supabase.'); return supabase }

export function createSupabasePlannerRepository(deps: Dependencies): PlannerRepository {
  let version = 0
  let loadedWeek: string | null = null
  let loadedSession: PersonalDataSession | null = null
  let loadedSlots: PlannedMeal[] = []
  let generation = 0
  const key = (session: PersonalDataSession) => `${session.token}:${session.localRevision}:${session.supabaseRevision}`

  async function owner(session: PersonalDataSession) {
    deps.assertCurrent(session)
    const { data: { user }, error } = await deps.getClient().auth.getUser()
    if (error) throw error
    if (!user) throw new Error('Iniciá sesión para guardar tu planificación.')
    deps.assertOwner(session, user.id)
    return user.id
  }

  function assertLoaded(session: PersonalDataSession, week: string) {
    deps.assertCurrent(session)
    if (!loadedSession || loadedWeek !== week || key(loadedSession) !== key(session)) throw new Error('La planificación cambió o no está cargada para esta semana. Recargala antes de guardar.')
  }

  async function read(week: string, session: PersonalDataSession, operation: number): Promise<PlannedMeal[]> {
    const userId = await owner(session)
    const { data, error } = await deps.getClient().rpc('get_my_meal_plan', { p_week_start: week })
    if (error) throw error
    deps.assertOwner(session, userId)
    if (operation !== generation) throw new Error('La planificación cambió mientras se cargaba. Volvé a cargarla.')
    const result = data as Envelope
    if (!result || (result.plan !== null && (result.plan.week_start !== week || !Number.isSafeInteger(Number(result.plan.version)) || Number(result.plan.version) < 1)) || !Array.isArray(result.slots)) throw new Error('El servidor devolvió una planificación inválida.')
    const recipes = await deps.knownRecipes()
    deps.assertOwner(session, userId)
    if (operation !== generation) throw new Error('La planificación cambió mientras se cargaba. Volvé a cargarla.')
    const byRelationalId = new Map(recipes.flatMap((recipe) => recipe.relationalId ? [[recipe.relationalId, recipe] as const] : []))
    const slots = result.slots.map((slot): PlannedMeal & { relationalId?: string; available?: boolean; position?: number } => {
      if (!slot || typeof slot.meal_date !== 'string' || weekStart(slot.meal_date) !== week || !mealForShift[slot.meal_shift] || typeof slot.recipe_id !== 'string' || !Number.isInteger(Number(slot.portions)) || !Number.isInteger(Number(slot.position)) || Number(slot.position) < 1 || Number(slot.position) > 100 || typeof slot.available !== 'boolean') throw new Error('El servidor devolvió una entrada de planificación inválida.')
      const recipe = byRelationalId.get(slot.recipe_id)
      return { date: slot.meal_date, meal: mealForShift[slot.meal_shift], recipeId: recipe?.id ?? slot.recipe_id, relationalId: slot.recipe_id, portions: Number(slot.portions), position: Number(slot.position), available: slot.available }
    })
    if (new Set(slots.map((slot) => `${slot.date}:${slot.meal}:${slot.position}`)).size !== slots.length) throw new Error('La planificación contiene posiciones repetidas.')
    loadedWeek = week
    version = Number(result.plan?.version ?? 0)
    loadedSession = session
    loadedSlots = slots.map((slot) => ({ ...slot }))
    return slots
  }

  async function write(plan: PlannedMeal[], week: string, session: PersonalDataSession) {
    assertLoaded(session, week)
    if (plan.some((slot) => weekStart(slot.date) !== week)) throw new Error('No se pueden guardar cambios de varias semanas en una sola operación.')
    const operation = generation, expectedVersion = version
    const recipes = await deps.knownRecipes()
    assertLoaded(session, week)
    if (operation !== generation || expectedVersion !== version) throw new Error('La semana cambió mientras se preparaba el guardado. Recargala y volvé a intentarlo.')
    const byId = new Map(recipes.map((recipe) => [recipe.id, recipe]))
    const slots = plan.map((item) => {
      const recipe = byId.get(item.recipeId)
      const recipeId = item.relationalId ?? recipe?.relationalId
      if (!recipeId) throw new Error(`No se pudo resolver la referencia relacional de «${recipe?.name ?? item.recipeId}».`)
      return { meal_date: item.date, meal_shift: shiftForMeal[item.meal], recipe_id: recipeId, portions: item.portions, position: item.position ?? 1 }
    })
    const userId = await owner(session)
    assertLoaded(session, week)
    if (operation !== generation || expectedVersion !== version) throw new Error('La semana cambió mientras se preparaba el guardado. Recargala y volvé a intentarlo.')
    let response
    try { response = await deps.getClient().rpc('save_my_meal_plan', { p_week_start: week, p_slots: slots, p_expected_version: expectedVersion }) }
    catch (error) { loadedSession = null; throw error }
    if (response.error) { loadedSession = null; throw response.error }
    deps.assertOwner(session, userId)
    if (operation !== generation) { loadedSession = null; throw new Error('La semana cambió mientras se guardaba. Recargala para verificar el resultado.') }
    const saved = response.data as PlanRow
    if (!saved || typeof saved.id !== 'string' || saved.week_start !== week || !Number.isSafeInteger(Number(saved.version)) || Number(saved.version) !== expectedVersion + 1) { loadedSession = null; throw new Error('No se pudo confirmar la versión guardada. Recargá la semana antes de continuar.') }
    version = Number(saved.version)
    // Reload the server snapshot so slot UUIDs, availability, and version are authoritative.
    const reloadOperation = ++generation
    return read(week, session, reloadOperation)
  }

  return {
    async list(requestedWeek) {
      const session = deps.capture(), operation = ++generation
      return read(requestedWeek ?? weekStart(weekDates()[0]), session, operation)
    },
    async loadRecipes() {
      const session = deps.capture()
      const [known, available] = await Promise.all([deps.knownRecipes(), supabaseRecipeRepository.list()])
      deps.assertCurrent(session)
      return { known, available }
    },
    async save(plan) {
      const session = deps.capture()
      if (!plan.length) {
        if (!loadedWeek) throw new Error('Cargá una semana antes de vaciar su planificación.')
        await write([], loadedWeek, session)
        return
      }
      const weeks = new Set(plan.map((slot) => weekStart(slot.date)))
      if (weeks.size !== 1) throw new Error('No se pueden guardar cambios de varias semanas en una sola operación.')
      await write(plan, [...weeks][0], session)
    },
    async assign(date, meal, recipeId, portions) {
      const session = deps.capture(), week = weekStart(date)
      assertLoaded(session, week)
      const current = loadedSlots
      if (current.filter((slot) => slot.date === date && slot.meal === meal).length > 1) throw new Error('Esta comida tiene varias posiciones. Conservamos todas las entradas; no se puede editar desde esta vista.')
      const target = current.find((slot) => slot.date === date && slot.meal === meal)
      if (current.some((slot) => slot.available === false && (slot.date !== date || slot.meal !== meal))) throw new Error('Esta semana conserva recetas inactivas. Preservamos esas entradas; reemplazalas primero antes de guardar otros cambios.')
      const next = setPlannedMeal(current, date, meal, recipeId, portions).map((slot) => slot.date === date && slot.meal === meal && recipeId
        ? { ...slot, relationalId: undefined, position: target?.position ?? 1, available: true }
        : slot)
      return write(next, week, session)
    },
    async generateShopping(dates) {
      const session = deps.capture()
      const suggestions = await deps.suggestions(dates)
      deps.assertCurrent(session)
      const result = await deps.appendSuggestions(suggestions)
      deps.assertCurrent(session)
      return result.length
    },
  }
}

export const supabasePlannerRepository = createSupabasePlannerRepository({
  getClient: client, capture: capturePersonalDataSession, assertCurrent: assertPersonalDataSessionCurrent, assertOwner: assertPersonalDataOwner,
  knownRecipes: () => supabaseRecipeRepository.listKnown(),
  async suggestions(dates) { return supabaseShoppingRepository.suggestionsFromWeek(dates) },
  async appendSuggestions(suggestions) { return supabaseShoppingRepository.append(suggestions as Awaited<ReturnType<typeof supabaseShoppingRepository.suggestionsFromWeek>>) },
})

export function isRelationalPlannerRepositoryEnabled() { return isRelationalPlanningEnabled && supabase !== null }
