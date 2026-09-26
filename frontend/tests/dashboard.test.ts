import assert from 'node:assert/strict'
import test from 'node:test'
import { sampleRecipes } from '../src/mocks/recipes'
import type { PantryItem } from '../src/features/pantry/domain/pantry'
import type { PlannedMeal } from '../src/features/planner/domain/planner'
import type { ShoppingItem } from '../src/features/shopping/domain/shopping'
import type { PreparationEvent } from '../src/features/cooking/domain/cooking'
import { buildDashboardSummary } from '../src/features/dashboard/domain/dashboard'

const today = new Date(2026, 8, 23)
const pantry: PantryItem[] = [
  { id: 'rice', name: 'Arroz integral', category: 'Granos y legumbres', quantity: 100, unit: 'g', minimum: 200, expiry: '' },
  { id: 'tomato', name: 'Tomates cherry', category: 'Frutas y verduras', quantity: 150, unit: 'g', minimum: 0, expiry: '2026-09-24' },
  { id: 'expired-oil', name: 'Aceite de oliva', category: 'Almacén', quantity: 30, unit: 'ml', minimum: 0, expiry: '2026-09-22' },
]

test('summarizes low stock and separates expired from soon-to-expire ingredients', () => {
  const summary = buildDashboardSummary({ pantry, recipes: [], favoriteIds: [], plan: [], shopping: [], history: [] }, today)

  assert.equal(summary.pantry.totalItems, 3)
  assert.deepEqual(summary.pantry.lowStock.map((item) => item.id), ['rice'])
  assert.deepEqual(summary.pantry.expired.map((item) => item.id), ['expired-oil'])
  assert.deepEqual(summary.pantry.expiringSoon.map((item) => item.id), ['tomato'])
})

test('prioritizes recipes that can be cooked and summarizes favorites, plan, shopping and history', () => {
  const quinoa: PantryItem[] = sampleRecipes[0].ingredients.map((ingredient) => ({
    id: ingredient.name,
    name: ingredient.name,
    category: 'Otros',
    quantity: ingredient.quantity,
    unit: ingredient.unit,
    minimum: 0,
    expiry: '',
  }))
  const plan: PlannedMeal[] = [
    { date: '2026-09-23', meal: 'Almuerzo', recipeId: 'quinoa-bowl' },
    { date: '2026-09-25', meal: 'Cena', recipeId: 'pumpkin-pasta' },
    { date: '2026-09-28', meal: 'Cena', recipeId: 'chicken-rice' },
  ]
  const shopping: ShoppingItem[] = [
    { id: 'pending', name: 'Queso', category: 'Lácteos', quantity: 1, unit: 'u', note: '', checked: false, sources: ['manual'] },
    { id: 'done', name: 'Sal', category: 'Almacén', quantity: 1, unit: 'u', note: '', checked: true, sources: ['manual'] },
  ]
  const history: PreparationEvent[] = [
    { id: 'old', recipeId: 'pumpkin-pasta', cookedAt: '2026-09-20T12:00:00.000Z', portions: 3 },
    { id: 'new', recipeId: 'quinoa-bowl', cookedAt: '2026-09-22T12:00:00.000Z', portions: 2 },
  ]

  const summary = buildDashboardSummary({
    pantry: quinoa,
    recipes: sampleRecipes,
    favoriteIds: ['pumpkin-pasta', 'unknown'],
    plan,
    shopping,
    history,
  }, today)

  assert.equal(summary.suggestedRecipes[0]?.recipe.id, 'quinoa-bowl')
  assert.deepEqual(summary.favorites.map((recipe) => recipe.id), ['pumpkin-pasta'])
  assert.deepEqual(summary.todayMeals.map((entry) => entry.recipe?.id), ['quinoa-bowl'])
  assert.equal(summary.weeklyMealCount, 2)
  assert.equal(summary.shopping.pendingCount, 1)
  assert.equal(summary.shopping.completedCount, 1)
  assert.deepEqual(summary.recentHistory.map((entry) => entry.id), ['new', 'old'])
  assert.equal(summary.discovery.featured.length, 3)
  assert.deepEqual(summary.discovery.recook.map((recipe) => recipe.id), ['quinoa-bowl', 'pumpkin-pasta'])
})

test('returns actionable empty values when every local source is empty', () => {
  const summary = buildDashboardSummary({ pantry: [], recipes: [], favoriteIds: [], plan: [], shopping: [], history: [] }, today)

  assert.equal(summary.pantry.totalItems, 0)
  assert.deepEqual(summary.suggestedRecipes, [])
  assert.deepEqual(summary.favorites, [])
  assert.deepEqual(summary.todayMeals, [])
  assert.equal(summary.weeklyMealCount, 0)
  assert.equal(summary.shopping.pendingCount, 0)
  assert.deepEqual(summary.recentHistory, [])
  assert.deepEqual(summary.discovery.recook, [])
  assert.deepEqual(summary.discovery.basedOnHistory, [])
})

test('today includes four ordered turns and keeps a historical inactive assignment visible', () => {
  const plan: PlannedMeal[] = [
    { date: '2026-09-23', meal: 'Cena', recipeId: 'pumpkin-pasta' },
    { date: '2026-09-23', meal: 'Merienda', recipeId: 'chickpea-salad' },
    { date: '2026-09-23', meal: 'Desayuno', recipeId: 'quinoa-bowl' },
    { date: '2026-09-23', meal: 'Almuerzo', recipeId: 'chicken-rice' },
  ]
  const summary = buildDashboardSummary({ pantry: [], recipes: sampleRecipes.slice(1), knownRecipes: sampleRecipes, favoriteIds: [], plan, shopping: [], history: [] }, today)
  assert.deepEqual(summary.todayMeals.map((entry) => entry.meal), ['Desayuno', 'Almuerzo', 'Merienda', 'Cena'])
  assert.equal(summary.todayMeals[0]?.recipe.id, 'quinoa-bowl')
  assert.equal(summary.weeklyMealCount, 4)
})
