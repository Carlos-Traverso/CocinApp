import assert from 'node:assert/strict'
import test from 'node:test'
import { existsSync } from 'node:fs'
import { fileURLToPath } from 'node:url'
import { sampleRecipes } from '../src/mocks/recipes'
import { filterRecipes, getIngredientAvailability, getIngredientDeficits, getRecipeReadiness, matchesDietaryPreferences, parseRecipePortions } from '../src/features/recipes/domain/recipeRules'
import { readFavoriteIds, writeFavoriteIds } from '../src/features/recipes/data/localFavoritesStore'
import { discoverRecipes } from '../src/features/recipes/domain/recipeDiscovery'
import type { PantryItem } from '../src/features/pantry/domain/pantry'
import { mergeRecipeSeed, recipeSeed, recipeSeedVersion } from '../src/features/recipes/data/recipeSeed'
import { buildRecipeRecommendations } from '../src/features/recipes/domain/recipeRecommendations'
import { adminSeedId, createInitialAdminData } from '../src/features/admin/data/adminSeed'
import { saveAdminData } from '../src/features/admin/data/localAdminStore'
import { getAvailableRecipes, getKnownRecipes } from '../src/features/recipes/data/availableRecipes'
import { buildCookingSuggestions } from '../src/features/dashboard/domain/dashboard'

const testLocalStorage = new Map<string, string>()
Object.defineProperty(globalThis, 'localStorage', { configurable: true, value: {
  getItem: (key: string) => testLocalStorage.get(key) ?? null,
  setItem: (key: string, value: string) => { testLocalStorage.set(key, value) },
  removeItem: (key: string) => { testLocalStorage.delete(key) },
  clear: () => testLocalStorage.clear(),
} })
Object.defineProperty(globalThis, 'window', { configurable: true, value: { dispatchEvent: () => {} } })

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
  assert.equal(recipeSeedVersion, 3)
  assert.equal(recipeSeed.length, 22)
  assert.deepEqual(new Set(recipeSeed.map((recipe) => recipe.category)), new Set(['Almuerzo', 'Cena', 'Desayuno', 'Merienda']))
  assert.equal(recipeSeed.every((recipe) => recipe.steps.length > 0 && recipe.ingredients.length > 0 && recipe.symbol), true)
  assert.equal(mergeRecipeSeed(recipeSeed, []).length, 22)
  assert.equal(mergeRecipeSeed(mergeRecipeSeed(recipeSeed, []), []).length, 22)
})

test('every seeded recipe has a unique local WebP photograph and useful alternative text', () => {
  const images = recipeSeed.map((recipe) => recipe.image)
  assert.equal(new Set(images).size, recipeSeed.length)
  for (const recipe of recipeSeed) {
    assert.match(recipe.image ?? '', /^\/assets\/recipes\/[a-z0-9-]+\.webp$/)
    assert.ok((recipe.imageAlt?.trim().length ?? 0) >= 20)
    assert.equal(existsSync(fileURLToPath(new URL(`../public${recipe.image}`, import.meta.url))), true, recipe.image)
  }
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
  assert.deepEqual(filterRecipes(sampleRecipes, { search: '', category: 'Almuerzo', maxMinutes: 25, difficulty: 'Fácil', pantryOnly: false }, pantry, today).map((item) => item.id), ['chickpea-salad', 'caprese-sandwich', 'tuna-rice-salad', 'vegetable-wrap'])
  assert.deepEqual(filterRecipes(sampleRecipes, { search: '', category: '', maxMinutes: null, difficulty: '', pantryOnly: true }, pantry, today), [])
})

test('recipe turn filters accept every selected meal shift and keep scalar/category legacy fallbacks', () => {
  const multiShift = { ...sampleRecipes[0]!, id: 'multi-shift', category: 'Cena', mealShift: 'Cena', mealShifts: ['Desayuno', 'Merienda'] }
  assert.deepEqual(filterRecipes([multiShift], { search: '', category: 'Desayuno', maxMinutes: null, difficulty: '', pantryOnly: false }, []).map((recipe) => recipe.id), ['multi-shift'])
  assert.deepEqual(filterRecipes([multiShift], { search: '', category: 'Merienda', maxMinutes: null, difficulty: '', pantryOnly: false }, []).map((recipe) => recipe.id), ['multi-shift'])
  assert.deepEqual(filterRecipes([multiShift], { search: '', category: 'Cena', maxMinutes: null, difficulty: '', pantryOnly: false }, []), [])
  const scalarLegacy = { ...sampleRecipes[0]!, id: 'scalar-legacy', category: 'Cena', mealShift: 'Almuerzo' }
  assert.deepEqual(filterRecipes([scalarLegacy], { search: '', category: 'Almuerzo', maxMinutes: null, difficulty: '', pantryOnly: false }, []).map((recipe) => recipe.id), ['scalar-legacy'])
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

test('readiness reports exact deficits in the recipe unit and groups repeated ingredients', () => {
  const repeated = { ...sampleRecipes[0], ingredients: [
    { name: 'Harina', quantity: 0.5, unit: 'kg' },
    { name: 'Harina', quantity: 250, unit: 'g' },
  ] }
  const stock: PantryItem[] = [{ id: 'flour', name: 'Harina', category: 'Almacén', quantity: 600, unit: 'g', minimum: 0, expiry: '' }]
  const readiness = getRecipeReadiness(repeated, stock)
  assert.equal(readiness.percentage, 0)
  assert.equal(readiness.label, 'Requiere compra')
  assert.equal(readiness.missing[0]?.required, 0.75)
  assert.equal(readiness.missing[0]?.available, 0.6)
  assert.equal(readiness.missing[0]?.missing, 0.15)
  assert.equal(getIngredientDeficits(repeated, stock)[0]?.ingredient.unit, 'kg')
})

test('readiness threshold uses complete ingredient matches, not partial amounts', () => {
  const recipe = { ...sampleRecipes[0], portions: 1, ingredients: ['a', 'b', 'c', 'd', 'e'].map((name) => ({ name, quantity: 1, unit: 'u' })) }
  const stock: PantryItem[] = ['a', 'b', 'c'].map((name, index) => ({ id: String(index), name, category: 'Otros', quantity: 1, unit: 'u', minimum: 0, expiry: '' }))
  assert.deepEqual(getRecipeReadiness(recipe, stock).percentage, 60)
  assert.equal(getRecipeReadiness(recipe, stock).label, 'Casi lista')
  const oneMissingTinyAmount = { ...recipe, ingredients: [...recipe.ingredients.slice(0, 1), { name: 'f', quantity: 0.0001, unit: 'u' }] }
  const tinyReadiness = getRecipeReadiness(oneMissingTinyAmount, stock)
  assert.equal(tinyReadiness.label, 'Requiere compra')
  assert.equal(tinyReadiness.percentage, 50)
  assert.equal(tinyReadiness.missing[0]?.missing, 0.0001)
})

test('dietary preferences combine and accept explicit celiaquía aliases', () => {
  const recipe = { ...sampleRecipes[0], dietaryTags: ['Apto Celíaco', 'Vegana'] }
  assert.equal(matchesDietaryPreferences(recipe, ['gluten-free', 'vegan']), true)
  assert.equal(matchesDietaryPreferences(recipe, ['gluten-free', 'nut-free']), false)
  assert.deepEqual(filterRecipes([recipe], { search: '', category: '', maxMinutes: null, difficulty: '', pantryOnly: false, preferences: ['gluten-free', 'vegan'] }, []).map((item) => item.id), [recipe.id])
})

test('portion links accept only bounded integer servings and preserve the recipe default otherwise', () => {
  assert.equal(parseRecipePortions('4'), 4)
  for (const invalid of [null, '', '0', '2.5', '-1', '21', 'abc']) assert.equal(parseRecipePortions(invalid), undefined)
})

test('readiness preserves a tiny positive kilogram shortage', () => {
  const recipe = { ...sampleRecipes[0], ingredients: [{ name: 'Harina', quantity: 0.001, unit: 'kg' }] }
  const stock: PantryItem[] = [{ id: 'flour', name: 'Harina', category: 'Almacén', quantity: 0.000999, unit: 'kg', minimum: 0, expiry: '' }]
  const readiness = getRecipeReadiness(recipe, stock)
  assert.ok(readiness.missing[0]?.missing && readiness.missing[0].missing > 0)
  assert.notEqual(readiness.label, 'Lista para cocinar')
})

test('same-dimension units with incompatible roots keep each repeated requirement visible', () => {
  const units = [
    { id: 'root-a', name: 'Cucharón A', abbreviation: 'ca', dimension: 'masa' as const, active: true, isDeleted: false },
    { id: 'root-b', name: 'Cucharón B', abbreviation: 'cb', dimension: 'masa' as const, active: true, isDeleted: false },
  ]
  const recipe = { ...sampleRecipes[0], ingredients: [{ name: 'Harina', quantity: 2, unit: 'ca' }, { name: 'Harina', quantity: 3, unit: 'cb' }] }
  const deficits = getIngredientDeficits(recipe, [], recipe.portions, today, units)
  assert.deepEqual(deficits.map((item) => [item.required, item.missing]), [[2, 2], [3, 3]])
})

test('recommendations use an optional custom unit catalog while preserving default call signatures', () => {
  const units = [
    { id: 'g', name: 'Gramo', abbreviation: 'g', dimension: 'masa' as const, active: true, isDeleted: false },
    { id: 'scoop', name: 'Medida', abbreviation: 'scoop', dimension: 'masa' as const, baseUnitId: 'g', equivalenceMultiplier: 100, active: true, isDeleted: false },
  ]
  const recipe = { ...sampleRecipes[0], featured: true, ingredients: [{ name: 'Harina especial', quantity: 1, unit: 'scoop' }] }
  const stock: PantryItem[] = [{ id: 'flour', name: 'Harina especial', category: 'Almacén', quantity: 100, unit: 'g', minimum: 0, expiry: null }]
  assert.equal(buildRecipeRecommendations([recipe], [recipe], stock, [], [], today, [], units).sections.find((section) => section.id === 'recipe-pantry-ready')?.recipes[0]?.id, recipe.id)
  assert.equal(buildCookingSuggestions([recipe], stock, today, 4, units)[0]?.canCook, true)
  assert.equal(buildCookingSuggestions([recipe], stock, today)[0]?.canCook, false)
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

test('new recipe actions exclude published recipes that depend on inactive catalog records', () => {
  const previousStorage = globalThis.localStorage
  const previousWindow = globalThis.window
  const entries = new Map<string, string>()
  Object.defineProperty(globalThis, 'localStorage', { configurable: true, value: {
    getItem: (key: string) => entries.get(key) ?? null,
    setItem: (key: string, value: string) => { entries.set(key, value) },
  } })
  Object.defineProperty(globalThis, 'window', { configurable: true, value: { dispatchEvent: () => {} } })
  try {
    const catalog = createInitialAdminData()
    const seed = recipeSeed[0]!
    const recipe = {
      id: seed.id, title: seed.name, author: 'CocinAPP', description: seed.description, category: seed.category,
      minutes: seed.minutes, portions: seed.portions, difficulty: seed.difficulty, calories: seed.calories ?? 0,
      mealShift: seed.mealShift ?? seed.category, mealShifts: ['Desayuno', 'Merienda'], dietaryTags: [...(seed.dietaryTags ?? [])],
      ingredients: seed.ingredients.map((item) => ({ ingredientId: adminSeedId('ingredient', item.name), quantity: item.quantity, unitId: adminSeedId('unit', item.unit) })),
      steps: [...seed.steps], status: 'published' as const, active: true, isDeleted: false, symbol: seed.symbol, color: seed.color,
    }
    catalog.recipes = [recipe]
    const ingredient = catalog.ingredients.find((entry) => entry.id === recipe.ingredients[0]?.ingredientId)
    assert.ok(ingredient)
    ingredient.active = false
    saveAdminData(catalog)
    assert.deepEqual(getKnownRecipes().find((entry) => entry.id === seed.id)?.mealShifts, ['Desayuno', 'Merienda'])
    assert.equal(getAvailableRecipes().some((entry) => entry.id === seed.id), false)
  } finally {
    if (previousStorage === undefined) Reflect.deleteProperty(globalThis, 'localStorage')
    else Object.defineProperty(globalThis, 'localStorage', { configurable: true, value: previousStorage })
    if (previousWindow === undefined) Reflect.deleteProperty(globalThis, 'window')
    else Object.defineProperty(globalThis, 'window', { configurable: true, value: previousWindow })
  }
})

test('recommendations keep their real sections in the panel order without duplicating recipes logic', () => {
  const history = [{ id: 'history', recipeId: 'quinoa-bowl', cookedAt: '2026-09-23T11:00:00.000Z', portions: 2 }]
  const recommendations = buildRecipeRecommendations(sampleRecipes, sampleRecipes, pantry, ['chickpea-salad'], history, today)
  assert.deepEqual(recommendations.sections.map((section) => section.id), [
    'recipe-featured',
    'recipe-pantry-ready',
    'recipe-history-based',
    'recipe-recook',
    'recipe-favorites',
    'recipe-quick',
  ])
  assert.equal(recommendations.sections.find((section) => section.id === 'recipe-recook')?.recipes[0]?.id, 'quinoa-bowl')
  assert.equal(recommendations.sections.find((section) => section.id === 'recipe-favorites')?.recipes[0]?.id, 'chickpea-salad')
  assert.ok(recommendations.hero)
})
