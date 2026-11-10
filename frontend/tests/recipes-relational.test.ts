import assert from 'node:assert/strict'
import test from 'node:test'
import { createSupabaseRecipeRepository } from '../src/features/recipes/data/SupabaseRecipeRepository.ts'
import { createSupabaseFavoriteRepository } from '../src/features/recipes/data/supabaseFavoriteRepository.ts'
import type { PersonalDataSession } from '../src/shared/data/personalDataSession.ts'

const session: PersonalDataSession = { token: 'supabase-user:owner-1', localRevision: 0, supabaseRevision: 0 }
const relationalId = '11111111-1111-4111-8111-111111111111'
const legacyUuid = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'
const baseRecipe = {
  id: relationalId, legacy_id: legacyUuid, title: 'Sopa', description: 'Rica', total_minutes: 20, portions: 2,
  difficulty: 'easy', meal_shifts: ['dinner'], dietary_tags: ['vegan'],
  ingredients: [{ position: 1, name: 'Calabaza', quantity: 2, unit: 'kg' }],
  steps: [{ instruction: 'Cocinar', duration_minutes: 10, ingredients: [{ ingredient_position: 1, quantity_override: 1 }] }],
}

function createHarness(respond: (name: string, args: Record<string, unknown>) => unknown, options: { stale?: boolean } = {}) {
  let current = true
  const calls: Array<{ name: string; args: Record<string, unknown> }> = []
  const repository = createSupabaseRecipeRepository({
    captureSession: () => session,
    assertCurrent: () => { if (options.stale && !current) throw new Error('session changed') },
    assertOwner: () => { if (options.stale && !current) throw new Error('session changed') },
    getUser: async () => 'owner-1',
    rpc: async (name, args) => { calls.push({ name, args }); return respond(name, args) },
    getProfile: async () => ({ preferences: ['vegan'] }),
  })
  return { repository, calls, expire: () => { current = false } }
}

test('maps relational discovery payloads and AND-style dietary filters', async () => {
  const harness = createHarness((name) => name === 'search_my_recipes' ? {
    total: 1, items: [{ recipe: baseRecipe, stock: { ingredients: [{ name: 'Calabaza', unit: 'kg', required: 1, available: 0.5, missing: 0.5 }] }, percentage: 0, label: 'Requiere compra' }],
  } : null)
  const result = await harness.repository.match([], { preferences: ['vegan'], category: 'Cena', difficulty: 'Fácil' })
  assert.equal(result[0]?.recipe.id, legacyUuid)
  assert.equal(result[0]?.recipe.relationalId, relationalId)
  assert.equal(result[0]?.recipe.stepMeta?.[0]?.durationMinutes, 10)
  assert.equal(result[0]?.ingredients[0]?.missing, 0.5)
  assert.deepEqual(harness.calls[0]?.args.p_dietary_tag_keys, ['vegan'])
  assert.equal(harness.calls[0]?.args.p_meal_shift, 'dinner')
})

test('uses the explicit legacy argument before UUID lookup, preserving UUID-shaped legacy IDs', async () => {
  const harness = createHarness((name, args) => name === 'get_my_recipe_detail' && args.p_legacy_id === legacyUuid ? { recipe: baseRecipe } : null)
  const recipe = await harness.repository.getById(legacyUuid, true)
  assert.equal(recipe?.relationalId, relationalId)
  assert.equal(harness.calls.length, 1)
  assert.equal(harness.calls[0]?.args.p_recipe_id, null)
})

test('missing calorie estimates stay absent while explicit calorie values are preserved', async () => {
  for (const value of [null, undefined, '', 0, 240, '240']) {
    const harness = createHarness(() => ({ recipe: { ...baseRecipe, calories_per_portion: value } }))
    const recipe = await harness.repository.getById(legacyUuid, true)
    assert.equal(recipe?.calories, value === null || value === undefined || value === '' ? undefined : Number(value))
  }
})

test('falls back to UUID identity only when the explicit legacy lookup is empty', async () => {
  const harness = createHarness((name, args) => name === 'get_my_recipe_detail' && args.p_recipe_id === relationalId ? { recipe: { ...baseRecipe, legacy_id: null } } : null)
  const recipe = await harness.repository.getById(relationalId, true)
  assert.equal(recipe?.id, relationalId)
  assert.deepEqual(harness.calls.map((call) => call.args.p_legacy_id ?? call.args.p_recipe_id), [relationalId, relationalId])
})

test('allows an explicit inactive read and rejects stale session responses', async () => {
  const inactive = createHarness((name, args) => name === 'get_my_recipe_detail' && args.p_legacy_id === 'old-key' && args.p_include_inactive === true ? { recipe: baseRecipe } : null)
  assert.equal((await inactive.repository.getById('old-key', true))?.name, 'Sopa')
  const stale = createHarness((name) => {
    if (name === 'search_my_recipes') return { total: 0, items: [] }
    return null
  }, { stale: true })
  stale.expire()
  await assert.rejects(stale.repository.list(), /session changed/)
})

test('reads visible favorites through the personal RPC and changes one UUID without replacing the collection', async () => {
  const calls: Array<{ name: string; args: Record<string, unknown> }> = []
  const repository = createSupabaseFavoriteRepository({
    captureSession: () => session,
    assertCurrent: () => undefined,
    assertOwner: () => undefined,
    getUser: async () => 'owner-1',
    rpc: async (name, args) => {
      calls.push({ name, args })
      if (name === 'get_my_favorites') return { items: [{ recipe_id: relationalId, available: true, recipe: baseRecipe }] }
      return null
    },
    resolve: async () => relationalId,
  })
  assert.deepEqual(await repository.listIds(), [legacyUuid])
  await repository.setFavorite?.('recipe-key', true)
  assert.equal(calls[0]?.name, 'get_my_favorites')
  assert.deepEqual(calls[1], { name: 'set_my_favorite', args: { p_recipe_id: relationalId, p_is_favorite: true } })
})

test('rejects favorite responses when account ownership changes and forbids destructive snapshot replacement', async () => {
  const repository = createSupabaseFavoriteRepository({
    captureSession: () => session,
    assertCurrent: () => undefined,
    assertOwner: () => { throw new Error('permission changed') },
    getUser: async () => 'other-user',
    rpc: async () => ({ items: [] }),
    resolve: async () => relationalId,
  })
  await assert.rejects(repository.listIds(), /permission changed/)
  await assert.rejects(repository.saveIds([]), /de forma individual/)
})
