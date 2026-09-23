import { daysUntilExpiry, normalizePantryName, type PantryItem } from '../../pantry/domain/pantry'
import type { Recipe } from './Recipe'

export interface RecipeFilters {
  search: string
  category: string
  maxMinutes: number | null
  difficulty: Recipe['difficulty'] | ''
  pantryOnly: boolean
}

export function getIngredientAvailability(recipe: Recipe, pantry: PantryItem[], today = new Date()) {
  const available: Recipe['ingredients'] = []
  const missing: Recipe['ingredients'] = []
  for (const ingredient of recipe.ingredients) {
    const quantity = pantry.filter((item) => item.unit === ingredient.unit
      && normalizePantryName(item.name) === normalizePantryName(ingredient.name)
      && (!item.expiry || (daysUntilExpiry(item.expiry, today) ?? -1) >= 0))
      .reduce((sum, item) => sum + item.quantity, 0)
    ;(quantity >= ingredient.quantity ? available : missing).push(ingredient)
  }
  return { available, missing }
}

export function filterRecipes(recipes: Recipe[], filters: RecipeFilters, pantry: PantryItem[], today = new Date()): Recipe[] {
  const search = normalizePantryName(filters.search)
  return recipes.filter((recipe) => {
    if (search && ![recipe.name, recipe.description, ...recipe.ingredients.map((item) => item.name)]
      .some((value) => normalizePantryName(value).includes(search))) return false
    if (filters.category && recipe.category !== filters.category) return false
    if (filters.maxMinutes !== null && recipe.minutes > filters.maxMinutes) return false
    if (filters.difficulty && recipe.difficulty !== filters.difficulty) return false
    return !filters.pantryOnly || getIngredientAvailability(recipe, pantry, today).missing.length === 0
  })
}
