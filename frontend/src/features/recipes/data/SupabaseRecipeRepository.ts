import type { Recipe } from '../domain/Recipe'
import type { RecipeRepository } from './RecipeRepository'
import type { RecipeFilters, IngredientDeficit } from '../domain/recipeRules'
import type { DietaryPreference } from '../../profile/domain/profile'
import type { ProfileDraft } from '../../profile/domain/profile'
import { profileRepository } from '../../profile/data/ProfileRepository'
import { assertPersonalDataOwner, assertPersonalDataSessionCurrent, capturePersonalDataSession, type PersonalDataSession } from '../../../shared/data/personalDataSession'
import { isRelationalRecipesEnabled, supabase } from '../../../shared/data/supabaseClient'

type JsonRow = Record<string, unknown>
interface RecipeReadEnvelope { recipe?: JsonRow | null; stock?: JsonRow | null; percentage?: number | null; label?: string }
interface RecipeRepositoryDependencies {
  captureSession(): PersonalDataSession
  assertCurrent(session: PersonalDataSession): void
  assertOwner(session: PersonalDataSession, userId: string): void
  getUser(session: PersonalDataSession): Promise<string>
  rpc(name: string, args: Record<string, unknown>, session: PersonalDataSession): Promise<unknown>
  getProfile(): Promise<ProfileDraft>
}

const preferenceKeys: Record<DietaryPreference, string> = {
  'gluten-free': 'gluten-free', vegetarian: 'vegetarian', vegan: 'vegan',
  'lactose-free': 'lactose-free', 'nut-free': 'nut-free',
}
const shifts: Record<string, string> = { breakfast: 'Desayuno', lunch: 'Almuerzo', snack: 'Merienda', dinner: 'Cena' }
const difficulties: Record<string, Recipe['difficulty']> = { easy: 'Fácil', intermediate: 'Intermedia', advanced: 'Avanzada' }

function strings(value: unknown): string[] { return Array.isArray(value) ? value.filter((item): item is string => typeof item === 'string') : [] }

export function mapRecipe(raw: unknown): Recipe {
  if (!raw || typeof raw !== 'object' || Array.isArray(raw)) throw new Error('El servidor devolvió una receta inválida.')
  const row = raw as JsonRow
  const relationalId = typeof row.id === 'string' ? row.id : ''
  if (!relationalId || typeof row.title !== 'string') throw new Error('El servidor devolvió una receta incompleta.')
  const legacyId = typeof row.legacy_id === 'string' && row.legacy_id ? row.legacy_id : undefined
  const ingredientRows = Array.isArray(row.ingredients) ? row.ingredients : []
  const stepRows = Array.isArray(row.steps) ? row.steps : []
  const steps = stepRows.flatMap((value) => value && typeof value === 'object' && typeof (value as JsonRow).instruction === 'string' ? [(value as JsonRow).instruction as string] : [])
  const stepMeta = stepRows.flatMap((value) => {
    if (!value || typeof value !== 'object') return []
    const item = value as JsonRow
    const linked = Array.isArray(item.ingredients) ? item.ingredients.flatMap((association) => {
      if (!association || typeof association !== 'object') return []
      const relation = association as JsonRow
      const ingredient = ingredientRows.find((candidate) => candidate && typeof candidate === 'object' && (candidate as JsonRow).position === relation.ingredient_position) as JsonRow | undefined
      if (!ingredient || typeof ingredient.name !== 'string' || typeof ingredient.unit !== 'string') return []
      return [{ name: ingredient.name, quantity: Number(relation.quantity_override ?? ingredient.quantity) || 0, unit: ingredient.unit }]
    }) : []
    return [{
      ...(typeof item.duration_minutes === 'number' ? { durationMinutes: item.duration_minutes } : {}),
      ...(typeof item.temperature === 'string' ? { temperature: item.temperature } : {}),
      ...(typeof item.tip === 'string' ? { tip: item.tip } : {}),
      ...(typeof item.warning === 'string' ? { warning: item.warning } : {}),
      ...(typeof item.special_instructions === 'string' ? { specialInstructions: item.special_instructions } : {}),
      ...(Array.isArray(item.utensils) ? { utensils: strings(item.utensils) } : {}),
      ...(linked.length ? { stepIngredients: linked } : {}),
    }]
  })
  const mealShifts = strings(row.meal_shifts).map((item) => shifts[item] ?? item)
  const minutes = Number(row.total_minutes)
  const portions = Number(row.portions)
  const calories = typeof row.calories_per_portion === 'number'
    || typeof row.calories_per_portion === 'string' && row.calories_per_portion.trim() !== ''
    ? Number(row.calories_per_portion) : Number.NaN
  const recipe: Recipe = {
    id: legacyId ?? relationalId,
    relationalId,
    legacyId,
    name: row.title,
    description: typeof row.description === 'string' ? row.description : '',
    category: mealShifts[0] ?? 'Almuerzo',
    mealShifts,
    minutes: Number.isFinite(minutes) ? minutes : 0,
    portions: Number.isFinite(portions) && portions > 0 ? portions : 1,
    difficulty: difficulties[String(row.difficulty)] ?? 'Intermedia',
    ingredients: ingredientRows.flatMap((value) => {
      if (!value || typeof value !== 'object') return []
      const item = value as JsonRow
      if (typeof item.name !== 'string' || typeof item.unit !== 'string') return []
      return [{ name: item.name, quantity: Number(item.quantity) || 0, unit: item.unit, ...(typeof item.category === 'string' ? { category: item.category } : {}) }]
    }),
    steps,
    stepMeta,
    symbol: typeof row.symbol === 'string' ? row.symbol : '🍽️',
    color: row.color === 'gold' || row.color === 'pink' || row.color === 'blue' ? row.color : 'green',
    dietaryTags: strings(row.dietary_tags),
    ...(Number.isFinite(calories) ? { calories } : {}),
    ...(typeof row.image_path === 'string' ? { image: row.image_path } : {}),
    ...(typeof row.image_alt === 'string' ? { imageAlt: row.image_alt } : {}),
    ...(typeof row.cross_contamination_note === 'string' ? { crossContaminationNote: row.cross_contamination_note } : {}),
    ...(row.featured === true ? { featured: true } : {}),
  }
  return recipe
}

function mapStock(raw: unknown): IngredientDeficit[] {
  if (!raw || typeof raw !== 'object' || !Array.isArray((raw as JsonRow).ingredients)) return []
  return ((raw as JsonRow).ingredients as unknown[]).flatMap((value) => {
    if (!value || typeof value !== 'object') return []
    const row = value as JsonRow
    if (typeof row.name !== 'string' || typeof row.unit !== 'string') return []
    const required = Number(row.required) || 0
    const available = Number(row.available) || 0
    const missing = Number(row.missing) || 0
    return [{ ingredient: { name: row.name, quantity: required, unit: row.unit }, required, available, missing }]
  })
}

export function createSupabaseRecipeRepository(deps: RecipeRepositoryDependencies): RecipeRepository {
  async function call(name: string, args: Record<string, unknown>, session = deps.captureSession()): Promise<unknown> {
    const owner = await deps.getUser(session)
    deps.assertCurrent(session)
    const result = await deps.rpc(name, args, session)
    deps.assertCurrent(session)
    const afterOwner = await deps.getUser(session)
    deps.assertCurrent(session)
    deps.assertOwner(session, afterOwner)
    if (owner !== afterOwner) throw new Error('La cuenta cambió mientras se consultaban las recetas.')
    return result
  }
  async function known(): Promise<Recipe[]> {
    const session = deps.captureSession()
    const recipes: Recipe[] = []
    for (let offset = 0; offset <= 5000; offset += 500) {
      const result = await call('list_known_recipes', { p_limit: 500, p_offset: offset }, session)
      if (!Array.isArray(result)) throw new Error('El servidor devolvió un catálogo inválido.')
      recipes.push(...result.map(mapRecipe))
      if (result.length < 500) return recipes
    }
    throw new Error('El catálogo supera el límite de lectura permitido.')
  }
  async function read(id: string, includeInactive = false): Promise<RecipeReadEnvelope | null> {
    const session = deps.captureSession()
    // Resolve historical keys explicitly first. UUID-shaped legacy IDs remain legacy IDs.
    const legacy = await call('get_my_recipe_detail', { p_recipe_id: null, p_legacy_id: id, p_include_inactive: includeInactive }, session) as RecipeReadEnvelope | null
    if (legacy?.recipe) return legacy
    if (!/^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(id)) return null
    return await call('get_my_recipe_detail', { p_recipe_id: id, p_legacy_id: null, p_include_inactive: includeInactive }, session) as RecipeReadEnvelope | null
  }
  async function discover(filters: Partial<RecipeFilters> = {}, portions?: number): Promise<Array<{ recipe: Recipe; percentage: number; label: string; ingredients: IngredientDeficit[] }>> {
    const session = deps.captureSession()
    const selectedPreferences = (filters.preferences ?? []).map((item) => preferenceKeys[item])
    const args = {
      p_search: filters.search?.trim() || null,
      p_meal_shift: filters.category ? Object.entries(shifts).find(([, label]) => label === filters.category)?.[0] ?? null : null,
      p_max_minutes: filters.maxMinutes ?? null,
      p_difficulty: filters.difficulty ? Object.entries(difficulties).find(([, label]) => label === filters.difficulty)?.[0] ?? null : null,
      p_dietary_tag_keys: selectedPreferences,
      p_pantry_only: filters.pantryOnly ?? false,
      p_portions: portions ?? null,
      p_limit: 50,
    }
    const matches: Array<{ recipe: Recipe; percentage: number; label: string; ingredients: IngredientDeficit[] }> = []
    let total = 0
    for (let offset = 0; offset <= 5000; offset += 50) {
      const result = await call('search_my_recipes', { ...args, p_offset: offset }, session)
      if (!result || typeof result !== 'object' || !Array.isArray((result as JsonRow).items)) throw new Error('El servidor devolvió una búsqueda inválida.')
      const envelope = result as JsonRow
      const items = envelope.items as unknown[]
      total = typeof envelope.total === 'number' ? envelope.total : offset + items.length
      matches.push(...items.map((value) => {
        if (!value || typeof value !== 'object') throw new Error('El servidor devolvió un resultado inválido.')
        const row = value as JsonRow
        const recipe = mapRecipe(row.recipe)
        return { recipe, percentage: typeof row.percentage === 'number' ? row.percentage : 0, label: typeof row.label === 'string' ? row.label : 'Disponibilidad no calculable', ingredients: mapStock(row.stock) }
      }))
      if (matches.length >= total || items.length < 50) return matches
    }
    throw new Error('La búsqueda supera el límite de lectura permitido.')
  }
  return {
    async list() { return (await discover()).map((item) => item.recipe) },
    async listKnown() { return known() },
    async getById(id, includeInactive = false) { const envelope = await read(id, includeInactive); return envelope?.recipe ? mapRecipe(envelope.recipe) : undefined },
    async match(_pantry, filters = {}, portions) { return discover(filters, portions) },
    async getReadiness(id, _pantry, portions, includeInactive = false) {
      const session = deps.captureSession()
      const recipe = await this.getById(id, includeInactive)
      deps.assertCurrent(session)
      if (!recipe?.relationalId) return undefined
      const stock = await call('check_my_cooking_stock', { p_recipe_id: recipe.relationalId, p_portions: portions ?? recipe.portions, p_session_id: null }, session) as JsonRow
      const ingredients = mapStock(stock)
      const ready = ingredients.filter((item) => item.missing === 0).length
      const percentage = ingredients.length ? (ready === ingredients.length ? 100 : Math.min(99, Math.round(ready / ingredients.length * 100))) : 0
      return { percentage, label: percentage === 100 ? 'Lista para cocinar' : percentage >= 60 ? 'Casi lista' : 'Requiere compra', ingredients }
    },
    async getDietaryPreferences() { return (await deps.getProfile()).preferences ?? [] },
    async getProfile() { return deps.getProfile() },
  }
}

export const supabaseRecipeRepository = createSupabaseRecipeRepository({
  captureSession: capturePersonalDataSession,
  assertCurrent: assertPersonalDataSessionCurrent,
  assertOwner: assertPersonalDataOwner,
  async getUser(session) {
    if (!supabase) throw new Error('No está disponible la conexión con recetas.')
    assertPersonalDataSessionCurrent(session)
    const { data: { user }, error } = await supabase.auth.getUser()
    if (error) throw error
    if (!user) throw new Error('Iniciá sesión para consultar tus recetas.')
    assertPersonalDataOwner(session, user.id)
    return user.id
  },
  async rpc(name, args, session) {
    if (!supabase) throw new Error('No está disponible la conexión con recetas.')
    assertPersonalDataSessionCurrent(session)
    const { data, error } = await supabase.rpc(name, args)
    if (error) throw error
    return data
  },
  getProfile: () => profileRepository.getProfile(),
})

export function isRelationalRecipeRepositoryEnabled(): boolean { return isRelationalRecipesEnabled && supabase !== null }
