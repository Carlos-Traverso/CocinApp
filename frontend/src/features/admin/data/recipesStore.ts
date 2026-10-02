import { getAdminData, saveAdminData } from './localAdminStore'
import type { AdminRecipe } from '../domain/adminModels'
import { hasAdminReferences } from './adminReferences'
import { validateRecipe } from '../domain/adminValidation'
import type { Recipe } from '../../recipes/domain/Recipe'
import { normalizePantryName } from '../../pantry/domain/pantry'
import { recipeSeed } from '../../recipes/data/recipeSeed'
import { adminSeedId, seedUnitDefinitions } from './adminSeed'

export function createSeedRecipeOverride(recipe: Recipe, now = new Date()): AdminRecipe {
  const data = getAdminData()
  const existing = data.recipes.find((entry) => entry.id === recipe.id)
  if (existing) return existing
  const categoryId = adminSeedId('category', 'Otros')
  if (!data.categories.some((entry) => entry.id === categoryId)) data.categories.push({ id: categoryId, name: 'Otros', isDeleted: false })
  const ensureUnit = (abbreviation: string) => {
    const definition = seedUnitDefinitions[abbreviation as keyof typeof seedUnitDefinitions] ?? { name: abbreviation, dimension: 'conteo' as const }
    const id = adminSeedId('unit', abbreviation)
    if (!data.units.some((entry) => entry.id === id)) {
      const baseAbbreviation = definition.dimension === 'masa' ? 'g' : definition.dimension === 'volumen' ? 'ml' : 'u'
      const baseUnitId = adminSeedId('unit', baseAbbreviation)
      if (baseAbbreviation !== abbreviation) ensureUnit(baseAbbreviation)
      data.units.push({ id, name: definition.name, abbreviation, dimension: definition.dimension,
        baseUnitId: baseAbbreviation === abbreviation ? undefined : baseUnitId,
        equivalenceMultiplier: abbreviation === 'kg' || abbreviation === 'l' ? 1000 : undefined, isDeleted: false })
    }
    return id
  }
  const ingredients = recipe.ingredients.map((ingredient) => {
    const unitId = ensureUnit(ingredient.unit)
    const ingredientId = adminSeedId('ingredient', ingredient.name)
    if (!data.ingredients.some((entry) => entry.id === ingredientId)) data.ingredients.push({ id: ingredientId, name: ingredient.name, categoryId, baseUnitId: unitId, isDeleted: false })
    return { ingredientId, quantity: ingredient.quantity, unitId }
  })
  const override: AdminRecipe = {
    id: recipe.id, title: recipe.name, author: 'CocinAPP', description: recipe.description,
    category: recipe.category, mealShift: recipe.mealShift ?? recipe.category, minutes: recipe.minutes,
    portions: recipe.portions, difficulty: recipe.difficulty, calories: recipe.calories ?? 0,
    dietaryTags: recipe.dietaryTags ?? [], featured: recipe.featured ?? false, ingredients,
    steps: [...recipe.steps], stepMeta: recipe.stepMeta?.map((entry) => ({
      ...entry,
      ingredientIds: entry.stepIngredients?.flatMap((stepIngredient) => {
        const ingredient = data.ingredients.find((item) => normalizePantryName(item.name) === normalizePantryName(stepIngredient.name))
        return ingredient ? [ingredient.id] : []
      }),
      utensils: entry.utensils ? [...entry.utensils] : undefined,
    })) ?? [],
    status: 'published', isDeleted: false, symbol: recipe.symbol, color: recipe.color,
    image: recipe.image, imageAlt: recipe.imageAlt,
    createdAt: now.toISOString(), updatedAt: now.toISOString(),
  }
  data.recipes.push(override)
  saveAdminData(data)
  return override
}

export function createRecipe(recipe: Omit<AdminRecipe, 'id' | 'isDeleted' | 'createdAt' | 'updatedAt'>, now = new Date()): string {
  const data = getAdminData()
  const validRecipe = validateRecipe(recipe, data.recipes, data.ingredients, data.units)
  const id = crypto.randomUUID()
  data.recipes.push({ ...validRecipe, id, isDeleted: false, createdAt: now.toISOString(), updatedAt: now.toISOString() })
  saveAdminData(data)
  return id
}

export function updateRecipe(id: string, recipe: Omit<AdminRecipe, 'id' | 'isDeleted' | 'createdAt' | 'updatedAt'>, now = new Date()): void {
  const data = getAdminData()
  const validRecipe = validateRecipe(recipe, data.recipes, data.ingredients, data.units, id)
  const index = data.recipes.findIndex(r => r.id === id)
  if (index !== -1) {
    data.recipes[index] = { ...validRecipe, id, isDeleted: data.recipes[index].isDeleted, createdAt: data.recipes[index].createdAt ?? now.toISOString(), updatedAt: now.toISOString() }
    saveAdminData(data)
  }
}

export function deleteRecipe(id: string): void {
  const data = getAdminData()
  const index = data.recipes.findIndex(r => r.id === id)
  if (index !== -1) {
    if (hasAdminReferences('recipe', id) || recipeSeed.some((recipe) => recipe.id === id)) {
      data.recipes[index].isDeleted = true
    } else {
      data.recipes.splice(index, 1)
    }
    saveAdminData(data)
  }
}

function ensureManagedRecipe(id: string, now = new Date()): AdminRecipe {
  const existing = getAdminData().recipes.find((recipe) => recipe.id === id)
  if (existing) return existing
  const seeded = recipeSeed.find((recipe) => recipe.id === id)
  if (!seeded) throw new Error('La receta no existe.')
  return createSeedRecipeOverride(seeded, now)
}

export function setRecipeActive(id: string, active: boolean, now = new Date()): void {
  const managed = ensureManagedRecipe(id, now)
  const data = getAdminData()
  const recipe = data.recipes.find((entry) => entry.id === managed.id)
  if (!recipe) return
  recipe.isDeleted = !active
  if (active && recipe.status === 'draft') recipe.status = 'published'
  recipe.updatedAt = now.toISOString()
  saveAdminData(data)
}

export function setRecipeFeatured(id: string, featured: boolean, now = new Date()): void {
  const managed = ensureManagedRecipe(id, now)
  const data = getAdminData()
  const recipe = data.recipes.find((entry) => entry.id === managed.id)
  if (!recipe) return
  recipe.featured = featured
  recipe.updatedAt = now.toISOString()
  saveAdminData(data)
}

export function duplicateRecipe(id: string, now = new Date()): string {
  const source = ensureManagedRecipe(id, now)
  const { id: _id, isDeleted: _isDeleted, createdAt: _createdAt, updatedAt: _updatedAt, ...copy } = source
  const titles = getAdminData().recipes.map((recipe) => normalizePantryName(recipe.title))
  let title = `Copia de ${source.title}`
  let sequence = 2
  while (titles.includes(normalizePantryName(title))) title = `Copia ${sequence++} de ${source.title}`
  return createRecipe({ ...copy, title, status: 'draft', featured: false, ingredients: source.ingredients.map((entry) => ({ ...entry })), steps: [...source.steps], stepMeta: source.stepMeta?.map((entry) => ({ ...entry })) }, now)
}
