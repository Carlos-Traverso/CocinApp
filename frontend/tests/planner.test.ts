import assert from 'node:assert/strict'
import test from 'node:test'
import { meals, weekDates, setPlannedMeal } from '../src/features/planner/domain/planner'
import { readMealPlan, writeMealPlan } from '../src/features/planner/data/localMealPlanStore'

test('week starts on Monday and crosses month boundaries', () => {
  assert.deepEqual(weekDates(new Date(2026, 8, 23)), ['2026-09-21', '2026-09-22', '2026-09-23', '2026-09-24', '2026-09-25', '2026-09-26', '2026-09-27'])
  assert.equal(weekDates(new Date(2026, 9, 1))[0], '2026-09-28')
})

test('assigning the same day and meal replaces the recipe; empty choice clears it', () => {
  const first = setPlannedMeal([], '2026-09-23', 'Almuerzo', 'quinoa-bowl')
  const second = setPlannedMeal(first, '2026-09-23', 'Almuerzo', 'chickpea-salad')
  assert.deepEqual(second, [{ date: '2026-09-23', meal: 'Almuerzo', recipeId: 'chickpea-salad' }])
  assert.deepEqual(setPlannedMeal(second, '2026-09-23', 'Almuerzo', ''), [])
  assert.deepEqual(meals, ['Desayuno', 'Almuerzo', 'Merienda', 'Cena'])
  assert.equal(setPlannedMeal(first, '2026-09-23', 'Desayuno', 'quinoa-bowl').length, 2)
})

test('plan storage keeps valid known recipes and ignores invalid entries', () => {
  const entries = new Map<string, string>()
  const storage = { getItem: (key: string) => entries.get(key) ?? null, setItem: (key: string, value: string) => { entries.set(key, value) } }
  const plan = [{ date: '2026-09-23', meal: 'Cena' as const, recipeId: 'pumpkin-pasta' }]
  writeMealPlan(plan, storage)
  assert.deepEqual(readMealPlan(storage), plan)
  entries.set('cocinapp.planner.v1', JSON.stringify([...plan, { date: '2026-09-31', meal: 'Cena', recipeId: 'pumpkin-pasta' }, { date: '2026-09-24', meal: 'Cena', recipeId: 'missing' }]))
  assert.deepEqual(readMealPlan(storage), plan)
})

test('older lunch and dinner records remain alongside four turns and independent weeks', () => {
  const entries = new Map<string, string>()
  const storage = { getItem: (key: string) => entries.get(key) ?? null, setItem: (key: string, value: string) => { entries.set(key, value) } }
  const legacy = [{ date: '2026-09-23', meal: 'Almuerzo', recipeId: 'quinoa-bowl' }, { date: '2026-09-23', meal: 'Cena', recipeId: 'pumpkin-pasta' }]
  entries.set('cocinapp.planner.v1', JSON.stringify(legacy))
  const migrated = readMealPlan(storage)
  assert.deepEqual(migrated, legacy)
  const expanded = setPlannedMeal(setPlannedMeal(migrated, '2026-09-23', 'Desayuno', 'quinoa-bowl'), '2026-09-30', 'Merienda', 'chickpea-salad')
  writeMealPlan(expanded, storage)
  assert.equal(readMealPlan(storage).length, 4)
  assert.equal(readMealPlan(storage).filter((entry) => weekDates(new Date(2026, 8, 23)).includes(entry.date)).length, 3)
})
