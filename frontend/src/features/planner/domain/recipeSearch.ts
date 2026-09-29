import { normalizePantryName } from '../../pantry/domain/pantry'
import type { Recipe } from '../../recipes/domain/Recipe'

export function searchPlanRecipes(recipes: Recipe[], query: string): Recipe[] {
  const normalized = normalizePantryName(query)
  return normalized ? recipes.filter((recipe) => normalizePantryName(recipe.name).includes(normalized)) : recipes
}
