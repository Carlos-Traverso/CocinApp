import assert from 'node:assert/strict'
import test from 'node:test'
import { createRelationalDashboardRepository } from '../src/features/dashboard/data/DashboardRepository'

const snapshot = { id: 'old', name: 'Receta guardada', description: '', category: 'Cena', minutes: 20, portions: 2, difficulty: 'Fácil', ingredients: [], steps: ['Mezclar'], symbol: '🍲', color: 'green' }
const planRecipe = { id: 'old', title: 'Receta planificada', description: '', total_minutes: 20, portions: 2, meal_shifts: ['dinner'], ingredients: [], steps: [] }
function localDay() {
  const day = new Date()
  return `${day.getFullYear()}-${String(day.getMonth() + 1).padStart(2, '0')}-${String(day.getDate()).padStart(2, '0')}`
}
function summary(asOf = localDay()) {
  return {
    as_of: asOf, profile: { profile: { display_name: 'Carla', weight_kg: 60 }, preference_keys: ['vegan'] },
    pantry: { total: 13, low: 4, empty: 2, soon: 3, expired: 1 }, favorites: { total: 6, available: 5 },
    shopping: { active_list_id: 'list', pending_items: 7, checked_items: 2, transferred_items: 1 },
    today_plan: { plan: { version: 2 }, slots: [{ meal_date: asOf, meal_shift: 'dinner', recipe_id: 'recipe-1', portions: 3, position: 1, available: true, recipe: planRecipe }] },
    recent_preparations: [{ id: 'event-1', recipe_id: 'inactive-recipe', cooked_at: '2026-11-06T20:00:00Z', portions: 2, recipe_snapshot: snapshot }],
  }
}
function setup(rpc: (name: string, args: Record<string, unknown>) => Promise<{ data: unknown; error: null }>, assertSession = () => {}) {
  const calls: string[] = []
  const fake = { auth: { getUser: async () => ({ data: { user: { id: 'user-1' } }, error: null }) }, rpc: async (name: string, args: Record<string, unknown>) => { calls.push(name); return rpc(name, args) } }
  const recipeRepo = { list: async () => [], listKnown: async () => [], getById: async () => undefined, match: async () => [], getReadiness: async () => undefined, getDietaryPreferences: async () => [], getProfile: async () => ({}) }
  const pantryRepo = { list: async () => [], getCatalog: async () => ({ categories: [], units: [], ingredients: [] }) }
  const favorites = { listIds: async () => ['favorite-1'] }
  const repository = createRelationalDashboardRepository({ getClient: () => fake as never, captureSession: () => ({ token: 'supabase-user:user-1', localRevision: 1, supabaseRevision: 1 }), assertSession, assertOwner: (_s, id) => assert.equal(id, 'user-1'), recipes: recipeRepo as never, pantry: pantryRepo as never, favorites: favorites as never })
  return { repository, calls }
}

test('dashboard maps exact summary counts, local date, plan and inactive history snapshots without writes', async () => {
  let args: Record<string, unknown> = {}
  const { repository, calls } = setup(async (name, input) => { assert.equal(name, 'get_my_dashboard_summary'); args = input; return { data: summary(), error: null } })
  const result = await repository.loadHome()
  assert.match(String(args.p_day), /^\d{4}-\d{2}-\d{2}$/)
  assert.equal(args.p_recent_limit, 4)
  assert.equal(args.p_day, localDay())
  assert.deepEqual(result.summary, { asOf: args.p_day, pantry: { total: 13, low: 4, empty: 2, soon: 3, expired: 1 }, favorites: { total: 6, available: 5 }, shopping: { pending: 7, checked: 2, transferred: 1 }, todayPlanCount: 1 })
  assert.deepEqual(result.plannedMeals.map(({ date, meal, portions }) => ({ date, meal, portions })), [{ date: args.p_day, meal: 'Cena', portions: 3 }])
  assert.equal(result.knownRecipes[0]?.name, 'Receta planificada')
  assert.equal(result.history[0]?.recipeSnapshot?.name, 'Receta guardada')
  assert.ok(result.knownRecipes.some((recipe) => recipe.name === 'Receta guardada'))
  assert.deepEqual(result.favoriteIds, ['favorite-1'])
  assert.deepEqual(calls, ['get_my_dashboard_summary'])
})

test('malformed summary fails closed', async () => {
  const { repository } = setup(async () => ({ data: { ...summary(), pantry: { total: -1 } }, error: null }))
  await assert.rejects(repository.loadHome(), /conteo inválido/)
})

test('summary for a different day is rejected', async () => {
  const { repository } = setup(async () => ({ data: summary('2000-01-01'), error: null }))
  await assert.rejects(repository.loadHome(), /corresponde a otro día/)
})

test('session change after the summary read rejects before publishing or writes', async () => {
  let current = true
  let resolve!: (result: { data: unknown; error: null }) => void
  const { repository, calls } = setup(() => new Promise((done) => { resolve = done }), () => { if (!current) throw new Error('session changed') })
  const loading = repository.loadHome()
  await new Promise((done) => setTimeout(done, 0))
  current = false
  resolve({ data: summary(), error: null })
  await assert.rejects(loading, /session changed/)
  assert.deepEqual(calls, ['get_my_dashboard_summary'])
})

test('latest overlapping dashboard read wins', async () => {
  let resolveFirst!: (value: { data: unknown; error: null }) => void
  let count = 0
  const { repository, calls } = setup(async () => {
    count += 1
    if (count === 1) return await new Promise((resolve) => { resolveFirst = resolve })
    return { data: summary(), error: null }
  })
  const first = repository.loadHome()
  const latest = repository.loadHome()
  const result = await latest
  resolveFirst({ data: summary(), error: null })
  await assert.rejects(first, /desactualizada/)
  assert.equal(result.summary?.pantry.total, 13)
  assert.deepEqual(calls, ['get_my_dashboard_summary', 'get_my_dashboard_summary'])
})
