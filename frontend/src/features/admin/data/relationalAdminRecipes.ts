import type { AdminRecipe } from '../domain/adminModels'
import type { Recipe } from '../../recipes/domain/Recipe'
import type { DeleteResult } from './deleteResult'
import type { AdminRecipeInput } from './recipesStore'
import { supabase } from '../../../shared/data/supabaseClient'

type Row = Record<string, unknown>
type Client = NonNullable<typeof supabase>
type RecipeClient = Pick<Client, 'auth' | 'rpc' | 'from'>
export interface RelationalAdminRecipesOptions { getClient?: () => RecipeClient | null }

const shiftsFromDb: Record<string, string> = { breakfast: 'Desayuno', lunch: 'Almuerzo', snack: 'Merienda', dinner: 'Cena' }
const shiftsToDb: Record<string, string> = Object.fromEntries(Object.entries(shiftsFromDb).map(([key, value]) => [value, key]))
const difficultiesFromDb: Record<string, AdminRecipe['difficulty']> = { easy: 'Fácil', intermediate: 'Intermedia', advanced: 'Avanzada' }
const difficultiesToDb: Record<AdminRecipe['difficulty'], string> = { Fácil: 'easy', Intermedia: 'intermediate', Avanzada: 'advanced' }

function fail(message: string): never { throw new Error(message) }
function asRow(value: unknown): Row {
  if (!value || typeof value !== 'object' || Array.isArray(value)) return fail('Supabase devolvió una receta inválida.')
  return value as Row
}
function text(row: Row, key: string, fallback = ''): string { return typeof row[key] === 'string' ? row[key] as string : fallback }
function number(row: Row, key: string, fallback = 0): number { return typeof row[key] === 'number' && Number.isFinite(row[key]) ? row[key] as number : fallback }
function textArray(value: unknown): string[] { return Array.isArray(value) ? value.filter((item): item is string => typeof item === 'string') : [] }
function uuid(): string { return globalThis.crypto.randomUUID() }

function create(options: RelationalAdminRecipesOptions = {}) {
  const getClient = options.getClient ?? (() => supabase)
  const baselines = new Map<string, Map<string, { version: number; row: Row }>>()
  const refsByAccount = new Map<string, Map<string, Map<string, Map<string, number | null>>>>()
  const listRevisions = new Map<string, number>()
  const pendingLists = new Map<string, Promise<AdminRecipe[]>>()
  const pendingCreates = new Map<string, Map<string, string>>()
  const pendingDuplicates = new Map<string, Map<string, string>>()

  async function authorized() {
    const client = getClient()
    if (!client) fail('Supabase no está configurado.')
    const { data: before, error: sessionError } = await client.auth.getSession()
    if (sessionError || !before.session?.access_token || !before.session.user.id) fail('La sesión administrativa no está disponible.')
    const token = before.session.access_token
    const userId = before.session.user.id
    const verify = async () => {
      const { data, error } = await client.auth.getSession()
      if (error || data.session?.access_token !== token || data.session.user.id !== userId) fail('La sesión cambió durante la operación. Volvé a cargar las recetas.')
    }
    const { data: role, error } = await client.rpc('current_app_role')
    await verify()
    if (error) throw error
    if (role !== 'ADMIN') fail('Solo una cuenta administradora puede gestionar recetas.')
    const account = `${userId}:${token}`
    if (!baselines.has(account)) baselines.set(account, new Map())
    if (!refsByAccount.has(account)) refsByAccount.set(account, new Map())
    if (!pendingCreates.has(account)) pendingCreates.set(account, new Map())
    if (!pendingDuplicates.has(account)) pendingDuplicates.set(account, new Map())
    return { client, account, verify }
  }

  function parseRecipe(value: unknown, account: string, commitBaseline = true): AdminRecipe {
    const row = asRow(value)
    if (typeof row.id !== 'string' || typeof row.version !== 'number' || !Number.isInteger(row.version) || row.version < 1) return fail('Supabase devolvió una receta sin versión válida.')
    const ingredients = (Array.isArray(row.ingredients) ? row.ingredients : []).map((value, index) => {
      const entry = asRow(value)
      return { ingredientId: text(entry, 'ingredient_id'), unitId: text(entry, 'unit_id'), quantity: number(entry, 'quantity'), note: text(entry, 'note'), position: number(entry, 'position', index + 1) }
    }).sort((a, b) => a.position - b.position)
    const steps = (Array.isArray(row.steps) ? row.steps : []).map((value, index) => ({ row: asRow(value), position: number(asRow(value), 'position', index + 1) })).sort((a, b) => a.position - b.position)
    const rawRefs = new Map<string, Map<string, number | null>>()
    steps.forEach(({ row: step }, stepIndex) => (Array.isArray(step.ingredients) ? step.ingredients : []).forEach((value) => {
      const ref = asRow(value)
      const position = number(ref, 'ingredient_position')
      const ingredientId = ingredients[position - 1]?.ingredientId
      if (!ingredientId) return
      const byIngredient = rawRefs.get(String(stepIndex)) ?? new Map<string, number | null>()
      byIngredient.set(ingredientId, typeof ref.quantity_override === 'number' ? ref.quantity_override : null)
      rawRefs.set(String(stepIndex), byIngredient)
    }))
    if (commitBaseline) refsByAccount.get(account)!.set(row.id, rawRefs)
    const mealShifts = textArray(row.meal_shifts).map((shift) => shiftsFromDb[shift] ?? shift)
    const difficulty = difficultiesFromDb[String(row.difficulty)]
    if (!difficulty) return fail('Supabase devolvió una dificultad de receta inválida.')
    const shift = mealShifts[0] ?? 'Almuerzo'
    const recipe: AdminRecipe = {
      id: row.id, title: text(row, 'title'), author: text(row, 'author', 'CocinAPP'), description: text(row, 'description'),
      category: shift, mealShift: shift, mealShifts, minutes: number(row, 'total_minutes', 30), portions: number(row, 'portions', 1), difficulty,
      calories: number(row, 'calories_per_portion'), dietaryTags: textArray(row.dietary_tags), featured: row.featured === true,
      ingredients: ingredients.map(({ ingredientId, unitId, quantity, note }) => ({ ingredientId, unitId, quantity, note })),
      steps: steps.map(({ row: step }) => text(step, 'instruction')),
      stepMeta: steps.map(({ row: step }, stepIndex) => ({
        relationalStepKey: String(stepIndex),
        durationMinutes: typeof step.duration_minutes === 'number' ? step.duration_minutes : undefined,
        ingredientIds: (Array.isArray(step.ingredients) ? step.ingredients : []).flatMap((value) => {
          const position = number(asRow(value), 'ingredient_position')
          return ingredients[position - 1] ? [ingredients[position - 1]!.ingredientId] : []
        }),
        utensils: textArray(step.utensils), tip: text(step, 'tip') || undefined, warning: text(step, 'warning') || undefined,
        temperature: text(step, 'temperature') || undefined, specialInstructions: text(step, 'special_instructions') || undefined,
      })),
      status: row.publication_status === 'published' ? 'published' : 'draft', active: row.active === true, isDeleted: row.is_deleted === true,
      symbol: text(row, 'symbol', 'R'), color: row.color === 'gold' || row.color === 'pink' || row.color === 'blue' ? row.color : 'green',
      image: typeof row.image_path === 'string' ? row.image_path : undefined, imageAlt: typeof row.image_alt === 'string' ? row.image_alt : undefined,
      preparationMinutes: typeof row.preparation_minutes === 'number' ? row.preparation_minutes : undefined,
      cookingMinutes: typeof row.cooking_minutes === 'number' ? row.cooking_minutes : undefined,
      createdAt: typeof row.created_at === 'string' ? row.created_at : undefined, updatedAt: typeof row.updated_at === 'string' ? row.updated_at : undefined,
    }
    if (commitBaseline) baselines.get(account)!.set(row.id, { version: row.version, row })
    return recipe
  }

  function payload(recipe: AdminRecipeInput, id: string, account: string): Row {
    const mealShifts = (recipe.mealShifts?.length ? recipe.mealShifts : [recipe.mealShift]).map((shift) => shiftsToDb[shift] ?? shift)
    const previousRefs = refsByAccount.get(account)?.get(id) ?? new Map()
    const baseline = baselines.get(account)?.get(id)?.row
    return {
      title: recipe.title, author: recipe.author, description: recipe.description, category_label: recipe.category,
      meal_shifts: mealShifts, total_minutes: recipe.minutes, preparation_minutes: recipe.preparationMinutes ?? null, cooking_minutes: recipe.cookingMinutes ?? null,
      portions: recipe.portions, difficulty: difficultiesToDb[recipe.difficulty], calories_per_portion: recipe.calories, dietary_tags: recipe.dietaryTags,
      featured: recipe.featured ?? false, symbol: recipe.symbol, color: recipe.color, cross_contamination_note: baseline?.cross_contamination_note ?? null,
      image_path: recipe.image ?? null, image_alt: recipe.imageAlt ?? null, publication_status: recipe.status, active: recipe.active ?? true,
      ingredients: recipe.ingredients.map((item) => ({ ingredient_id: item.ingredientId, quantity: item.quantity, unit_id: item.unitId, note: item.note ?? '' })),
      steps: recipe.steps.map((instruction, stepIndex) => {
        const meta = recipe.stepMeta?.[stepIndex] ?? {}
        const ingredientRefs = (meta.ingredientIds ?? []).flatMap((ingredientId) => {
          const position = recipe.ingredients.findIndex((item) => item.ingredientId === ingredientId) + 1
          if (!position) return []
          const previous = meta.relationalStepKey === undefined ? undefined : previousRefs.get(meta.relationalStepKey)?.get(ingredientId)
          return [{ ingredient_position: position, quantity_override: previous ?? null }]
        })
        return { instruction, duration_minutes: meta.durationMinutes ?? meta.minutes ?? null, temperature: meta.temperature ?? null,
          tip: meta.tip ?? null, warning: meta.warning ?? null, utensils: meta.utensils ?? [], special_instructions: meta.specialInstructions ?? null, ingredients: ingredientRefs }
      }),
    }
  }
  function expectedVersion(account: string, id: string): number {
    const baseline = baselines.get(account)?.get(id)
    if (!baseline) return fail('No hay una versión cargada para esta receta. Recargá el catálogo.')
    return baseline.version
  }
  async function getRecipe(client: RecipeClient, account: string, verify: () => Promise<void>, id: string, isCurrent = () => true): Promise<AdminRecipe | undefined> {
    const { data, error } = await client.rpc('admin_get_recipe', { p_recipe_id: id })
    await verify()
    if (error) throw error
    return data === null ? undefined : parseRecipe(data, account, isCurrent())
  }
  async function save(client: RecipeClient, account: string, verify: () => Promise<void>, id: string, recipe: AdminRecipeInput, expected: number): Promise<void> {
    const { data, error } = await client.rpc('admin_save_recipe', { p_recipe_id: id, p_recipe: payload(recipe, id, account), p_expected_version: expected })
    await verify()
    if (error) throw new Error(error.code === '40001' ? 'La receta cambió; recargá los datos.' : error.message, { cause: error })
    parseRecipe(data, account)
  }
  async function changeFlag(id: string, args: Row): Promise<void> {
    const { client, account, verify } = await authorized()
    const { data, error } = await client.rpc('admin_set_recipe_flags', { p_recipe_id: id, p_expected_version: expectedVersion(account, id), ...args })
    await verify()
    if (error) throw error
    parseRecipe(data, account)
  }

  return {
    async listRecipes(): Promise<AdminRecipe[]> {
      const { client, account, verify } = await authorized()
      const pending = pendingLists.get(account)
      if (pending) {
        const recipes = await pending
        await verify()
        return recipes
      }
      const revision = (listRevisions.get(account) ?? 0) + 1
      listRevisions.set(account, revision)
      const load = (async () => {
        const rows: Row[] = []
        for (let offset = 0; ; offset += 500) {
          const { data, error } = await client.from('recetas').select('id').eq('recipe_source', 'official').is('owner_user_id', null).order('id').range(offset, offset + 499)
          await verify()
          if (error) throw error
          const page = data as Row[] | null
          if (!page) return fail('No se pudo leer el catálogo de recetas.')
          rows.push(...page)
          if (page.length < 500) break
        }
        const result = await Promise.all(rows.map((row) => getRecipe(client, account, verify, String(row.id), () => listRevisions.get(account) === revision)))
        await verify()
        if (listRevisions.get(account) !== revision) return fail('La lista de recetas quedó desactualizada. Volvé a cargarla.')
        return result.filter((recipe): recipe is AdminRecipe => recipe !== undefined)
      })()
      pendingLists.set(account, load)
      try {
        const recipes = await load
        await verify()
        return recipes
      } finally {
        if (pendingLists.get(account) === load) pendingLists.delete(account)
      }
    },
    async createRecipe(recipe: AdminRecipeInput): Promise<string> {
      const { client, account, verify } = await authorized()
      const key = JSON.stringify(recipe)
      const ids = pendingCreates.get(account)!
      const id = ids.get(key) ?? uuid()
      ids.set(key, id)
      await save(client, account, verify, id, recipe, 0)
      ids.delete(key)
      return id
    },
    async updateRecipe(id: string, recipe: AdminRecipeInput): Promise<void> {
      const { client, account, verify } = await authorized()
      await save(client, account, verify, id, recipe, expectedVersion(account, id))
    },
    async deleteRecipe(id: string): Promise<DeleteResult> {
      const { account } = await authorized()
      if (!baselines.get(account)?.has(id)) return 'not-found'
      await changeFlag(id, { p_archived: true })
      return 'deactivated'
    },
    async restoreRecipe(id: string): Promise<void> { await changeFlag(id, { p_restored: true }) },
    async duplicateRecipe(id: string): Promise<string> {
      const { client, account, verify } = await authorized()
      const ids = pendingDuplicates.get(account)!
      const targetId = ids.get(id) ?? uuid()
      ids.set(id, targetId)
      const { data, error } = await client.rpc('admin_duplicate_recipe', { p_source_id: id, p_target_id: targetId, p_expected_version: 0 })
      await verify()
      if (error) throw error
      parseRecipe(data, account)
      ids.delete(id)
      return targetId
    },
    async setRecipeActive(id: string, active: boolean): Promise<void> {
      const { client, account, verify } = await authorized()
      const archived = baselines.get(account)?.get(id)?.row.is_deleted === true
      const { data, error } = await client.rpc('admin_set_recipe_flags', {
        p_recipe_id: id, p_expected_version: expectedVersion(account, id), p_active: active,
        ...(active && archived ? { p_restored: true } : {}),
      })
      await verify()
      if (error) throw error
      parseRecipe(data, account)
    },
    async setRecipeFeatured(id: string, featured: boolean): Promise<void> { await changeFlag(id, { p_featured: featured }) },
    async createSeedRecipeOverride(recipe: Recipe): Promise<AdminRecipe> {
      const { client, account, verify } = await authorized()
      let id = recipe.relationalId
      if (!id) {
        const { data, error } = await client.rpc('get_my_recipe_detail', { p_recipe_id: null, p_legacy_id: recipe.legacyId ?? recipe.id, p_include_inactive: true })
        await verify()
        if (error) throw error
        const outer = data === null ? undefined : asRow(data)
        const inner = outer?.recipe === undefined ? undefined : asRow(outer.recipe)
        id = typeof inner?.id === 'string' ? inner.id : undefined
      }
      if (!id) return fail('Esta receta todavía no tiene una versión relacional. Actualizá el catálogo o esperá la conversión inicial antes de editarla.')
      const loaded = await getRecipe(client, account, verify, id)
      if (!loaded) return fail('La receta oficial no está disponible para edición.')
      return loaded
    },
  }
}

export const createRelationalAdminRecipes = create
export const relationalAdminRecipes = create()
