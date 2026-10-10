import { getRecipeById } from '../../recipes/data/availableRecipes'
import { sampleRecipes } from '../../../mocks/recipes'
import { personalStorage } from '../../auth/data/personalStorage'
import { meals, type Meal, type PlannedMeal } from '../domain/planner'

const key = 'cocinapp.planner.v1'
interface StorageLike { getItem(key: string): string | null; setItem(key: string, value: string): void }

function recipeById(id: string) {
  if (typeof localStorage === 'undefined') return sampleRecipes.find((recipe) => recipe.id === id)
  try { return getRecipeById(id, true) } catch { return sampleRecipes.find((recipe) => recipe.id === id) }
}

function isPlannedMeal(value: unknown): value is PlannedMeal {
  if (!value || typeof value !== 'object') return false
  const entry = value as Record<string, unknown>
  if (typeof entry.date !== 'string' || !/^\d{4}-\d{2}-\d{2}$/.test(entry.date)) return false
  const [year, month, day] = entry.date.split('-').map(Number)
  const parsed = new Date(year, month - 1, day)
  return parsed.getFullYear() === year && parsed.getMonth() === month - 1 && parsed.getDate() === day
    && meals.includes(entry.meal as Meal)
    && Boolean(recipeById(String(entry.recipeId)))
}

export function readMealPlan(storage: StorageLike = personalStorage): PlannedMeal[] {
  try {
    const value: unknown = JSON.parse(storage.getItem(key) ?? '[]')
    if (!Array.isArray(value)) return []
    const unique = new Map<string, PlannedMeal>()
    for (const item of value) if (isPlannedMeal(item)) {
      const recipePortions = recipeById(item.recipeId)?.portions ?? 2
      const portions = Number.isFinite(item.portions) && item.portions >= 1 ? Math.min(20, Math.round(item.portions)) : recipePortions
      unique.set(`${item.date}:${item.meal}`, { ...item, portions })
    }
    return [...unique.values()]
  } catch { return [] }
}

export function writeMealPlan(plan: PlannedMeal[], storage: StorageLike = personalStorage): void {
  storage.setItem(key, JSON.stringify(plan))
}
