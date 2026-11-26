import assert from 'node:assert/strict'
import test from 'node:test'
import { createSupabasePlannerRepository } from '../src/features/planner/data/SupabasePlannerRepository'
import { weekDates } from '../src/features/planner/domain/planner'
import type { Recipe } from '../src/features/recipes/domain/Recipe'
import { createSupabaseShoppingRepository } from '../src/features/shopping/data/supabaseShoppingRepository'
import type { ShoppingSuggestion } from '../src/features/shopping/domain/shopping'

const session = { token: 'supabase-user:user-1', localRevision: 1, supabaseRevision: 1 }
const unit = { id: 'unit-uuid', name: 'Kilogramo', abbreviation: 'kg', dimension: 'masa' as const, active: true, isDeleted: false }
const category = { id: 'category-uuid', name: 'Almacén', active: true, isDeleted: false }
const ingredient = { id: 'legacy-rice', legacyId: 'legacy-rice', relationalId: 'ingredient-uuid', name: 'Arroz', categoryId: category.id, baseUnitId: unit.id, active: true, isDeleted: false }
const catalog = { categories: [category], units: [unit], ingredients: [ingredient], recipes: [] }

function row(id = 'shopping-item', checked = false, transferredAt: string | null = null) {
  return { id, ingredient_id: 'ingredient-uuid', name_snapshot: 'Arroz', category_snapshot: 'Almacén', quantity: 2, unit_id: 'unit-uuid',
    unit_detail: { abbreviation: 'kg' }, note: '', checked, transferred_at: transferredAt, sources: [{ source: 'manual' }] }
}
function setup(options: { beforeTransfer?: () => unknown; pendingRead?: Promise<unknown>; rejectWrite?: boolean } = {}) {
  const calls: Array<{ name: string; args: Record<string, unknown> }> = []
  let version = 4, transferred = false
  const fake = {
    auth: { getUser: async () => ({ data: { user: { id: 'user-1' } }, error: null }) },
    rpc: async (name: string, args: Record<string, unknown>) => {
      calls.push({ name, args })
      if (name === 'get_my_shopping_list') {
        if (options.pendingRead) return options.pendingRead
        return { data: { list: { id: 'list-uuid', version, status: 'active' }, items: [row('shopping-item', true, transferred ? '2026-11-06T12:00:00Z' : null)], total: 1 }, error: null }
      }
      if (name === 'set_my_shopping_checked') return { data: { id: 'list-uuid', version: ++version, status: 'active' }, error: null }
      if (name === 'put_my_shopping_item' || name === 'remove_my_shopping_item') {
        if (options.rejectWrite) { options.rejectWrite = false; version++; return { data: null, error: { code: '40001', message: 'stale list version' } } }
        return { data: { id: 'list-uuid', version: ++version, status: 'active' }, error: null }
      }
      if (name === 'transfer_my_shopping_to_pantry') {
        if (options.beforeTransfer) { const response = options.beforeTransfer(); transferred = true; return response }
        transferred = true; version += 1
        return { data: { id: 'receipt-uuid', resulting_list_version: version }, error: null }
      }
      return { data: true, error: null }
    },
  }
  const repo = createSupabaseShoppingRepository({ getClient: () => fake as never, captureSession: () => session,
    assertOwner: (_session, id) => assert.equal(id, 'user-1'), assertSession: () => undefined,
    getCatalog: async () => catalog })
  return { repo, calls }
}

test('shopping saves preserve stable item UUID and pass the optimistic list version', async () => {
  const { repo, calls } = setup(), items = await repo.list()
  items[0]!.note = 'largo fino'
  await repo.save(items)
  const write = calls.find((call) => call.name === 'put_my_shopping_item')
  assert.ok(write)
  assert.equal((write.args.p_item as { id: string }).id, 'shopping-item')
  assert.equal(write.args.p_expected_version, 4)
  assert.equal((write.args.p_item as { ingredient_id: string }).ingredient_id, 'ingredient-uuid')
})

test('transfer retries reuse the receipt UUID and never write local pantry stock', async () => {
  let attempts = 0
  const { repo, calls } = setup({ beforeTransfer: () => {
    if (attempts++ === 0) throw new Error('response lost')
    return { data: { id: 'receipt-uuid', resulting_list_version: 5 }, error: null }
  } })
  await repo.list()
  await assert.rejects(repo.transferPurchased(), /response lost/)
  const result = await repo.transferPurchased()
  const transfers = calls.filter((call) => call.name === 'transfer_my_shopping_to_pantry')
  assert.equal(transfers.length, 2)
  assert.equal(transfers[0]?.args.p_idempotency_key, transfers[1]?.args.p_idempotency_key)
  assert.equal(result.transferredCount, 1)
  assert.equal(result.items[0]?.transferredToPantry, true)
  assert.equal(calls.some((call) => call.name.includes('pantry_items') || call.name.includes('put_my_pantry')), false)
})

test('an older shopping read cannot replace a newer list', async () => {
  let resolveOld!: (value: unknown) => void
  const pending = new Promise((resolve) => { resolveOld = resolve })
  const calls: Array<{ name: string; args: Record<string, unknown> }> = []
  let count = 0
  const fake = { auth: { getUser: async () => ({ data: { user: { id: 'user-1' } }, error: null }) }, rpc: async (name: string, args: Record<string, unknown>) => {
    calls.push({ name, args }); if (++count === 1) return pending
    return { data: { list: { id: 'new-list', version: 2, status: 'active' }, items: [], total: 0 }, error: null }
  } }
  const repo = createSupabaseShoppingRepository({ getClient: () => fake as never, captureSession: () => session, assertOwner: () => {}, assertSession: () => {}, getCatalog: async () => catalog })
  const old = repo.list(), rejected = assert.rejects(old, /lista o la sesión cambió/)
  assert.deepEqual(await repo.list(), [])
  resolveOld({ data: { list: { id: 'old-list', version: 1, status: 'active' }, items: [row()], total: 1 }, error: null })
  await rejected
  assert.equal(calls.length, 2)
})

test('a version conflict requires an explicit fresh list before another save', async () => {
  const { repo, calls } = setup({ rejectWrite: true }), items = await repo.list()
  items[0]!.note = 'edición'
  await assert.rejects(repo.save(items), (error: { code?: string }) => error.code === '40001')
  await assert.rejects(repo.save(items), /Recargá las compras/)
  assert.equal(calls.filter((call) => call.name === 'put_my_shopping_item').length, 1)
  const fresh = await repo.list()
  fresh[0]!.note = 'edición actual'
  await repo.save(fresh)
  const write = calls.filter((call) => call.name === 'put_my_shopping_item').at(-1)
  assert.equal(write?.args.p_expected_version, 5)
})

test('week suggestions send every selected date and preserve relational provenance', async () => {
  const calls: Array<{ name: string; args: Record<string, unknown> }> = []
  const fake = { auth: { getUser: async () => ({ data: { user: { id: 'user-1' } }, error: null }) }, rpc: async (name: string, args: Record<string, unknown>) => {
    calls.push({ name, args })
    return { data: [{ ingredient_id: 'ingredient-uuid', name_snapshot: 'Arroz', category_snapshot: 'Almacén', quantity: 3, unit_id: 'unit-uuid',
      sources: [{ source: 'plan', plan_id: 'plan-uuid' }] }], error: null }
  } }
  const repo = createSupabaseShoppingRepository({ getClient: () => fake as never, captureSession: () => session, assertOwner: () => {}, assertSession: () => {}, getCatalog: async () => catalog })
  const dates = ['2026-11-02', '2026-11-03', '2026-11-02']
  const suggestions = await repo.suggestionsFromWeek(dates)
  assert.deepEqual(calls[0]?.args.p_dates, ['2026-11-02', '2026-11-03'])
  assert.equal(suggestions[0]?.unit, 'kg')
  assert.equal(suggestions[0]?.ingredientRef, 'ingredient-uuid')
  assert.deepEqual(suggestions[0]?.sourceLinks, [{ source: 'plan', plan_id: 'plan-uuid' }])
})

test('adding a recipe and generating weekly purchases creates a pending item for a previously transferred ingredient', async () => {
  const dates = weekDates(new Date(2026, 10, 26, 12))
  const recipe: Recipe = { id: 'rice-recipe', relationalId: 'recipe-uuid', name: 'Arroz', description: '', category: 'Almuerzo', minutes: 20, portions: 2, difficulty: 'Fácil', ingredients: [], steps: [], symbol: '🍚', color: 'green' }
  const transferred = row('transferred-rice', true, '2026-11-26T12:00:00Z')
  const items = [transferred]
  let plan: { id: string; week_start: string; version: number } | null = null
  let slots: Array<Record<string, unknown>> = []
  let version = 1
  const fake = {
    auth: { getUser: async () => ({ data: { user: { id: 'user-1' } }, error: null }) },
    rpc: async (name: string, args: Record<string, unknown>) => {
      const list = { id: 'list-uuid', version, status: 'active' }
      if (name === 'get_my_shopping_list') return { data: { list, items, total: items.length }, error: null }
      if (name === 'get_my_meal_plan') return { data: { plan, slots }, error: null }
      if (name === 'save_my_meal_plan') {
        plan = { id: 'plan-uuid', week_start: dates[0], version: 1 }
        slots = (args.p_slots as Array<Record<string, unknown>>).map((slot) => ({ ...slot, available: true }))
        return { data: plan, error: null }
      }
      if (name === 'suggest_my_shopping_for_dates') {
        assert.deepEqual(args.p_dates, dates)
        assert.equal(slots[0]?.recipe_id, recipe.relationalId)
        assert.equal(slots[0]?.portions, 3)
        return { data: [{ ...row(), quantity: 3, sources: [{ source: 'plan', plan_id: plan?.id }] }], error: null }
      }
      assert.equal(name, 'put_my_shopping_item')
      const item = args.p_item as Omit<ReturnType<typeof row>, 'transferred_at' | 'unit_detail'>
      if (item.id === transferred.id) return { data: null, error: new Error('No se puede modificar un artículo ya transferido.') }
      const index = items.findIndex((entry) => entry.id === item.id)
      const saved = { ...item, transferred_at: null, unit_detail: { abbreviation: 'kg' } }
      if (index === -1) items.push(saved)
      else items[index] = saved
      return { data: { ...list, version: ++version }, error: null }
    },
  }
  const repo = createSupabaseShoppingRepository({ getClient: () => fake as never, captureSession: () => session,
    assertOwner: () => {}, assertSession: () => {}, getCatalog: async () => catalog })
  const planner = createSupabasePlannerRepository({ getClient: () => fake as never, capture: () => session,
    assertOwner: () => {}, assertCurrent: () => {}, knownRecipes: async () => [recipe],
    suggestions: (selectedDates) => repo.suggestionsFromWeek(selectedDates),
    appendSuggestions: (suggestions) => repo.append(suggestions as ShoppingSuggestion[]) })
  await planner.list(dates[0])
  await planner.assign(dates[3], 'Almuerzo', recipe.id, 3)
  await planner.generateShopping(dates)
  const first = await repo.list()
  const pending = first.find((item) => !item.transferredToPantry)
  assert.equal(first.length, 2)
  assert.deepEqual(items[0], transferred)
  assert.equal(pending?.quantity, 3)
  assert.equal(pending?.checked, false)
  assert.deepEqual(pending?.sourceLinks, [{ source: 'plan', plan_id: 'plan-uuid' }])
  await planner.generateShopping(dates)
  assert.deepEqual(await repo.list(), first)
  assert.equal(version, 2)
})

test('a session change while the catalog loads rejects the pending shopping read', async () => {
  let revision = 1, resolveCatalog!: (value: typeof catalog) => void
  const pendingCatalog = new Promise<typeof catalog>((resolve) => { resolveCatalog = resolve })
  const currentSession = () => ({ ...session, localRevision: revision })
  const fake = { auth: { getUser: async () => ({ data: { user: { id: 'user-1' } }, error: null }) }, rpc: async () => ({ data: { list: null, items: [], total: 0 }, error: null }) }
  const repo = createSupabaseShoppingRepository({ getClient: () => fake as never, captureSession: currentSession,
    assertOwner: (captured) => { assert.equal(captured.localRevision, revision, 'session changed during catalog read') },
    assertSession: (captured) => { assert.equal(captured.localRevision, revision, 'session changed during catalog read') }, getCatalog: () => pendingCatalog })
  const read = repo.list()
  await new Promise((resolve) => setImmediate(resolve))
  revision++
  resolveCatalog(catalog)
  await assert.rejects(read, /session changed during catalog read/)
})
