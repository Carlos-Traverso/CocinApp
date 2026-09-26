import { sampleRecipes } from '../../../mocks/recipes'
import { getAdminData } from '../../admin/data/localAdminStore'
import type { AdminRecipe } from '../../admin/domain/adminModels'
import type { Recipe } from '../domain/Recipe'

function fromAdminRecipe(recipe: AdminRecipe): Recipe {
  const data = getAdminData()
  return {
    id: recipe.id,
    name: recipe.title,
    description: recipe.description,
    category: recipe.mealShift || recipe.category,
    minutes: recipe.minutes,
    portions: recipe.portions,
    difficulty: recipe.difficulty,
    steps: recipe.steps,
    stepMeta: recipe.stepMeta,
    symbol: recipe.symbol || recipe.title.slice(0, 1).toLocaleUpperCase('es'),
    color: recipe.color || 'green',
    calories: recipe.calories,
    mealShift: recipe.mealShift,
    dietaryTags: recipe.dietaryTags,
    featured: recipe.featured,
    ingredients: recipe.ingredients.flatMap((entry) => {
      const ingredient = data.ingredients.find((item) => item.id === entry.ingredientId)
      const unit = data.units.find((item) => item.id === entry.unitId)
      return ingredient && unit ? [{ name: ingredient.name, quantity: entry.quantity, unit: unit.abbreviation }] : []
    }),
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
  const combined = new Map<string, Recipe>(sampleRecipes.map((recipe): [string, Recipe] => [recipe.id, recipe]))
  for (const recipe of data.recipes) combined.set(recipe.id, fromAdminRecipe(recipe))
  return [...combined.values()]
}

export function getRecipeById(id: string, includeInactive = false): Recipe | undefined {
  if (!includeInactive) return getAvailableRecipes().find((recipe) => recipe.id === id)
  const record = getAdminData().recipes.find((recipe) => recipe.id === id)
  if (record) return fromAdminRecipe(record)
  return sampleRecipes.find((recipe) => recipe.id === id)
}
