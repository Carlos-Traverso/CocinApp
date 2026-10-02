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
import { createCategory, deleteCategory, restoreCategory } from '../src/features/admin/data/categoriesStore'
import { createUnit, deleteUnit, restoreUnit } from '../src/features/admin/data/unitsStore'
import { createIngredient, deleteIngredient, restoreIngredient } from '../src/features/admin/data/ingredientsStore'
import { createRecipe, createSeedRecipeOverride, deleteRecipe, duplicateRecipe, setRecipeActive, setRecipeFeatured, updateRecipe } from '../src/features/admin/data/recipesStore'
import { getAvailableRecipes } from '../src/features/recipes/data/availableRecipes'
import { getKnownRecipes, getRecipeById } from '../src/features/recipes/data/availableRecipes'
import { adminNavigation, getAdminNavigationItem } from '../src/features/admin/ui/adminNavigation'
import { createAdminDashboard } from '../src/features/admin/domain/adminDashboard'
import { filterAdminRecipes, getManagedRecipes } from '../src/features/admin/domain/adminRecipeList'
import { countAdminUsage } from '../src/features/admin/domain/adminUsage'

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
      steps: ['Mezclar.', 'Hornear.'], stepMeta: [{ durationMinutes: 8, ingredientIds: [ingredientId], utensils: ['Bol'], tip: 'Usá agua tibia.', warning: 'No amases de más.', temperature: 'Ambiente' }, {}], featured: true, status: 'published' as const, symbol: 'P', color: 'green' as const,
      image: '/assets/recipes/pan-simple.webp', imageAlt: 'Pan simple recién horneado sobre una tabla',
    }
    assert.throws(() => createRecipe({ ...recipe, ingredients: [{ ingredientId, quantity: 0, unitId: grams }] }), /positiva/i)
    assert.throws(() => createRecipe({ ...recipe, ingredients: [{ ingredientId, quantity: 200, unitId: milliliters }] }), /compatibles/i)
    assert.throws(() => createRecipe({ ...recipe, steps: ['  '] }), /instrucciones/i)
    assert.throws(() => createRecipe({ ...recipe, stepMeta: [{ minutes: 0 }] }), /tiempo de cada paso/i)
    assert.throws(() => createRecipe({ ...recipe, image: 'https://example.com/pan.webp' }), /archivo local/i)
    assert.throws(() => createRecipe({ ...recipe, imageAlt: '' }), /texto alternativo/i)
    const draftId = createRecipe({ ...recipe, title: 'Pan en borrador', status: 'draft' })
    assert.equal(getAvailableRecipes().some((entry) => entry.id === draftId), false)
    const id = createRecipe(recipe)
    assert.equal(getAvailableRecipes().find((entry) => entry.id === id)?.name, 'Pan simple')
    assert.equal(getAvailableRecipes().find((entry) => entry.id === id)?.ingredients[0]?.unit, 'g')
    assert.deepEqual(getAvailableRecipes().find((entry) => entry.id === id)?.stepMeta?.[0], {
      durationMinutes: 8,
      stepIngredients: [{ name: 'Harina', quantity: 200, unit: 'g' }],
      utensils: ['Bol'],
      tip: 'Usá agua tibia.',
      warning: 'No amases de más.',
      temperature: 'Ambiente',
    })
    assert.equal(getAvailableRecipes().find((entry) => entry.id === id)?.featured, true)
    assert.equal(getAvailableRecipes().find((entry) => entry.id === id)?.image, '/assets/recipes/pan-simple.webp')
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
    assert.equal(getRecipeById(id), undefined)
    assert.equal(localStorage.getItem('cocinapp.user.ana%40example.com.cocinapp.favorites.v1'), JSON.stringify([id]))
  })

  test('keeps valid older entries while ignoring malformed nested admin records', () => {
    localStorage.setItem('cocinapp.admin.v1', JSON.stringify({
      categories: [null, { id: 'c1', name: 'Granos' }],
      units: [null, { id: 'u1', name: 'Gramo', abbreviation: 'g', dimension: 'mass' }],
      ingredients: [null, { id: 'i1', name: 'Harina', categoryId: 'c1', baseUnitId: 'u1' }],
      recipes: [null, { id: 'r1', title: 'Pan', status: 'published', ingredients: [null, { ingredientId: 'i1', unitId: 'u1', quantity: 100 }], steps: [null, 'Hornear.'], stepMeta: [null, { minutes: 'bad', tip: 'Dejar enfriar.' }] }],
    }))
    const data = getAdminData()
    assert.equal(data.categories.length, 1)
    assert.equal(data.units[0]?.dimension, 'masa')
    assert.equal(data.ingredients.length, 1)
    assert.deepEqual(data.recipes[0]?.steps, ['Hornear.'])
    assert.equal(getAvailableRecipes().find((recipe) => recipe.id === 'r1')?.name, 'Pan')
    assert.equal(getRecipeById('r1')?.ingredients[0]?.name, 'Harina')
    localStorage.setItem('cocinapp.admin.v1', '{bad')
    assert.deepEqual(getAdminData().recipes, [])
  })

  test('does not serve a published recipe for new actions after its ingredient is archived', () => {
    const categoryId = createCategory('Granos')
    const grams = createUnit('Gramo', 'g', 'masa')
    const ingredientId = createIngredient('Harina', categoryId, grams)
    const id = createRecipe({ title: 'Pan', author: 'CocinAPP', description: '', category: 'Almuerzo', minutes: 30, portions: 1, difficulty: 'Fácil', calories: 200, mealShift: 'Almuerzo', dietaryTags: [], ingredients: [{ ingredientId, quantity: 100, unitId: grams }], steps: ['Hornear.'], status: 'published', symbol: 'P', color: 'green' })
    deleteIngredient(ingredientId)
    assert.equal(getRecipeById(id), undefined)
    assert.equal(getRecipeById(id, true)?.name, 'Pan')
  })

  test('seed recipes can be adopted, edited and deactivated without duplication', () => {
    const seeded = getRecipeById('quinoa-bowl')!
    const override = createSeedRecipeOverride(seeded)
    assert.equal(getAdminData().recipes.filter((recipe) => recipe.id === seeded.id).length, 1)
    assert.equal(createSeedRecipeOverride(seeded).id, seeded.id)
    updateRecipe(override.id, { ...override, title: 'Bowl administrado', status: 'published' })
    assert.equal(getRecipeById(seeded.id)?.name, 'Bowl administrado')
    deleteRecipe(seeded.id)
    assert.equal(getRecipeById(seeded.id), undefined)
    assert.equal(getRecipeById(seeded.id, true)?.name, 'Bowl administrado')
    assert.equal(getAdminData().recipes.find((recipe) => recipe.id === seeded.id)?.isDeleted, true)
  })
})

describe('admin navigation', () => {
  test('exposes every catalog required by the functional specification as its own route', () => {
    assert.deepEqual(adminNavigation.map((item) => item.path), [
      '/admin',
      '/admin/recipes',
      '/admin/ingredients',
      '/admin/categories',
      '/admin/units',
    ])
  })

  test('resolves nested locations to their breadcrumb section', () => {
    assert.equal(getAdminNavigationItem('/admin/recipes/new')?.label, 'Recetas')
    assert.equal(getAdminNavigationItem('/admin')?.label, 'Dashboard')
  })
})

describe('admin persistence', () => {
  test('initializes versioned categories, units and ingredients only for a new installation', () => {
    localStorage.clear()
    const seeded = getAdminData()
    assert.ok(seeded.categories.length >= 7)
    assert.ok(seeded.units.some((unit) => unit.abbreviation === 'g'))
    assert.ok(seeded.ingredients.length >= 20)

    saveAdminData({ categories: [], units: [], ingredients: [], recipes: [] })
    assert.deepEqual(getAdminData(), { categories: [], units: [], ingredients: [], recipes: [] })
    assert.equal(JSON.parse(localStorage.getItem('cocinapp.admin.v1')!).version, 2)
  })

  test('records creation and modification dates without changing the original creation date', () => {
    const categoryId = createCategory('Panadería')
    const unitId = createUnit('Gramo', 'g', 'masa')
    const ingredientId = createIngredient('Harina', categoryId, unitId)
    const createdAt = new Date('2026-09-30T10:00:00.000Z')
    const updatedAt = new Date('2026-10-01T12:00:00.000Z')
    const input = { title: 'Pan casero', author: 'CocinAPP', description: '', category: 'Almuerzo', minutes: 45, portions: 4, difficulty: 'Fácil' as const, calories: 220, mealShift: 'Almuerzo', dietaryTags: [], ingredients: [{ ingredientId, quantity: 400, unitId }], steps: ['Hornear.'], status: 'published' as const, symbol: 'P', color: 'gold' as const }
    const id = createRecipe(input, createdAt)
    updateRecipe(id, { ...input, title: 'Pan dorado' }, updatedAt)
    const recipe = getAdminData().recipes.find((entry) => entry.id === id)!
    assert.equal(recipe.createdAt, createdAt.toISOString())
    assert.equal(recipe.updatedAt, updatedAt.toISOString())
  })
})

describe('admin dashboard', () => {
  test('summarizes active, inactive and incomplete recipes with recent changes', () => {
    const data = { categories: [], units: [], ingredients: [], recipes: [
      { id: 'one', title: 'Activa', author: 'CocinAPP', description: '', category: 'Cena', minutes: 20, portions: 2, difficulty: 'Fácil' as const, calories: 100, mealShift: 'Cena', dietaryTags: [], featured: true, ingredients: [{ ingredientId: 'i', quantity: 1, unitId: 'u' }], steps: ['Cocinar'], status: 'published' as const, isDeleted: false, symbol: 'A', color: 'green' as const, updatedAt: '2026-10-01T12:00:00.000Z' },
      { id: 'two', title: 'Incompleta', author: 'CocinAPP', description: '', category: 'Cena', minutes: 20, portions: 2, difficulty: 'Fácil' as const, calories: 100, mealShift: 'Cena', dietaryTags: [], featured: false, ingredients: [], steps: [], status: 'draft' as const, isDeleted: false, symbol: 'I', color: 'gold' as const, updatedAt: '2026-09-30T12:00:00.000Z' },
    ] }
    const known = [
      { id: 'one', name: 'Activa', description: '', category: 'Cena', minutes: 20, portions: 2, difficulty: 'Fácil' as const, ingredients: [], steps: ['Cocinar'], symbol: 'A', color: 'green' as const, featured: true },
      { id: 'two', name: 'Incompleta', description: '', category: 'Cena', minutes: 20, portions: 2, difficulty: 'Fácil' as const, ingredients: [], steps: [], symbol: 'I', color: 'gold' as const },
    ]
    const summary = createAdminDashboard(data, known, [known[0]])
    assert.deepEqual(summary.metrics, { total: 2, active: 1, inactive: 1, featured: 1 })
    assert.equal(summary.alerts.missingImage, 2)
    assert.equal(summary.alerts.incomplete, 1)
    assert.equal(summary.recent[0]?.title, 'Activa')
  })
})

describe('admin recipe management', () => {
  test('combines search, status, difficulty, duration, featured and sorting filters', () => {
    const known = getKnownRecipes()
    const managed = getManagedRecipes(getAdminData(), known)
    const result = filterAdminRecipes(managed, { search: 'quinoa', status: 'active', difficulty: 'Fácil', maxMinutes: 60, featured: 'all', sort: 'title-asc' })
    assert.equal(result[0]?.id, 'quinoa-bowl')
    assert.ok(result.every((recipe) => recipe.active && recipe.minutes <= 60))
    assert.deepEqual(filterAdminRecipes(managed, { search: '', status: 'all', difficulty: 'all', maxMinutes: 0, featured: 'featured', sort: 'title-asc' }).map((recipe) => recipe.title), [...managed.filter((recipe) => recipe.featured).map((recipe) => recipe.title)].sort((a, b) => a.localeCompare(b, 'es')))
  })

  test('can feature, deactivate, reactivate and duplicate an initial recipe', () => {
    const originalTitle = getRecipeById('quinoa-bowl')!.name
    setRecipeFeatured('quinoa-bowl', true)
    assert.equal(getAdminData().recipes.find((recipe) => recipe.id === 'quinoa-bowl')?.featured, true)
    setRecipeActive('quinoa-bowl', false)
    assert.equal(getRecipeById('quinoa-bowl'), undefined)
    setRecipeActive('quinoa-bowl', true)
    assert.equal(getRecipeById('quinoa-bowl')?.name, originalTitle)
    const duplicateId = duplicateRecipe('quinoa-bowl')
    const duplicate = getAdminData().recipes.find((recipe) => recipe.id === duplicateId)!
    assert.match(duplicate.title, /^Copia de /)
    assert.equal(duplicate.status, 'draft')
  })
})

describe('admin catalog usage', () => {
  test('counts recipe associations and restores logically deleted master data', () => {
    localStorage.clear()
    const data = getAdminData()
    const usage = countAdminUsage(data, getKnownRecipes())
    const quinoa = data.ingredients.find((ingredient) => ingredient.name.toLocaleLowerCase('es').includes('quinoa'))!
    assert.ok((usage.ingredients[quinoa.id] ?? 0) > 0)
    createRecipe({ title: 'Prueba de quinoa', author: 'CocinAPP', description: '', category: 'Cena', minutes: 20, portions: 2, difficulty: 'Fácil', calories: 100, mealShift: 'Cena', dietaryTags: [], ingredients: [{ ingredientId: quinoa.id, quantity: 100, unitId: quinoa.baseUnitId }], steps: ['Cocinar.'], status: 'draft', symbol: 'Q', color: 'green' })
    deleteIngredient(quinoa.id)
    restoreIngredient(quinoa.id)
    assert.equal(getAdminData().ingredients.find((ingredient) => ingredient.id === quinoa.id)?.isDeleted, false)

    const category = data.categories.find((entry) => entry.name === 'Otros')!
    const unit = data.units.find((entry) => entry.abbreviation === 'g')!
    deleteCategory(category.id)
    deleteUnit(unit.id)
    restoreCategory(category.id)
    restoreUnit(unit.id)
    assert.equal(getAdminData().categories.find((entry) => entry.id === category.id)?.isDeleted, false)
    assert.equal(getAdminData().units.find((entry) => entry.id === unit.id)?.isDeleted, false)
  })
})
