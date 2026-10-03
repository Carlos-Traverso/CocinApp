import { normalizePantryName } from '../../pantry/domain/pantry'
import type { Recipe } from '../../recipes/domain/Recipe'

export type PlanRecipeKeyAction = 'next' | 'previous' | 'select' | 'close'

export function searchPlanRecipes(recipes: Recipe[], query: string): Recipe[] {
  const normalized = normalizePantryName(query)
  return normalized ? recipes.filter((recipe) => normalizePantryName(recipe.name).includes(normalized)) : []
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
