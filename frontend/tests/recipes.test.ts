import assert from 'node:assert/strict'
import test from 'node:test'
import { sampleRecipes } from '../src/mocks/recipes'
import { filterRecipes, getIngredientAvailability } from '../src/features/recipes/domain/recipeRules'
import { readFavoriteIds, writeFavoriteIds } from '../src/features/recipes/data/localFavoritesStore'
import type { PantryItem } from '../src/features/pantry/domain/pantry'

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

test('recipe filters combine text, category, time, difficulty and pantry availability', () => {
  assert.deepEqual(filterRecipes(sampleRecipes, { search: 'CALABAZA', category: '', maxMinutes: null, difficulty: '', pantryOnly: false }, pantry, today).map((item) => item.id), ['pumpkin-pasta'])
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
