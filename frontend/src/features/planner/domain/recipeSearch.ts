import { normalizePantryName } from '../../pantry/domain/pantry'
import type { Recipe } from '../../recipes/domain/Recipe'
import { recipeMealShifts } from '../../recipes/domain/recipeRules'
import type { Meal } from './planner'

export type PlanRecipeKeyAction = 'next' | 'previous' | 'select' | 'close'

export function searchPlanRecipes(recipes: Recipe[], query: string): Recipe[] {
  const normalized = normalizePantryName(query)
  return normalized ? recipes.filter((recipe) => normalizePantryName(recipe.name).includes(normalized)) : []
}

export function recipesForMeal(recipes: Recipe[], meal: Meal): Recipe[] {
  return recipes.filter((recipe) => recipeMealShifts(recipe).some((shift) => normalizePantryName(shift) === normalizePantryName(meal)))
}

export function suggestedPlanRecipes(recipes: Recipe[], meal: Meal): Recipe[] {
  return recipesForMeal(recipes, meal)
    .slice()
    .sort((left, right) => left.name.localeCompare(right.name, 'es') || left.id.localeCompare(right.id))
    .slice(0, 4)
}

export function nextPlanRecipeIndex(current: number, resultCount: number, direction: 'next' | 'previous'): number {
  if (resultCount === 0) return 0
  return direction === 'next' ? Math.min(current + 1, resultCount - 1) : Math.max(current - 1, 0)
}

export function planRecipeKeyAction(key: string): PlanRecipeKeyAction | null {
  if (key === 'ArrowDown') return 'next'
  if (key === 'ArrowUp') return 'previous'
  if (key === 'Enter') return 'select'
  if (key === 'Escape') return 'close'
  return null
}
