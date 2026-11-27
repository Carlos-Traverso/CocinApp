import assert from 'node:assert/strict'
import test from 'node:test'
import { sampleRecipes } from '../src/mocks/recipes'
import type { PantryItem } from '../src/features/pantry/domain/pantry'
import { buildCookingSuggestions, buildDashboardRecommendations, findPlannedRecipe, mealForHour, recentPreparations, recommendRecipeForTime } from '../src/features/dashboard/domain/dashboard'

const today = new Date(2026, 8, 23)

test('today plan resolves each legacy recipe by its own ID and leaves unknown recipes unresolved', () => {
  const recipeIds = ['scrambled-eggs-toast', 'pumpkin-pasta', 'overnight-oats', 'spinach-pie']
  assert.deepEqual(recipeIds.map((recipeId) => findPlannedRecipe(sampleRecipes, { recipeId })?.id), recipeIds)
  assert.equal(findPlannedRecipe(sampleRecipes, { recipeId: 'unknown-recipe' }), undefined)
})

test('today plan resolves a recipe by its relational ID when its route ID differs', () => {
  const recipe = { ...sampleRecipes[0], relationalId: 'relational-recipe' }
  assert.equal(findPlannedRecipe([recipe], { recipeId: 'old-route', relationalId: recipe.relationalId }), recipe)
})

test('meal boundaries cover the four local time ranges exactly', () => {
  assert.equal(mealForHour(4), 'Cena')
  assert.equal(mealForHour(5), 'Desayuno')
  assert.equal(mealForHour(10), 'Desayuno')
  assert.equal(mealForHour(11), 'Almuerzo')
  assert.equal(mealForHour(14), 'Almuerzo')
  assert.equal(mealForHour(15), 'Merienda')
  assert.equal(mealForHour(18), 'Merienda')
  assert.equal(mealForHour(19), 'Cena')
  assert.equal(mealForHour(23), 'Cena')
  assert.equal(mealForHour(0), 'Cena')
})

test('cooking suggestions include complete and nearly cookable recipes while ignoring expired stock', () => {
  const recipe = sampleRecipes.find((item) => item.id === 'yogurt-fruit')!
  const pantry: PantryItem[] = [
    { id: 'yogurt', name: 'Yogur', category: 'Lácteos', quantity: 180, unit: 'g', minimum: 0, expiry: null },
    { id: 'banana', name: 'Banana', category: 'Frutas y verduras', quantity: 1, unit: 'u', minimum: 0, expiry: '2026-09-22' },
    { id: 'oats', name: 'Avena', category: 'Almacén', quantity: 40, unit: 'g', minimum: 0, expiry: null },
  ]
  const [suggestion] = buildCookingSuggestions([recipe], pantry, today)
  assert.equal(suggestion.canCook, false)
  assert.equal(suggestion.availableCount, 2)
  assert.deepEqual(suggestion.missingNames, ['Banana'])
  assert.match(suggestion.reason, /falta Banana/)
  assert.equal(buildCookingSuggestions([{ ...recipe, ingredients: [...recipe.ingredients, { name: 'Miel', quantity: 10, unit: 'g' }, { name: 'Nueces', quantity: 10, unit: 'g' }] }], pantry, today).length, 0)
})

test('time recommendation prioritizes meal, pantry, favorites, history and admin featured state', () => {
  const favorite = { ...sampleRecipes.find((recipe) => recipe.id === 'banana-pancakes')!, ingredients: [{ name: 'Banana', quantity: 1, unit: 'u' }] }
  const alternative = { ...sampleRecipes.find((recipe) => recipe.id === 'yogurt-fruit')!, featured: true, ingredients: [{ name: 'Yogur', quantity: 1, unit: 'u' }] }
  const pantry = favorite.ingredients.map((ingredient, index): PantryItem => ({ id: String(index), name: ingredient.name, category: 'Otros', quantity: ingredient.quantity, unit: ingredient.unit, minimum: 0, expiry: null }))
  const recommendation = recommendRecipeForTime([alternative, favorite], 8, { pantry, favoriteIds: [favorite.id], history: [{ id: 'h', recipeId: favorite.id, cookedAt: '2026-09-20T12:00:00.000Z', portions: 2 }], rotation: 0, today })
  assert.equal(recommendation.meal, 'Desayuno')
  assert.equal(recommendation.recipe?.id, favorite.id)
  assert.match(recommendation.reason ?? '', /desayuno.*despensa.*favoritas/i)
  const multiShift = { ...favorite, id: 'multi-shift', category: 'Cena', mealShift: 'Cena', mealShifts: ['Desayuno', 'Merienda'] }
  assert.equal(recommendRecipeForTime([multiShift], 8).recipe?.id, 'multi-shift')
  assert.equal(recommendRecipeForTime([], 13).recipe, undefined)
})

test('rotation varies equally ranked options and recent history handles empty and known data', () => {
  const equal = sampleRecipes.filter((recipe) => recipe.category === 'Merienda').map((recipe) => ({ ...recipe, minutes: 10, featured: false }))
  const first = recommendRecipeForTime(equal, 16, { rotation: 0 }).recipe?.id
  const second = recommendRecipeForTime(equal, 16, { rotation: 1 }).recipe?.id
  assert.notEqual(first, second)
  assert.deepEqual(recentPreparations([], equal.map((recipe) => recipe.id)), [])
  const history = [
    { id: 'old', recipeId: equal[0].id, cookedAt: '2026-09-20T12:00:00.000Z', portions: 1 },
    { id: 'unknown', recipeId: 'inactive', cookedAt: '2026-09-23T12:00:00.000Z', portions: 1 },
    { id: 'new', recipeId: equal[1].id, cookedAt: '2026-09-22T12:00:00.000Z', portions: 2 },
  ]
  assert.deepEqual(recentPreparations(history, equal.map((recipe) => recipe.id)).map((event) => event.id), ['new', 'old'])
})

test('panel recommendations backfill eligible recipes without repeating them across sections', () => {
  const base = sampleRecipes[0]
  const featured = Array.from({ length: 7 }, (_, index) => ({
    ...base, id: `featured-${index}`, name: `Destacada ${index}`, mealShifts: index === 0 ? ['Cena'] : ['Almuerzo'],
    featured: true, minutes: 15, ingredients: [{ name: 'Arroz', quantity: 1, unit: 'g' }],
  }))
  const nearlyCookable = {
    ...base, id: 'nearly-cookable', mealShifts: ['Almuerzo'], featured: false, minutes: 25,
    ingredients: [...featured[0].ingredients, { name: 'Tomate', quantity: 1, unit: 'u' }],
  }
  const pantry: PantryItem[] = [{ id: 'rice', name: 'Arroz', category: 'Almacén', quantity: 100, unit: 'g', minimum: 0, expiry: null }]
  const recipes = [...featured, nearlyCookable]
  const options = { pantry, favoriteIds: [], history: [], preferences: [], today }
  const { timeSuggestion, recommendations, suggestions } = buildDashboardRecommendations(recipes, recipes, 20, options)

  assert.equal(timeSuggestion.recipe?.id, 'featured-0')
  assert.equal(recommendations.hero?.id, 'featured-1')
  assert.deepEqual(recommendations.sections.find((section) => section.id === 'recipe-featured')?.recipes.map((recipe) => recipe.id),
    ['featured-2', 'featured-3', 'featured-4', 'featured-5'])
  assert.deepEqual(recommendations.sections.find((section) => section.id === 'recipe-pantry-ready')?.recipes.map((recipe) => recipe.id), ['featured-6'])
  assert.deepEqual(suggestions.map(({ recipe }) => recipe.id), [nearlyCookable.id])
  const displayed = [timeSuggestion.recipe, recommendations.hero, ...recommendations.sections.flatMap((section) => section.recipes),
    ...suggestions.map(({ recipe }) => recipe)].map((recipe) => recipe?.id)
  assert.equal(new Set(displayed).size, displayed.length)

  const single = buildDashboardRecommendations([base], [base], 20, options)
  assert.equal(single.timeSuggestion.recipe?.id, base.id)
  assert.equal(single.recommendations.hero, undefined)
  assert.ok(single.recommendations.sections.every((section) => section.recipes.length === 0))
  assert.deepEqual(single.suggestions, [])
})
