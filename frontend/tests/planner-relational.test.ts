import assert from 'node:assert/strict'
import test from 'node:test'
import { createSupabasePlannerRepository } from '../src/features/planner/data/SupabasePlannerRepository'
import type { Recipe } from '../src/features/recipes/domain/Recipe'
import type { PersonalDataSession } from '../src/shared/data/personalDataSession'

const recipe: Recipe = { id: 'legacy-r', relationalId: '00000000-0000-4000-8000-000000000001', name: 'Arroz', description: '', category: 'Almuerzo', minutes: 1, portions: 2, difficulty: 'Fácil', ingredients: [], steps: [], symbol: '🍚', color: 'green' }
const baseSession: PersonalDataSession = { token: 'supabase-user:user-1', localRevision: 1, supabaseRevision: 1 }
function harness(options: { slots?: Record<string, unknown>[]; conflict?: boolean; inactive?: boolean } = {}) {
  let current = baseSession
  let version = options.slots ? 1 : 0
  let slots = options.slots ?? []
  const writes: Array<{ args: Record<string, unknown> }> = []
  const deps = {
    getClient: () => ({ auth: { getUser: async () => ({ data: { user: { id: 'user-1' } }, error: null }) }, rpc: async (name: string, args: Record<string, unknown>) => {
      if (name === 'get_my_meal_plan') return { data: { plan: version ? { id: 'plan-1', week_start: '2026-10-05', version } : null, slots: slots.map((slot) => ({ available: true, recipe: {}, ...slot, ...(options.inactive && slot.recipe_id === 'inactive-id' ? { available: false, recipe: null } : {}) })) }, error: null }
      writes.push({ args })
      if (options.conflict) return { data: null, error: Object.assign(new Error('conflict'), { code: '40001' }) }
      version += 1; slots = (args.p_slots as Record<string, unknown>[]).map((slot, index) => ({ ...slot, id: `slot-${index}`, position: slot.position ?? 1, available: true }))
      return { data: { id: 'plan-1', week_start: args.p_week_start, version }, error: null }
    } }) as never,
    capture: () => current,
    assertCurrent: (session: PersonalDataSession) => { if (session !== current) throw new Error('session changed') },
    assertOwner: (session: PersonalDataSession, userId: string) => { if (session !== current || userId !== 'user-1') throw new Error('owner changed') },
    knownRecipes: async () => [recipe],
    suggestions: async () => [],
  }
  return { repository: createSupabasePlannerRepository(deps), writes, changeSession: () => { current = { ...baseSession, localRevision: 2 } } }
}

test('maps relational recipe IDs, versions full-week writes, and reloads the authoritative snapshot', async () => {
  const h = harness()
  const loaded = await h.repository.list('2026-10-05')
  assert.deepEqual(loaded, [])
  const saved = await h.repository.assign('2026-10-06', 'Almuerzo', recipe.id, 4)
  assert.equal(h.writes[0].args.p_expected_version, 0)
  assert.deepEqual(h.writes[0].args.p_slots, [{ meal_date: '2026-10-06', meal_shift: 'lunch', recipe_id: recipe.relationalId, portions: 4, position: 1 }])
  assert.equal(saved[0].recipeId, recipe.id)
})

test('empty week is represented by null plan and empty slots, then can be cleared transactionally', async () => {
  const h = harness({ slots: [{ id: 'slot-a', meal_date: '2026-10-06', meal_shift: 'lunch', recipe_id: recipe.relationalId, portions: 2, position: 1 }] })
  assert.equal((await h.repository.list('2026-10-05')).length, 1)
  assert.deepEqual(await h.repository.assign('2026-10-06', 'Almuerzo', '', 2), [])
  assert.deepEqual(h.writes[0].args.p_slots, [])
})

test('preserves inactive records and refuses a different slot edit instead of deleting them', async () => {
  const h = harness({ inactive: true, slots: [{ id: 'slot-a', meal_date: '2026-10-06', meal_shift: 'lunch', recipe_id: 'inactive-id', portions: 2, position: 1 }] })
  const before = await h.repository.list('2026-10-05')
  assert.equal(before[0].recipeId, 'inactive-id')
  await assert.rejects(h.repository.assign('2026-10-07', 'Cena', recipe.id, 2), /inactivas/)
  assert.equal(h.writes.length, 0)
})

test('blocks edits when a meal has hidden positions, preserving every submitted slot', async () => {
  const h = harness({ slots: [
    { id: 'slot-a', meal_date: '2026-10-06', meal_shift: 'lunch', recipe_id: recipe.relationalId, portions: 2, position: 1 },
    { id: 'slot-b', meal_date: '2026-10-06', meal_shift: 'lunch', recipe_id: recipe.relationalId, portions: 3, position: 2 },
  ] })
  const current = await h.repository.list('2026-10-05')
  assert.deepEqual(current.map((slot) => slot.position), [1, 2])
  await assert.rejects(h.repository.assign('2026-10-06', 'Almuerzo', '', 2), /varias posiciones/)
  assert.equal(h.writes.length, 0)
})

test('rejects multiweek writes before reaching the RPC', async () => {
  const h = harness()
  await assert.rejects(h.repository.save([
    { date: '2026-10-05', meal: 'Almuerzo', recipeId: recipe.id, portions: 2 },
    { date: '2026-10-12', meal: 'Almuerzo', recipeId: recipe.id, portions: 2 },
  ]), /varias semanas/)
  assert.equal(h.writes.length, 0)
})

test('version conflicts invalidate loaded state and require an explicit reload', async () => {
  const h = harness({ conflict: true })
  await h.repository.list('2026-10-05')
  await assert.rejects(h.repository.assign('2026-10-06', 'Almuerzo', recipe.id, 2), /conflict/)
  await assert.rejects(h.repository.assign('2026-10-06', 'Almuerzo', recipe.id, 2), /Recargala/)
})

test('session changes invalidate an operation captured before awaiting the repository', async () => {
  const h = harness()
  await h.repository.list('2026-10-05')
  h.changeSession()
  await assert.rejects(h.repository.assign('2026-10-06', 'Almuerzo', recipe.id, 2), /Recargala|session changed/)
  assert.equal(h.writes.length, 0)
})

test('an older out of order load cannot replace the newest week snapshot', async () => {
  let releaseFirst: ((value: unknown) => void) | undefined
  let reads = 0
  const deps = {
    getClient: () => ({ auth: { getUser: async () => ({ data: { user: { id: 'user-1' } }, error: null }) }, rpc: async (name: string, args: Record<string, unknown>) => {
      if (name === 'save_my_meal_plan') return { data: { id: 'plan', week_start: args.p_week_start, version: 1 }, error: null }
      reads += 1
      if (reads === 1) return await new Promise((resolve) => { releaseFirst = resolve })
      return { data: { plan: null, slots: [] }, error: null }
    } }) as never,
    capture: () => baseSession,
    assertCurrent: () => {}, assertOwner: () => {}, knownRecipes: async () => [recipe], suggestions: async () => [], appendSuggestions: async () => [],
  }
  const repository = createSupabasePlannerRepository(deps)
  const stale = repository.list('2026-10-05')
  assert.deepEqual(await repository.list('2026-10-12'), [])
  releaseFirst?.({ data: { plan: null, slots: [] }, error: null })
  await assert.rejects(stale, /cambió mientras se cargaba/)
  await assert.rejects(repository.assign('2026-10-05', 'Almuerzo', recipe.id, 2), /no está cargada/)
})
