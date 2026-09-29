import assert from 'node:assert/strict'
import test from 'node:test'
import { sampleRecipes } from '../src/mocks/recipes'
import { filterRecipes, getIngredientAvailability } from '../src/features/recipes/domain/recipeRules'
import { readFavoriteIds, writeFavoriteIds } from '../src/features/recipes/data/localFavoritesStore'
import { discoverRecipes } from '../src/features/recipes/domain/recipeDiscovery'
import type { PantryItem } from '../src/features/pantry/domain/pantry'
import { mergeRecipeSeed, recipeSeed, recipeSeedVersion } from '../src/features/recipes/data/recipeSeed'

const pantry: PantryItem[] = [
  { id: 'a', name: 'Quinoa', category: 'Granos y legumbres', quantity: 150, unit: 'g', minimum: 0, expiry: '' },
  { id: 'b', name: 'Tomate', category: 'Frutas y verduras', quantity: 1, unit: 'u', minimum: 0, expiry: '' },
  { id: 'c', name: 'Limón', category: 'Frutas y verduras', quantity: 1, unit: 'u', minimum: 0, expiry: '2026-09-22' },
]
const today = new Date(2026, 8, 23)

test('ingredient availability checks quantity, unit and expiry', () => {
  const recipe = sampleRecipes[0]
  const result = getIngredientAvailability(recipe, pantry, today)
  assert.deepEqual(result.available.map((item) => item.name), ['Quinoa'])
  assert.deepEqual(result.missing.map((item) => item.name), ['Tomates cherry', 'Aceite de oliva', 'Limón'])
})

test('the versioned seed provides a complete varied catalog and remains idempotent', () => {
  assert.equal(recipeSeedVersion, 2)
  assert.equal(recipeSeed.length, 22)
  assert.deepEqual(new Set(recipeSeed.map((recipe) => recipe.category)), new Set(['Almuerzo', 'Cena', 'Desayuno', 'Merienda']))
  assert.equal(recipeSeed.every((recipe) => recipe.steps.length > 0 && recipe.ingredients.length > 0 && recipe.symbol), true)
  assert.equal(mergeRecipeSeed(recipeSeed, []).length, 22)
  assert.equal(mergeRecipeSeed(mergeRecipeSeed(recipeSeed, []), []).length, 22)
})

test('administrator records override a seed recipe without duplicating or losing new seed entries', () => {
  const override = { ...recipeSeed[0], name: 'Bowl personalizado' }
  const merged = mergeRecipeSeed(recipeSeed, [override])
  assert.equal(merged.length, 22)
  assert.equal(merged.find((recipe) => recipe.id === override.id)?.name, 'Bowl personalizado')
  assert.equal(merged.some((recipe) => recipe.id === 'roasted-vegetable-soup'), true)
})

test('recipe filters combine text, category, time, difficulty and pantry availability', () => {
  assert.deepEqual(filterRecipes(sampleRecipes, { search: 'CALABAZA', category: '', maxMinutes: null, difficulty: '', pantryOnly: false }, pantry, today).map((item) => item.id), ['pumpkin-pasta', 'roasted-vegetable-soup'])
  assert.deepEqual(filterRecipes(sampleRecipes, { search: '', category: 'Almuerzo', maxMinutes: 25, difficulty: 'Fácil', pantryOnly: false }, pantry, today).map((item) => item.id), ['chickpea-salad'])
  assert.deepEqual(filterRecipes(sampleRecipes, { search: '', category: '', maxMinutes: null, difficulty: '', pantryOnly: true }, pantry, today), [])
})

test('the example pantry can produce a recipe in the pantry-only filter', () => {
  const examples: PantryItem[] = [
    { id: 'chicken', name: 'Pechuga de pollo', category: 'Carnes y pescados', quantity: 500, unit: 'g', minimum: 0, expiry: '' },
    { id: 'rice', name: 'Arroz integral', category: 'Granos y legumbres', quantity: 1000, unit: 'g', minimum: 0, expiry: '' },
    { id: 'tomato', name: 'Tomates cherry', category: 'Frutas y verduras', quantity: 250, unit: 'g', minimum: 0, expiry: '' },
    { id: 'oil', name: 'Aceite de oliva', category: 'Almacén', quantity: 750, unit: 'ml', minimum: 0, expiry: '' },
  ]
  assert.deepEqual(filterRecipes(sampleRecipes, { search: '', category: '', maxMinutes: null, difficulty: '', pantryOnly: true }, examples, today).map((item) => item.id), ['chicken-rice'])
})

test('recipe availability converts compatible metric units and never crosses dimensions', () => {
  const recipe = { ...sampleRecipes[0], ingredients: [{ name: 'Harina', quantity: 1, unit: 'kg' }] }
  const matchingPantry: PantryItem[] = [{ id: 'flour', name: 'Harina', category: 'Almacén', quantity: 1000, unit: 'g', minimum: 0, expiry: '' }]
  assert.deepEqual(getIngredientAvailability(recipe, matchingPantry).missing, [])
  const incompatible: PantryItem[] = [{ ...matchingPantry[0], quantity: 2000, unit: 'ml' }]
  assert.equal(getIngredientAvailability(recipe, incompatible).missing.length, 1)
})

test('favorites persist known IDs and ignore malformed storage', () => {
  const entries = new Map<string, string>()
  const storage = { getItem: (key: string) => entries.get(key) ?? null, setItem: (key: string, value: string) => { entries.set(key, value) } }
  writeFavoriteIds(['quinoa-bowl'], storage)
  assert.deepEqual(readFavoriteIds(storage), ['quinoa-bowl'])
  entries.set('cocinapp.favorites.v1', JSON.stringify(['quinoa-bowl', 'unknown', 7, 'quinoa-bowl']))
  assert.deepEqual(readFavoriteIds(storage), ['quinoa-bowl'])
  entries.set('cocinapp.favorites.v1', '{bad')
  assert.deepEqual(readFavoriteIds(storage), [])
})

test('discovery uses local history deterministically and excludes inactive recipes from new actions', () => {
  const history = [
    { id: 'old', recipeId: 'pumpkin-pasta', cookedAt: '2026-09-22T10:00:00.000Z', portions: 2 },
    { id: 'new', recipeId: 'quinoa-bowl', cookedAt: '2026-09-23T10:00:00.000Z', portions: 2 },
    { id: 'again', recipeId: 'quinoa-bowl', cookedAt: '2026-09-23T11:00:00.000Z', portions: 2 },
  ]
  const active = sampleRecipes.filter((recipe) => recipe.id !== 'quinoa-bowl')
  const result = discoverRecipes(active, sampleRecipes, ['chickpea-salad', 'chickpea-salad'], history)
  assert.deepEqual(result.recook.map((recipe) => recipe.id), ['pumpkin-pasta'])
  assert.deepEqual(result.favorites.map((recipe) => recipe.id), ['chickpea-salad'])
  assert.equal(result.featured.some((recipe) => recipe.id === 'quinoa-bowl'), false)
  assert.equal(result.basedOnHistory.some((recipe) => recipe.id === 'quinoa-bowl' || recipe.id === 'pumpkin-pasta'), false)
  assert.deepEqual(discoverRecipes(active, sampleRecipes, [], []).basedOnHistory, [])
})
