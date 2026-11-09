import type { Recipe } from '../../recipes/domain/Recipe'
import type { PantryItem } from '../../pantry/domain/pantry'
import type { PreparationEvent } from '../../cooking/domain/cooking'
import type { PlannedMeal } from '../../planner/domain/planner'
import type { ProfileDraft } from '../../profile/domain/profile'
import type { AdminUnit } from '../../admin/domain/adminModels'
import { mockRecipeRepository } from '../../recipes/data/MockRecipeRepository'
import { supabaseRecipeRepository, mapRecipe } from '../../recipes/data/SupabaseRecipeRepository'
import { getPantryItems } from '../../pantry/data/localPantryStore'
import { supabasePantryRepository } from '../../pantry/data/supabasePantryRepository'
import { mockCookingRepository } from '../../cooking/data/MockCookingRepository'
import { recipeFromSnapshot } from '../../cooking/data/supabaseCookingRepository'
import { getFavoriteIds } from '../../recipes/data/localFavoritesStore'
import { supabaseFavoriteRepository } from '../../recipes/data/supabaseFavoriteRepository'
import { mockPlannerRepository } from '../../planner/data/MockPlannerRepository'
import { getAdminData } from '../../admin/data/localAdminStore'
import { mapRowToDraft } from '../../profile/data/ProfileRepository'
import { assertPersonalDataOwner, assertPersonalDataSessionCurrent, capturePersonalDataSession } from '../../../shared/data/personalDataSession'
import { isRelationalDashboardEnabled, supabase } from '../../../shared/data/supabaseClient'

export interface DashboardSummary {
  asOf: string
  pantry: { total: number; low: number; empty: number; soon: number; expired: number }
  favorites: { total: number; available: number }
  shopping: { pending: number; checked: number; transferred: number }
  todayPlanCount: number
}

export interface DashboardHomeData {
  recipes: Recipe[]
  knownRecipes: Recipe[]
  pantry: PantryItem[]
  history: PreparationEvent[]
  favoriteIds: string[]
  plannedMeals: PlannedMeal[]
  profile: ProfileDraft
  units: AdminUnit[]
  summary?: DashboardSummary
}

export interface DashboardRepository { loadHome(): Promise<DashboardHomeData> }

export const mockDashboardRepository: DashboardRepository = {
  async loadHome() {
    const [recipes, knownRecipes, pantry, history, favoriteIds, plannedMeals, profile] = await Promise.all([
      mockRecipeRepository.list(), mockRecipeRepository.listKnown(), getPantryItems(), mockCookingRepository.getHistory(), getFavoriteIds(), mockPlannerRepository.list(), mockRecipeRepository.getProfile(),
    ])
    return { recipes, knownRecipes, pantry, history, favoriteIds, plannedMeals, profile, units: getAdminData().units }
  },
}

type Json = Record<string, unknown>
type RelationalSummary = {
  as_of: string; profile: { profile: Json | null; preference_keys: string[] }
  pantry: DashboardSummary['pantry']; favorites: DashboardSummary['favorites']
  shopping: { pending_items: number; checked_items: number; transferred_items: number }
  today_plan: { plan: unknown; slots: Array<Json> }; recent_preparations: Array<Json>
}
function record(value: unknown): value is Json { return !!value && typeof value === 'object' && !Array.isArray(value) }
function count(value: unknown): number { const n = typeof value === 'number' || typeof value === 'string' && value.trim() !== '' ? Number(value) : NaN; if (!Number.isSafeInteger(n) || n < 0) throw new Error('El resumen del panel contiene un conteo inválido.'); return n }
function validateSummary(value: unknown): RelationalSummary {
  if (!record(value) || typeof value.as_of !== 'string' || !/^\d{4}-\d{2}-\d{2}$/.test(value.as_of)
    || !record(value.profile) || !Array.isArray(value.profile.preference_keys)
    || !record(value.pantry) || !record(value.favorites) || !record(value.shopping)
    || !record(value.today_plan) || !Array.isArray(value.today_plan.slots) || !Array.isArray(value.recent_preparations)) throw new Error('El servidor devolvió un resumen de panel inválido.')
  const profile = value.profile
  const plan = value.today_plan
  const slots = plan.slots as unknown[]
  const recent = value.recent_preparations as unknown[]
  if ((value.profile.preference_keys as unknown[]).some((key) => typeof key !== 'string')
    || slots.some((item) => !record(item)) || recent.some((item) => !record(item))) throw new Error('El resumen del panel contiene datos inválidos.')
  return {
    as_of: value.as_of,
    profile: { profile: profile.profile === null ? null : record(profile.profile) ? profile.profile : (() => { throw new Error('Perfil inválido en el resumen.') })(), preference_keys: profile.preference_keys as string[] },
    pantry: { total: count(value.pantry.total), low: count(value.pantry.low), empty: count(value.pantry.empty), soon: count(value.pantry.soon), expired: count(value.pantry.expired) },
    favorites: { total: count(value.favorites.total), available: count(value.favorites.available) },
    shopping: { pending_items: count(value.shopping.pending_items), checked_items: count(value.shopping.checked_items), transferred_items: count(value.shopping.transferred_items) },
    today_plan: { plan: plan.plan, slots: slots as Json[] }, recent_preparations: recent as Json[],
  }
}

export function createRelationalDashboardRepository(deps: {
  getClient: () => NonNullable<typeof supabase>
  captureSession: typeof capturePersonalDataSession
  assertSession: typeof assertPersonalDataSessionCurrent
  assertOwner: typeof assertPersonalDataOwner
  recipes: typeof supabaseRecipeRepository
  pantry: typeof supabasePantryRepository
  favorites: typeof supabaseFavoriteRepository
}) : DashboardRepository {
  let generation = 0
  return {
    async loadHome() {
      const session = deps.captureSession(), current = ++generation
      const check = () => { deps.assertSession(session); if (current !== generation) throw new Error('La carga del panel quedó desactualizada. Volvé a cargarlo.') }
      check()
      const auth = await deps.getClient().auth.getUser()
      if (auth.error) throw auth.error
      if (!auth.data.user) throw new Error('Iniciá sesión para consultar tu panel.')
      deps.assertOwner(session, auth.data.user.id)
      const day = new Date()
      const localDay = `${day.getFullYear()}-${String(day.getMonth() + 1).padStart(2, '0')}-${String(day.getDate()).padStart(2, '0')}`
      const response = await deps.getClient().rpc('get_my_dashboard_summary', { p_day: localDay, p_recent_limit: 4 })
      if (response.error) throw response.error
      check()
      deps.assertOwner(session, auth.data.user.id)
      const summary = validateSummary(response.data)
      if (summary.as_of !== localDay) throw new Error('El resumen del panel corresponde a otro día.')
      const [recipes, knownRecipes, pantry, catalog, favoriteIds] = await Promise.all([deps.recipes.list(), deps.recipes.listKnown(), deps.pantry.list(), deps.pantry.getCatalog(), deps.favorites.listIds()])
      check()
      deps.assertOwner(session, auth.data.user.id)
      const history = summary.recent_preparations.map((item): PreparationEvent => {
        if (typeof item.id !== 'string' || typeof item.recipe_id !== 'string' || typeof item.cooked_at !== 'string' || !Number.isInteger(Number(item.portions))) throw new Error('El historial del panel contiene una preparación inválida.')
        const currentRecipe = knownRecipes.find((recipe) => recipe.relationalId === item.recipe_id)
        const recipeId = currentRecipe?.id ?? item.recipe_id
        return { id: item.id, recipeId, cookedAt: item.cooked_at, portions: Number(item.portions), ...(record(item.recipe_snapshot) ? { recipeSnapshot: recipeFromSnapshot(item.recipe_snapshot, recipeId) } : {}) }
      })
      const planRecipes: Recipe[] = []
      const plan = summary.today_plan.slots.map((item): PlannedMeal => {
        if (typeof item.meal_date !== 'string' || item.meal_date !== summary.as_of || typeof item.meal_shift !== 'string' || typeof item.recipe_id !== 'string' || !Number.isInteger(Number(item.portions)) || typeof item.available !== 'boolean') throw new Error('El plan diario contiene una entrada inválida.')
        const shifts: Record<string, PlannedMeal['meal']> = { breakfast: 'Desayuno', lunch: 'Almuerzo', snack: 'Merienda', dinner: 'Cena' }
        if (!shifts[item.meal_shift]) throw new Error('El plan diario contiene una comida inválida.')
        const embedded = record(item.recipe) ? mapRecipe(item.recipe) : undefined
        if (embedded && !knownRecipes.some((recipe) => recipe.id === embedded.id)) planRecipes.push(embedded)
        return { date: item.meal_date, meal: shifts[item.meal_shift], recipeId: embedded?.id ?? knownRecipes.find((recipe) => recipe.relationalId === item.recipe_id)?.id ?? item.recipe_id, relationalId: item.recipe_id, portions: Number(item.portions), available: item.available, position: count(item.position ?? 1) }
      })
      const profile = summary.profile.profile
      const draft = mapRowToDraft(profile, summary.profile.preference_keys)
      const dashboardSummary: DashboardSummary = {
        asOf: summary.as_of, pantry: summary.pantry, favorites: summary.favorites,
        shopping: { pending: summary.shopping.pending_items, checked: summary.shopping.checked_items, transferred: summary.shopping.transferred_items }, todayPlanCount: plan.length,
      }
      const snapshots = history.flatMap((event) => event.recipeSnapshot ? [event.recipeSnapshot] : [])
      const combinedKnown = [...knownRecipes, ...planRecipes, ...snapshots.filter((recipe) => !knownRecipes.some((known) => known.id === recipe.id))]
      return { recipes, knownRecipes: combinedKnown, pantry, history, favoriteIds, plannedMeals: plan, profile: draft, units: catalog.units, summary: dashboardSummary }
    },
  }
}

function getClient() { if (!supabase) throw new Error('Falta configurar la conexión con Supabase.'); return supabase }
const relationalDashboardRepository = createRelationalDashboardRepository({ getClient, captureSession: capturePersonalDataSession, assertSession: assertPersonalDataSessionCurrent, assertOwner: assertPersonalDataOwner, recipes: supabaseRecipeRepository, pantry: supabasePantryRepository, favorites: supabaseFavoriteRepository })
export const dashboardRepository = isRelationalDashboardEnabled ? relationalDashboardRepository : mockDashboardRepository
