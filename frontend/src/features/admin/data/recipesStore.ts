import { getAdminData, saveAdminData } from './localAdminStore'
import type { AdminRecipe } from '../domain/adminModels'
import { hasAdminReferences } from './adminReferences'
import { validateRecipe } from '../domain/adminValidation'
import type { Recipe } from '../../recipes/domain/Recipe'
import { normalizePantryName } from '../../pantry/domain/pantry'
import { recipeSeed } from '../../recipes/data/recipeSeed'

const seedUnitDefinitions = {
  g: { name: 'Gramo', dimension: 'masa' as const }, kg: { name: 'Kilogramo', dimension: 'masa' as const },
  ml: { name: 'Mililitro', dimension: 'volumen' as const }, l: { name: 'Litro', dimension: 'volumen' as const },
  u: { name: 'Unidad', dimension: 'conteo' as const },
}

function seedId(prefix: string, value: string): string {
  return `seed-${prefix}-${normalizePantryName(value).replace(/[^a-z0-9]+/g, '-').replace(/(^-|-$)/g, '')}`
}

export function createSeedRecipeOverride(recipe: Recipe): AdminRecipe {
  const data = getAdminData()
  const existing = data.recipes.find((entry) => entry.id === recipe.id)
  if (existing) return existing
  const categoryId = seedId('category', 'Otros')
  if (!data.categories.some((entry) => entry.id === categoryId)) data.categories.push({ id: categoryId, name: 'Otros', isDeleted: false })
  const ensureUnit = (abbreviation: string) => {
    const definition = seedUnitDefinitions[abbreviation as keyof typeof seedUnitDefinitions] ?? { name: abbreviation, dimension: 'conteo' as const }
    const id = seedId('unit', abbreviation)
    if (!data.units.some((entry) => entry.id === id)) {
      const baseAbbreviation = definition.dimension === 'masa' ? 'g' : definition.dimension === 'volumen' ? 'ml' : 'u'
      const baseUnitId = seedId('unit', baseAbbreviation)
      if (baseAbbreviation !== abbreviation) ensureUnit(baseAbbreviation)
      data.units.push({ id, name: definition.name, abbreviation, dimension: definition.dimension,
        baseUnitId: baseAbbreviation === abbreviation ? undefined : baseUnitId,
        equivalenceMultiplier: abbreviation === 'kg' || abbreviation === 'l' ? 1000 : undefined, isDeleted: false })
    }
    return id
  }
  const ingredients = recipe.ingredients.map((ingredient) => {
    const unitId = ensureUnit(ingredient.unit)
    const ingredientId = seedId('ingredient', ingredient.name)
    if (!data.ingredients.some((entry) => entry.id === ingredientId)) data.ingredients.push({ id: ingredientId, name: ingredient.name, categoryId, baseUnitId: unitId, isDeleted: false })
    return { ingredientId, quantity: ingredient.quantity, unitId }
  })
  const override: AdminRecipe = {
    id: recipe.id, title: recipe.name, author: 'CocinAPP', description: recipe.description,
    category: recipe.category, mealShift: recipe.mealShift ?? recipe.category, minutes: recipe.minutes,
    portions: recipe.portions, difficulty: recipe.difficulty, calories: recipe.calories ?? 0,
    dietaryTags: recipe.dietaryTags ?? [], featured: recipe.featured ?? false, ingredients,
    steps: [...recipe.steps], stepMeta: recipe.stepMeta?.map((entry) => ({ ...entry })) ?? [],
    status: 'published', isDeleted: false, symbol: recipe.symbol, color: recipe.color,
  }
  data.recipes.push(override)
  saveAdminData(data)
  return override
}

export function createRecipe(recipe: Omit<AdminRecipe, 'id' | 'isDeleted'>): string {
  const data = getAdminData()
  const validRecipe = validateRecipe(recipe, data.recipes, data.ingredients, data.units)
  const id = crypto.randomUUID()
  data.recipes.push({ ...validRecipe, id, isDeleted: false })
  saveAdminData(data)
  return id
}

export function updateRecipe(id: string, recipe: Omit<AdminRecipe, 'id' | 'isDeleted'>): void {
  const data = getAdminData()
  const validRecipe = validateRecipe(recipe, data.recipes, data.ingredients, data.units, id)
  const index = data.recipes.findIndex(r => r.id === id)
  if (index !== -1) {
    data.recipes[index] = { ...validRecipe, id, isDeleted: data.recipes[index].isDeleted }
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
