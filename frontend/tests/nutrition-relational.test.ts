import assert from 'node:assert/strict'
import test from 'node:test'
import { estimateForProfile } from '../src/features/profile/domain/profile'
import { createNutritionRepository, mapNutritionConfig, type NutritionConfigInput } from '../src/features/profile/data/NutritionRepository'
import { startSupabaseUserSession } from '../src/features/auth/data/localAuthStore'

const storage = new Map<string, string>()
Object.defineProperty(globalThis, 'localStorage', { configurable: true, value: {
  getItem: (key: string) => storage.get(key) ?? null,
  setItem: (key: string, value: string) => { storage.set(key, value) },
  removeItem: (key: string) => { storage.delete(key) },
  clear: () => storage.clear(),
} })
Object.defineProperty(globalThis, 'window', { configurable: true, value: { dispatchEvent: () => {}, addEventListener: () => {}, removeEventListener: () => {} } })

const configRow = {
  config_version: 3,
  activity_factors: { sedentary: 1, light: 1.1, moderate: 1.2, active: 1.3, 'very-active': 1.4 },
  goal_adjustments: { lose: { minimum: -10, maximum: -5 }, maintain: { minimum: 0, maximum: 0 }, gain: { minimum: 5, maximum: 10 }, 'gain-muscle': { minimum: 2, maximum: 4 } },
  source_note: 'Fuente documentada', effective_at: '2026-01-01T00:00:00Z',
}

test('maps current config row and uses its factors and goal adjustments', () => {
  const config = mapNutritionConfig(configRow)!
  assert.equal(config.configVersion, 3)
  const estimate = estimateForProfile({ name: 'A', birthDate: '1990-01-01', weightKg: 70, heightCm: 175, metabolicSex: 'male', activityLevel: 'sedentary', goal: 'maintain', nutritionConfig: config }, new Date('2026-01-02'))!
  assert.equal(estimate.dailyCalories, estimate.basalCalories)
  assert.deepEqual(estimate.goalRange, { minimum: estimate.dailyCalories, maximum: estimate.dailyCalories })
})

test('absent current configuration maps to null and disables the estimate without affecting the profile', () => {
  assert.equal(mapNutritionConfig(null), null)
  assert.equal(mapNutritionConfig([]), null)
  assert.equal(mapNutritionConfig({ config_version: null, activity_factors: null, goal_adjustments: null, source_note: null, effective_at: null }), null)
  assert.throws(() => mapNutritionConfig({ config_version: null, activity_factors: null, goal_adjustments: null, source_note: null, effective_at: '2026-01-01T00:00:00Z' }), /configuración nutricional inválida/)
  assert.throws(() => mapNutritionConfig([configRow, configRow]), /configuración nutricional inválida/)
  const profile = { name: 'A', birthDate: '1990-01-01', weightKg: 70, heightCm: 175, metabolicSex: 'male' as const, activityLevel: 'sedentary' as const, goal: 'maintain' as const }
  assert.equal(estimateForProfile({ ...profile, nutritionConfig: null }, new Date('2026-01-02')), undefined)
  assert.ok(estimateForProfile(profile, new Date('2026-01-02')))
})

test('preserves the config request across retry and uses expected latest version', async () => {
  startSupabaseUserSession('nutrition-admin', 'admin@example.com', 'Admin')
  const request: NutritionConfigInput = { activityFactors: configRow.activity_factors, goalAdjustments: configRow.goal_adjustments, sourceNote: 'Fuente documentada', effectiveAt: '2026-01-01T00:00:00Z' }
  const calls: { request: NutritionConfigInput; expected: number }[] = []
  let attempt = 0
  const repository = createNutritionRepository({
    configured: true, relationalProfiles: true, relationalAdmin: true,
    getCurrent: async () => configRow,
    list: async () => [configRow],
    publish: async (input, expected) => {
      calls.push({ request: input, expected })
      if (attempt++ === 0) throw new Error('network failure')
      return { ...configRow, config_version: expected + 1 }
    },
  })
  await assert.rejects(repository.publish(request, 3), /network failure/)
  const saved = await repository.publish(request, 3)
  assert.equal(saved.configVersion, 4)
  assert.deepEqual(calls, [{ request, expected: 3 }, { request, expected: 3 }])
})

test('reports a version race instead of retrying with a newer version implicitly', async () => {
  startSupabaseUserSession('nutrition-admin-race', 'race@example.com', 'Admin')
  const request: NutritionConfigInput = { activityFactors: configRow.activity_factors, goalAdjustments: configRow.goal_adjustments, sourceNote: 'Fuente documentada', effectiveAt: '2026-01-01T00:00:00Z' }
  const repository = createNutritionRepository({
    configured: true, relationalProfiles: true, relationalAdmin: true,
    getCurrent: async () => null, list: async () => [configRow],
    publish: async () => { throw Object.assign(new Error('La configuración cambió; recargá antes de publicar.'), { code: '40001' }) },
  })
  await assert.rejects(repository.publish(request, 3), /configuración cambió/)
})
