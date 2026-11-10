import assert from 'node:assert/strict'
import test from 'node:test'
import { createRelationalAdminRecipes } from '../src/features/admin/data/relationalAdminRecipes.ts'
import type { AdminRecipeInput } from '../src/features/admin/data/recipesStore.ts'

type Row = Record<string, unknown>
const recipeId = '11111111-1111-4111-8111-111111111111'
const adminRecipe = {
  title: 'Sopa', author: 'CocinAPP', description: 'Suave', category: 'Cena', mealShift: 'Cena', mealShifts: ['Cena'], minutes: 25,
  portions: 2, difficulty: 'Fácil', calories: 120, dietaryTags: ['vegana'], featured: false,
  ingredients: [{ ingredientId: 'ingredient-1', quantity: 2, unitId: 'unit-1', note: 'picado' }], steps: ['Cocinar'],
  stepMeta: [{ durationMinutes: 10, ingredientIds: ['ingredient-1'], utensils: ['Olla'] }], status: 'published', active: true,
  symbol: '🍲', color: 'green', image: '/assets/recipes/sopa.webp', imageAlt: 'Sopa',
} satisfies AdminRecipeInput

function exported(overrides: Row = {}): Row {
  return {
    id: recipeId, version: 4, title: 'Sopa', author: 'CocinAPP', description: 'Suave', category_label: 'Cena', total_minutes: 25,
    preparation_minutes: 5, cooking_minutes: 20, portions: 2, difficulty: 'easy', calories_per_portion: 120,
    publication_status: 'published', active: true, is_deleted: false, featured: false, symbol: '🍲', color: 'green',
    image_path: '/assets/recipes/sopa.webp', image_alt: 'Sopa', meal_shifts: ['dinner'], dietary_tags: ['vegana'],
    ingredients: [{ ingredient_id: 'ingredient-1', quantity: 2, unit_id: 'unit-1', note: 'picado', position: 1 }],
    steps: [{ instruction: 'Cocinar', position: 1, duration_minutes: 10, utensils: ['Olla'], ingredients: [{ ingredient_position: 1, quantity_override: 0.5 }] }],
    ...overrides,
  }
}

function harness(options: { role?: string; conflict?: boolean; expireOnRpc?: string; firstSaveError?: boolean } = {}) {
  const calls: { name: string; args: Row }[] = []
  let token = 'session-a'
  let failedSave = false
  const client = {
    auth: { getSession: async () => ({ data: { session: { access_token: token, user: { id: 'admin-a' } } }, error: null }) },
    rpc: async (name: string, args: Row) => {
      calls.push({ name, args })
      if (options.expireOnRpc === name) token = 'session-b'
      if (name === 'current_app_role') return { data: options.role ?? 'ADMIN', error: null }
      if (name === 'admin_get_recipe') return { data: exported(), error: null }
      if (name === 'admin_save_recipe') {
        if (options.firstSaveError && !failedSave) { failedSave = true; return { data: null, error: { code: '40001', message: 'duplicate retry' } } }
        if (options.conflict) return { data: null, error: { code: '40001', message: 'stale' } }
        const row = exported({ version: Number(args.p_expected_version) + 1, ...(args.p_recipe as Row) })
        return { data: row, error: null }
      }
      if (name === 'admin_set_recipe_flags') return { data: exported({ ...args, version: 5 }), error: null }
      if (name === 'admin_duplicate_recipe') return { data: exported({ id: args.p_target_id, version: 1, publication_status: 'draft' }), error: null }
      if (name === 'get_my_recipe_detail') return { data: { recipe: { id: recipeId } }, error: null }
      return { data: null, error: null }
    },
    from: (table: string) => {
      assert.equal(table, 'recetas')
      const query = {
        select: () => query, eq: () => query, is: () => query, order: () => query,
        range: async () => ({ data: [{ id: recipeId }], error: null }),
      }
      return query
    },
  }
  const repo = createRelationalAdminRecipes({ getClient: () => client as never })
  return { repo, calls }
}

test('loads official drafts and inactive recipes through admin_get_recipe with the version baseline', async () => {
  const { repo, calls } = harness()
  const recipes = await repo.listRecipes()
  assert.equal(recipes.length, 1)
  assert.equal(recipes[0]?.mealShift, 'Cena')
  assert.equal(recipes[0]?.difficulty, 'Fácil')
  assert.equal(recipes[0]?.stepMeta?.[0]?.ingredientIds?.[0], 'ingredient-1')
  assert.deepEqual(calls.find(({ name }) => name === 'admin_get_recipe')?.args, { p_recipe_id: recipeId })
})

test('coalesces concurrent recipe list reads for the same admin session', async () => {
  const { repo, calls } = harness()
  const [first, second] = await Promise.all([repo.listRecipes(), repo.listRecipes()])
  assert.deepEqual(first, second)
  assert.equal(calls.filter(({ name }) => name === 'admin_get_recipe').length, 1)
})

test('sends SQL recipe payloads, expected version, and preserves step ingredient overrides', async () => {
  const { repo, calls } = harness()
  const [loaded] = await repo.listRecipes()
  await repo.updateRecipe(recipeId, { ...adminRecipe, stepMeta: loaded!.stepMeta })
  const call = calls.find(({ name }) => name === 'admin_save_recipe')
  assert.ok(call)
  assert.equal(call.args.p_expected_version, 4)
  const payload = call.args.p_recipe as Row
  assert.deepEqual(payload.meal_shifts, ['dinner'])
  assert.deepEqual(payload.ingredients, [{ ingredient_id: 'ingredient-1', quantity: 2, unit_id: 'unit-1', note: 'picado' }])
  assert.deepEqual((payload.steps as Row[])[0]?.ingredients, [{ ingredient_position: 1, quantity_override: 0.5 }])
})

test('enforces ADMIN and rejects a session that changes during a recipe read', async () => {
  await assert.rejects(harness({ role: 'USER' }).repo.listRecipes(), /Solo una cuenta administradora/)
  await assert.rejects(harness({ expireOnRpc: 'admin_get_recipe' }).repo.listRecipes(), /La sesión cambió/)
})

test('reports optimistic conflicts without replacing the loaded version', async () => {
  const { repo } = harness({ conflict: true })
  await repo.listRecipes()
  await assert.rejects(repo.updateRecipe(recipeId, adminRecipe), /recargá los datos/)
})

test('flag actions advance the cached version baseline from the RPC response', async () => {
  const { repo, calls } = harness()
  await repo.listRecipes()
  await repo.setRecipeActive(recipeId, false)
  await repo.setRecipeFeatured(recipeId, true)
  const flags = calls.filter(({ name }) => name === 'admin_set_recipe_flags')
  assert.equal(flags[0]?.args.p_expected_version, 4)
  assert.equal(flags[1]?.args.p_expected_version, 5)
})

test('retries a create with the same UUID and supports duplicate with a new stable target UUID', async () => {
  const { repo, calls } = harness({ firstSaveError: true })
  await assert.rejects(repo.createRecipe(adminRecipe))
  const createdId = await repo.createRecipe(adminRecipe)
  const creates = calls.filter(({ name }) => name === 'admin_save_recipe')
  assert.equal(creates[0]?.args.p_recipe_id, creates[1]?.args.p_recipe_id)
  assert.equal(creates[1]?.args.p_recipe_id, createdId)
  const copiedId = await repo.duplicateRecipe(recipeId)
  assert.notEqual(copiedId, recipeId)
  assert.equal(calls.find(({ name }) => name === 'admin_duplicate_recipe')?.args.p_target_id, copiedId)
})

test('moving a loaded step preserves its override while a new step starts without one', async () => {
  const { repo, calls } = harness()
  const [loaded] = await repo.listRecipes()
  await repo.updateRecipe(recipeId, { ...loaded!, steps: ['Paso nuevo', 'Cocinar'],
    stepMeta: [{ ingredientIds: ['ingredient-1'] }, loaded!.stepMeta![0]!] })
  const payload = calls.find(({ name }) => name === 'admin_save_recipe')!.args.p_recipe as Row
  const steps = payload.steps as Row[]
  assert.deepEqual(steps[0]!.ingredients, [{ ingredient_position: 1, quantity_override: null }])
  assert.deepEqual(steps[1]!.ingredients, [{ ingredient_position: 1, quantity_override: 0.5 }])
})
