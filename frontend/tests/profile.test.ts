import assert from 'node:assert/strict'
import test from 'node:test'
import { calculateAge, calculateEnergyEstimate, estimateForProfile, profileIsComplete, recipeGoalPercentageRange } from '../src/features/profile/domain/profile'
import { readLocalProfile, saveLocalProfile } from '../src/features/profile/data/localProfileStore'

test('calculates age from the birth date without adding a year before the birthday', () => {
  const today = new Date(2026, 8, 23)

  assert.equal(calculateAge('2000-09-24', today), 25)
  assert.equal(calculateAge('2000-09-23', today), 26)
  assert.equal(calculateAge('2026-02-30', today), undefined)
  assert.equal(calculateAge('2027-01-01', today), undefined)
  assert.equal(calculateAge('2000-02-29', new Date(2026, 1, 28)), 25)
  assert.equal(calculateAge('fecha vieja', today), undefined)
})

test('applies distinct goal adjustments to the same activity-adjusted daily estimate', () => {
  const base = { weightKg: 70, heightCm: 175, age: 30, metabolicSex: 'male' as const, activityLevel: 'sedentary' as const }
  const maintain = calculateEnergyEstimate({ ...base, goal: 'maintain' })
  assert.equal(maintain.basalCalories, 1649)
  assert.equal(maintain.dailyCalories, 1979)
  assert.deepEqual(maintain.goalRange, { minimum: 1879, maximum: 2079 })
  assert.deepEqual(calculateEnergyEstimate({ ...base, goal: 'lose' }).goalRange, { minimum: 1379, maximum: 1579 })
  assert.deepEqual(calculateEnergyEstimate({ ...base, goal: 'gain' }).goalRange, { minimum: 2229, maximum: 2379 })
  assert.deepEqual(calculateEnergyEstimate({ ...base, goal: 'gain-muscle' }).goalRange, { minimum: 2179, maximum: 2279 })
  assert.equal(calculateEnergyEstimate({ ...base, activityLevel: 'active', goal: 'maintain' }).dailyCalories, 2844)
})

test('updates the estimate with edited profile fields and compares one portion to the goal range', () => {
  const profile = { name: 'Carla', birthDate: '1996-09-24', weightKg: 70, heightCm: 175, metabolicSex: 'female' as const, activityLevel: 'moderate' as const, goal: 'maintain' as const }
  const today = new Date(2026, 8, 25)
  const first = estimateForProfile(profile, today)!
  const muscle = estimateForProfile({ ...profile, goal: 'gain-muscle' }, today)!
  const moreActive = estimateForProfile({ ...profile, activityLevel: 'active' }, today)!
  assert.notDeepEqual(first.goalRange, muscle.goalRange)
  assert.ok(moreActive.dailyCalories > first.dailyCalories)
  assert.deepEqual(recipeGoalPercentageRange(first.goalRange.minimum, first), {
    minimum: Math.round(first.goalRange.minimum / first.goalRange.maximum * 100), maximum: 100,
  })
  assert.equal(recipeGoalPercentageRange(-1, first), undefined)
  assert.equal(estimateForProfile({ ...profile, birthDate: '2012-01-01' }, today), undefined)
})

test('calculates an informational daily energy estimate from Mifflin-St Jeor', () => {
  const estimate = calculateEnergyEstimate({
    weightKg: 70,
    heightCm: 175,
    age: 30,
    metabolicSex: 'female',
    activityLevel: 'moderate',
    goal: 'maintain',
  })

  assert.equal(estimate.basalCalories, 1483)
  assert.equal(estimate.dailyCalories, 2298)
  assert.deepEqual(estimate.goalRange, { minimum: 2198, maximum: 2398 })
})

test('requires the essential onboarding fields before considering a profile complete', () => {
  assert.equal(profileIsComplete({}), false)
  assert.equal(profileIsComplete({
    name: 'Carla',
    birthDate: '2000-09-23',
    weightKg: 64,
    heightCm: 168,
    metabolicSex: 'female',
    activityLevel: 'light',
    goal: 'maintain',
  }), true)
  assert.equal(profileIsComplete({ name: 'Carla', birthDate: '2000-01-01', weightKg: NaN, heightCm: 168, metabolicSex: 'female', activityLevel: 'light', goal: 'gain-muscle' }), false)
})

test('profile storage survives valid data and ignores malformed older values', () => {
  const entries = new Map<string, string>()
  const storage = { getItem: (key: string) => entries.get(key) ?? null, setItem: (key: string, value: string) => { entries.set(key, value) } }
  saveLocalProfile({ name: 'Carla', goal: 'maintain' }, storage)
  assert.deepEqual(readLocalProfile(storage), { name: 'Carla', email: undefined, birthDate: undefined, weightKg: undefined, heightCm: undefined, metabolicSex: undefined, activityLevel: undefined, goal: 'maintain', preferences: undefined })
  entries.set('cocinapp.profile.v1', '{bad')
  assert.deepEqual(readLocalProfile(storage), {})
  entries.set('cocinapp.profile.v1', JSON.stringify({ name: 'Carla', goal: 'unknown', weightKg: '70' }))
  assert.equal(readLocalProfile(storage).goal, undefined)
  assert.equal(readLocalProfile(storage).weightKg, undefined)
  entries.set('cocinapp.profile.v1', JSON.stringify({ name: 'Carla', goal: 'gain', activityLevel: 'light' }))
  assert.equal(readLocalProfile(storage).goal, 'gain')
  saveLocalProfile({ name: 'Carla', goal: 'gain-muscle' }, storage)
  assert.equal(readLocalProfile(storage).goal, 'gain-muscle')
})
