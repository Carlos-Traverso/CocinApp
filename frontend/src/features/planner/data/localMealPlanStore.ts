import { daysUntilExpiry } from '../../pantry/domain/pantry'
import { getRecipeById } from '../../recipes/data/availableRecipes'
import { personalStorage } from '../../auth/data/personalStorage'
import type { PlannedMeal } from '../domain/planner'

const key = 'cocinapp.planner.v1'
interface StorageLike { getItem(key: string): string | null; setItem(key: string, value: string): void }

function isPlannedMeal(value: unknown): value is PlannedMeal {
  if (!value || typeof value !== 'object') return false
  const entry = value as Record<string, unknown>
  return typeof entry.date === 'string' && daysUntilExpiry(entry.date) !== null
    && (entry.meal === 'Almuerzo' || entry.meal === 'Cena')
    && Boolean(getRecipeById(String(entry.recipeId), true))
}

export function readMealPlan(storage: StorageLike = personalStorage): PlannedMeal[] {
  try {
    const value: unknown = JSON.parse(storage.getItem(key) ?? '[]')
    if (!Array.isArray(value)) return []
    const unique = new Map<string, PlannedMeal>()
    for (const item of value) if (isPlannedMeal(item)) unique.set(`${item.date}:${item.meal}`, item)
    return [...unique.values()]
  } catch { return [] }
}

export function writeMealPlan(plan: PlannedMeal[], storage: StorageLike = personalStorage): void {
  storage.setItem(key, JSON.stringify(plan))
}
