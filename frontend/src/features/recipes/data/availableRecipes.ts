import { getAdminData, resolveIngredientCategory, type AdminStorageData } from '../../admin/data/localAdminStore'
import type { AdminRecipe } from '../../admin/domain/adminModels'
import type { Recipe } from '../domain/Recipe'
import { mergeRecipeSeed, recipeSeed } from './recipeSeed'

function fromAdminRecipe(recipe: AdminRecipe, data: AdminStorageData, seededRecipe = recipeSeed.find((entry) => entry.id === recipe.id)): Recipe {
  const ingredients = recipe.ingredients.flatMap((entry) => {
    const ingredient = data.ingredients.find((item) => item.id === entry.ingredientId)
    const unit = data.units.find((item) => item.id === entry.unitId)
    return ingredient && unit ? [{ name: ingredient.name, quantity: entry.quantity, unit: unit.abbreviation, category: resolveIngredientCategory(ingredient.name, data) }] : []
  })
  return {
    id: recipe.id,
    name: recipe.title,
    description: recipe.description,
    category: recipe.mealShifts?.[0] || recipe.mealShift || recipe.category,
    minutes: recipe.minutes,
    portions: recipe.portions,
    difficulty: recipe.difficulty,
    steps: recipe.steps,
    stepMeta: recipe.stepMeta?.map((meta) => ({
      ...(meta.minutes !== undefined ? { minutes: meta.minutes } : {}),
      ...(meta.durationMinutes !== undefined ? { durationMinutes: meta.durationMinutes } : {}),
      ...(meta.ingredientIds?.length ? { stepIngredients: meta.ingredientIds.flatMap((ingredientId) => {
        const recipeIngredient = recipe.ingredients.find((entry) => entry.ingredientId === ingredientId)
        const ingredient = data.ingredients.find((entry) => entry.id === ingredientId)
        const unit = data.units.find((entry) => entry.id === recipeIngredient?.unitId)
        return recipeIngredient && ingredient && unit ? [{ name: ingredient.name, quantity: recipeIngredient.quantity, unit: unit.abbreviation }] : []
      }) } : {}),
      ...(meta.utensils?.length ? { utensils: [...meta.utensils] } : {}),
      ...(meta.tip ? { tip: meta.tip } : {}),
      ...(meta.warning ? { warning: meta.warning } : {}),
      ...(meta.temperature ? { temperature: meta.temperature } : {}),
      ...(meta.specialInstructions ? { specialInstructions: meta.specialInstructions } : {}),
    })),
    symbol: recipe.symbol || recipe.title.slice(0, 1).toLocaleUpperCase('es'),
    color: recipe.color || 'green',
    image: recipe.image ?? seededRecipe?.image,
    imageAlt: recipe.imageAlt ?? seededRecipe?.imageAlt,
    calories: recipe.calories,
    mealShift: recipe.mealShift,
    ...(recipe.mealShifts !== undefined ? { mealShifts: [...recipe.mealShifts] } : {}),
    dietaryTags: recipe.dietaryTags,
    featured: recipe.featured,
    ingredients,
  }
}

function isAvailable(record: AdminRecipe, data: AdminStorageData): boolean {
  if (!record.active || record.isDeleted || record.status !== 'published') return false
  return record.steps.length > 0 && record.ingredients.length > 0 && record.ingredients.every((entry) => {
    const ingredient = data.ingredients.find((item) => item.id === entry.ingredientId && item.active && !item.isDeleted)
    const unit = data.units.find((item) => item.id === entry.unitId && item.active && !item.isDeleted)
    const base = ingredient && data.units.find((item) => item.id === ingredient.baseUnitId && item.active && !item.isDeleted)
    return Boolean(ingredient && unit && base && unit.dimension === base.dimension)
  })
}

function withIngredientCategories(recipe: Recipe, data: AdminStorageData): Recipe {
  return {
    ...recipe,
    ingredients: recipe.ingredients.map((ingredient) => ({ ...ingredient, category: ingredient.category ?? resolveIngredientCategory(ingredient.name, data) })),
  }
}

export function getAvailableRecipes(data = getAdminData()): Recipe[] {
  const unavailable = new Set(data.recipes.filter((record) => !isAvailable(record, data)).map((record) => record.id))
  return getKnownRecipes(data).filter((recipe) => !unavailable.has(recipe.id))
}

export function getKnownRecipes(data = getAdminData()): Recipe[] {
  return mergeRecipeSeed(recipeSeed, data.recipes.map((recipe) => fromAdminRecipe(recipe, data)))
    .map((recipe) => withIngredientCategories(recipe, data))
}

export function getRecipeById(id: string, includeInactive = false, data = getAdminData()): Recipe | undefined {
  const record = data.recipes.find((recipe) => recipe.id === id)
  const seed = recipeSeed.find((recipe) => recipe.id === id)
  if (record) return includeInactive || isAvailable(record, data) ? fromAdminRecipe(record, data, seed) : undefined
  return seed && withIngredientCategories(seed, data)
}
