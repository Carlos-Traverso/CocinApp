import assert from 'node:assert/strict'
import test from 'node:test'
import { sampleRecipes } from '../src/mocks/recipes'
import { advanceStep, completeStep, cookingCompletionPath, createSession, moveStep, recordPreparation, remainingTimerMs, scaleIngredients, deductIngredients, getStepGuidance, remainingRecipeMinutes, startStepTimer, pauseStepTimer, resetStepTimer, type CookingSession } from '../src/features/cooking/domain/cooking'
import { clearCookingSession, finalizeCookingSession, readCookingSession, readHistory, saveCookingSession, writeHistory } from '../src/features/cooking/data/localCookingStore'
import { readPantryItems, writePantryItems } from '../src/features/pantry/data/localPantryStore'
import type { PantryItem } from '../src/features/pantry/domain/pantry'

const recipe = sampleRecipes[0]
const now = new Date('2026-09-23T15:00:00.000Z')

test('next completes the current step, previous preserves progress and completion is idempotent', () => {
  const start = createSession(recipe, now)
  assert.equal(start.stepIndex, 0)
  assert.deepEqual(start.completed, [])
  assert.equal(moveStep(start, -1, recipe.steps.length).stepIndex, 0)
  assert.equal(moveStep(start, 1, recipe.steps.length).stepIndex, 1)
  assert.deepEqual(completeStep(start, 0, recipe.steps.length).completed, [0])
  assert.deepEqual(completeStep(completeStep(start, 0, recipe.steps.length), 0, recipe.steps.length).completed, [0])
  const advanced = advanceStep(start, recipe.steps.length)
  assert.equal(advanced.stepIndex, 1)
  assert.deepEqual(advanced.completed, [0])
  assert.deepEqual(moveStep(advanced, -1, recipe.steps.length).completed, [0])
  assert.deepEqual(advanceStep(moveStep(advanced, -1, recipe.steps.length), recipe.steps.length).completed, [0])
  assert.equal(moveStep(start, 99, recipe.steps.length).stepIndex, recipe.steps.length - 1)
})

test('history records each preparation with date and portions', () => {
  const start = { ...createSession(recipe, now), portions: 4 }
  const events = recordPreparation([], start, now)
  assert.equal(events.length, 1)
  assert.deepEqual(events[0], { id: events[0].id, recipeId: recipe.id, cookedAt: now.toISOString(), portions: 4, sessionStartedAt: start.startedAt })
  assert.deepEqual(recordPreparation(events, start, now), events)
  assert.equal(recordPreparation(events, { ...start, startedAt: '2026-09-24T14:00:00.000Z' }, new Date('2026-09-24T15:00:00.000Z')).length, 2)
})

test('timer remaining time uses the deadline after a background gap and persists with progress', () => {
  const values = new Map<string, string>()
  const storage = { getItem: (key: string) => values.get(key) ?? null, setItem: (key: string, value: string) => { values.set(key, value) } }
  const session = { ...createSession(recipe, now), timer: { stepIndex: 0, remainingMs: 60_000, deadlineAt: 100_000 } }
  assert.equal(remainingTimerMs(session.timer, 110_000), 0)
  assert.equal(remainingTimerMs(session.timer, 75_000), 25_000)
  saveCookingSession(session, storage)
  assert.deepEqual(readCookingSession(recipe.id, storage), session)
  assert.equal(advanceStep(session, recipe.steps.length).timer, undefined)
})

test('step guidance scales its ingredients and estimates remaining cooking time', () => {
  const guidedRecipe = {
    ...recipe,
    portions: 2,
    steps: ['Preparar', 'Cocinar', 'Servir'],
    stepMeta: [
      { durationMinutes: 5, stepIngredients: [{ name: 'Quinoa', quantity: 100, unit: 'g' }], utensils: ['Colador'], tip: 'Enjuagá bien.' },
      { minutes: 12, temperature: 'Fuego medio', warning: 'No dejes que se seque.' },
      {},
    ],
  }
  const guidance = getStepGuidance(guidedRecipe, 0, 4)
  assert.deepEqual(guidance.stepIngredients, [{ name: 'Quinoa', quantity: 200, unit: 'g' }])
  assert.deepEqual(guidance.utensils, ['Colador'])
  assert.equal(guidance.durationMinutes, 5)
  assert.equal(guidance.nextStepPreview, 'Cocinar')
  assert.equal(remainingRecipeMinutes(guidedRecipe, 0), 17)
  assert.equal(remainingRecipeMinutes(guidedRecipe, 1, 90_000), 2)
})

test('timer can start, pause, resume, finish and reset without blocking progress', () => {
  const session = createSession(recipe, now)
  const started = startStepTimer(session, 60_000, 100_000)
  assert.equal(remainingTimerMs(started.timer!, 125_000), 35_000)
  const paused = pauseStepTimer(started, 125_000)
  assert.deepEqual(paused.timer, { stepIndex: 0, remainingMs: 35_000 })
  const resumed = startStepTimer(paused, 60_000, 200_000)
  assert.equal(resumed.timer?.deadlineAt, 235_000)
  assert.equal(remainingTimerMs(resumed.timer!, 240_000), 0)
  assert.equal(advanceStep(resumed, recipe.steps.length).stepIndex, 1)
  assert.equal(resetStepTimer(resumed).timer, undefined)
})

test('ingredient scaling and pantry deduction skip expired stock and never go negative', () => {
  assert.equal(scaleIngredients(recipe, 4)[0].quantity, recipe.ingredients[0].quantity * 2)
  const pantry: PantryItem[] = [
    { id: 'old', name: 'Quinoa', category: 'Granos y legumbres', quantity: 200, unit: 'g', minimum: 0, expiry: '2026-09-22' },
    { id: 'fresh', name: 'Quinoa', category: 'Granos y legumbres', quantity: 100, unit: 'g', minimum: 0, expiry: '' },
  ]
  const updated = deductIngredients(pantry, recipe, 2, new Date(2026, 8, 23))
  assert.equal(updated[0].quantity, 200)
  assert.equal(updated[1].quantity, 0)
  assert.equal(pantry[1].quantity, 100)
})

test('storage persists valid progress and history, and clears one session', () => {
  const values = new Map<string, string>()
  const storage = { getItem: (key: string) => values.get(key) ?? null, setItem: (key: string, value: string) => { values.set(key, value) } }
  const session: CookingSession = { ...createSession(recipe, now), completed: [0], stepIndex: 1 }
  saveCookingSession(session, storage)
  assert.deepEqual(readCookingSession(recipe.id, storage), session)
  const other = createSession(sampleRecipes[1], now)
  saveCookingSession(other, storage)
  assert.deepEqual(readCookingSession(other.recipeId, storage), other)
  clearCookingSession(recipe.id, storage)
  assert.equal(readCookingSession(recipe.id, storage), null)
  assert.deepEqual(readCookingSession(other.recipeId, storage), other)
  const history = recordPreparation([], session, now)
  writeHistory(history, storage)
  assert.deepEqual(readHistory(storage), history)
  values.set('cocinapp.cooking-history.v1', JSON.stringify([...history, { ...history[0], id: 'bad', portions: -1 }]))
  assert.deepEqual(readHistory(storage), history)
})

test('finalization records history once, closes the session and optionally deducts pantry stock', () => {
  assert.equal(cookingCompletionPath, '/recipes')
  const values = new Map<string, string>()
  const storage = { getItem: (key: string) => values.get(key) ?? null, setItem: (key: string, value: string) => { values.set(key, value) } }
  const session = createSession(recipe, now)
  const stock: PantryItem[] = recipe.ingredients.map((ingredient, index) => ({ id: String(index), name: ingredient.name, category: 'Otros', quantity: ingredient.quantity * 2, unit: ingredient.unit, minimum: 0, expiry: null }))
  saveCookingSession(session, storage)
  writePantryItems(stock, storage)
  finalizeCookingSession(recipe, session, true, storage, now)
  assert.equal(readHistory(storage).length, 1)
  assert.equal(readHistory(storage)[0].portions, recipe.portions)
  assert.equal(readCookingSession(recipe.id, storage), null)
  assert.equal(readPantryItems(storage)[0].quantity, recipe.ingredients[0].quantity)
  finalizeCookingSession(recipe, session, false, storage, now)
  assert.equal(readHistory(storage).length, 1)
  assert.equal(readPantryItems(storage)[0].quantity, recipe.ingredients[0].quantity)
})
