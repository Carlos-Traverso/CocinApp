const mockStorage = new Map<string, string>()
global.localStorage = {
  getItem: (key: string) => mockStorage.get(key) ?? null,
  setItem: (key: string, value: string) => mockStorage.set(key, value),
  clear: () => mockStorage.clear(),
  removeItem: (key: string) => mockStorage.delete(key),
  key: (index: number) => [...mockStorage.keys()][index] ?? null,
  get length() { return mockStorage.size },
} as unknown as Storage
global.window = { dispatchEvent: () => {} } as unknown as Window & typeof globalThis

import assert from 'node:assert/strict'
import test, { beforeEach, describe } from 'node:test'
import { getAdminData, saveAdminData } from '../src/features/admin/data/localAdminStore'
import { createCategory, deleteCategory } from '../src/features/admin/data/categoriesStore'
import { createUnit, deleteUnit } from '../src/features/admin/data/unitsStore'
import { createIngredient, deleteIngredient } from '../src/features/admin/data/ingredientsStore'
import { createRecipe, deleteRecipe } from '../src/features/admin/data/recipesStore'
import { getAvailableRecipes } from '../src/features/recipes/data/availableRecipes'
import { getRecipeById } from '../src/features/recipes/data/availableRecipes'

describe('local admin catalog', () => {
  beforeEach(() => {
    localStorage.clear()
    saveAdminData({ categories: [], units: [], ingredients: [], recipes: [] })
  })

  test('categories require a unique non-empty name and delete physically when unreferenced', () => {
    const id = createCategory('Lácteos')
    assert.throws(() => createCategory('lácteos'), /ya existe/i)
    assert.throws(() => createCategory('   '), /nombre/i)
    deleteCategory(id)
    assert.equal(getAdminData().categories.length, 0)
  })

  test('unit dimensions, base units and equivalences are validated', () => {
    const grams = createUnit('Gramo', 'g', 'masa')
    const kilograms = createUnit('Kilogramo', 'kg', 'masa', grams, 1000)
    assert.equal(getAdminData().units.find((unit) => unit.id === kilograms)?.equivalenceMultiplier, 1000)
    assert.throws(() => createUnit('Libra', 'lb', 'masa'), /unidad base.*g/i)
    assert.throws(() => createUnit('Litro', 'l', 'volumen', grams, 1000), /compatible/i)
    assert.throws(() => createUnit('Otra gramo', 'G', 'masa'), /ya existe/i)
  })

  test('structured user pantry references trigger logical removal for categories and units', () => {
    const categoryId = createCategory('Legumbres')
    const grams = createUnit('Gramo', 'g', 'masa')
    localStorage.setItem('cocinapp.user.ana%40example.com.cocinapp.pantry.v1', JSON.stringify([
      { id: 'stock-1', name: 'Lentejas', category: 'Legumbres', unit: 'g', quantity: 200, minimum: 0, expiry: '' },
    ]))
    deleteCategory(categoryId)
    deleteUnit(grams)
    assert.equal(getAdminData().categories[0]?.isDeleted, true)
    assert.equal(getAdminData().units[0]?.isDeleted, true)
  })

  test('ingredient dimensions are required and referenced catalog rows are logically deleted', () => {
    const categoryId = createCategory('Granos')
    const gramId = createUnit('Gramo', 'g', 'masa')
    assert.throws(() => createIngredient('', categoryId, gramId), /nombre/i)
    assert.throws(() => createIngredient('Harina', categoryId, 'missing'), /unidad base/i)
    const ingredientId = createIngredient('Harina', categoryId, gramId)
    assert.throws(() => createIngredient(' harina ', categoryId, gramId), /ya existe/i)
    deleteCategory(categoryId)
    deleteUnit(gramId)
    assert.equal(getAdminData().categories[0]?.isDeleted, true)
    assert.equal(getAdminData().units[0]?.isDeleted, true)
    deleteIngredient(ingredientId)
    assert.equal(getAdminData().ingredients.length, 0)
  })

  test('recipes require complete compatible ingredients and publish to the user catalog', () => {
    const categoryId = createCategory('Granos')
    const grams = createUnit('Gramo', 'g', 'masa')
    const milliliters = createUnit('Mililitro', 'ml', 'volumen')
    const ingredientId = createIngredient('Harina', categoryId, grams)
    const recipe = {
      title: 'Pan simple', author: 'CocinAPP', description: 'Pan casero', category: 'Desayuno',
      minutes: 30, portions: 2, difficulty: 'Fácil' as const, calories: 200,
      mealShift: 'Desayuno', dietaryTags: ['Vegetariana'], ingredients: [{ ingredientId, quantity: 200, unitId: grams }],
      steps: ['Mezclar.', 'Hornear.'], stepMeta: [{ minutes: 8, tip: 'Usá agua tibia.' }, {}], status: 'published' as const, symbol: 'P', color: 'green' as const,
    }
    assert.throws(() => createRecipe({ ...recipe, ingredients: [{ ingredientId, quantity: 0, unitId: grams }] }), /positiva/i)
    assert.throws(() => createRecipe({ ...recipe, ingredients: [{ ingredientId, quantity: 200, unitId: milliliters }] }), /compatibles/i)
    assert.throws(() => createRecipe({ ...recipe, steps: ['  '] }), /instrucciones/i)
    assert.throws(() => createRecipe({ ...recipe, stepMeta: [{ minutes: 0 }] }), /tiempo de cada paso/i)
    const draftId = createRecipe({ ...recipe, title: 'Pan en borrador', status: 'draft' })
    assert.equal(getAvailableRecipes().some((entry) => entry.id === draftId), false)
    const id = createRecipe(recipe)
    assert.equal(getAvailableRecipes().find((entry) => entry.id === id)?.name, 'Pan simple')
    assert.equal(getAvailableRecipes().find((entry) => entry.id === id)?.ingredients[0]?.unit, 'g')
    assert.deepEqual(getAvailableRecipes().find((entry) => entry.id === id)?.stepMeta?.[0], { minutes: 8, tip: 'Usá agua tibia.' })
  })

  test('referenced published recipes are retained inactive and hidden from new actions', () => {
    const categoryId = createCategory('Granos')
    const grams = createUnit('Gramo', 'g', 'masa')
    const ingredientId = createIngredient('Harina', categoryId, grams)
    const id = createRecipe({ title: 'Tortillas', author: 'CocinAPP', description: '', category: 'Cena', minutes: 10, portions: 1, difficulty: 'Fácil', calories: 50, mealShift: 'Cena', dietaryTags: [], ingredients: [{ ingredientId, quantity: 50, unitId: grams }], steps: ['Cocinar.'], status: 'published', symbol: 'T', color: 'green' })
    localStorage.setItem('cocinapp.user.ana%40example.com.cocinapp.favorites.v1', JSON.stringify([id]))
    deleteRecipe(id)
    assert.equal(getAdminData().recipes[0]?.isDeleted, true)
    assert.equal(getAvailableRecipes().some((recipe) => recipe.id === id), false)
    assert.equal(getAvailableRecipes().some((recipe) => recipe.name === 'Tortillas'), false)
    assert.equal(getRecipeById(id, true)?.name, 'Tortillas')
    assert.equal(localStorage.getItem('cocinapp.user.ana%40example.com.cocinapp.favorites.v1'), JSON.stringify([id]))
  })
})
