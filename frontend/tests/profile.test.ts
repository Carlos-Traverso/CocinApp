import assert from 'node:assert/strict'
import test from 'node:test'
import { calculateAge, calculateEnergyEstimate, profileIsComplete } from '../src/features/profile/domain/profile'

test('calculates age from the birth date without adding a year before the birthday', () => {
  const today = new Date(2026, 8, 23)

  assert.equal(calculateAge('2000-09-24', today), 25)
  assert.equal(calculateAge('2000-09-23', today), 26)
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
})
