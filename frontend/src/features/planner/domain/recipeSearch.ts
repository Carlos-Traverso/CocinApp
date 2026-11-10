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

export function suggestedPlanRecipes(recipes: Recipe[], meal: Meal, seed = 0): Recipe[] {
  const candidates = recipesForMeal(recipes, meal)
  let state = Math.floor(seed * 0xffffffff) >>> 0
  for (let index = candidates.length - 1; index > 0; index--) {
    state = (Math.imul(state, 1664525) + 1013904223) >>> 0
    const selected = Math.floor(state / 0x100000000 * (index + 1))
    ;[candidates[index], candidates[selected]] = [candidates[selected]!, candidates[index]!]
  }
  return candidates.slice(0, 6)
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
