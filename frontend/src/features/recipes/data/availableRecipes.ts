import { getAdminData } from '../../admin/data/localAdminStore'
import type { AdminRecipe } from '../../admin/domain/adminModels'
import type { Recipe } from '../domain/Recipe'
import { mergeRecipeSeed, recipeSeed } from './recipeSeed'

function fromAdminRecipe(recipe: AdminRecipe): Recipe {
  const data = getAdminData()
  const seededRecipe = recipeSeed.find((entry) => entry.id === recipe.id)
  const ingredients = recipe.ingredients.flatMap((entry) => {
    const ingredient = data.ingredients.find((item) => item.id === entry.ingredientId)
    const unit = data.units.find((item) => item.id === entry.unitId)
    return ingredient && unit ? [{ name: ingredient.name, quantity: entry.quantity, unit: unit.abbreviation }] : []
  })
  return {
    id: recipe.id,
    name: recipe.title,
    description: recipe.description,
    category: recipe.mealShift || recipe.category,
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
    dietaryTags: recipe.dietaryTags,
    featured: recipe.featured,
    ingredients,
  }
}

export function getAvailableRecipes(): Recipe[] {
  const data = getAdminData()
  return getKnownRecipes().filter((recipe) => {
    const record = data.recipes.find((entry) => entry.id === recipe.id)
    if (!record) return true
    if (record.isDeleted || record.status !== 'published') return false
    return record.steps.length > 0 && record.ingredients.length > 0 && record.ingredients.every((entry) => {
      const ingredient = data.ingredients.find((item) => item.id === entry.ingredientId && !item.isDeleted)
      const unit = data.units.find((item) => item.id === entry.unitId && !item.isDeleted)
      const base = ingredient && data.units.find((item) => item.id === ingredient.baseUnitId && !item.isDeleted)
      return Boolean(ingredient && unit && base && unit.dimension === base.dimension)
    })
  })
}

export function getKnownRecipes(): Recipe[] {
  const data = getAdminData()
  return mergeRecipeSeed(recipeSeed, data.recipes.map(fromAdminRecipe))
}

export function getRecipeById(id: string, includeInactive = false): Recipe | undefined {
  if (!includeInactive) return getAvailableRecipes().find((recipe) => recipe.id === id)
  const record = getAdminData().recipes.find((recipe) => recipe.id === id)
  if (record) return fromAdminRecipe(record)
  return recipeSeed.find((recipe) => recipe.id === id)
}
