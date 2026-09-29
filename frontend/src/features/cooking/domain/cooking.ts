import { daysUntilExpiry, normalizePantryName, type PantryItem } from '../../pantry/domain/pantry'
import type { Recipe } from '../../recipes/domain/Recipe'

export const cookingCompletionPath = '/recipes'

export interface CookingSession {
  recipeId: string
  stepIndex: number
  completed: number[]
  portions: number
  startedAt: string
  timer?: { stepIndex: number; remainingMs: number; deadlineAt?: number }
}

export interface PreparationEvent {
  id: string
  recipeId: string
  cookedAt: string
  portions: number
  sessionStartedAt?: string
}

export function createSession(recipe: Recipe, now = new Date()): CookingSession {
  return { recipeId: recipe.id, stepIndex: 0, completed: [], portions: recipe.portions, startedAt: now.toISOString() }
}

export function moveStep(session: CookingSession, delta: number, stepCount: number): CookingSession {
  return { ...session, stepIndex: Math.max(0, Math.min(stepCount - 1, session.stepIndex + delta)), timer: undefined }
}

export function completeStep(session: CookingSession, index: number, stepCount: number): CookingSession {
  if (!Number.isInteger(index) || index < 0 || index >= stepCount) return session
  const completed = session.completed.includes(index) ? session.completed : [...session.completed, index].sort((a, b) => a - b)
  return { ...session, completed }
}

export function advanceStep(session: CookingSession, stepCount: number): CookingSession {
  const completed = completeStep(session, session.stepIndex, stepCount)
  return { ...completed, stepIndex: Math.min(stepCount - 1, session.stepIndex + 1), timer: undefined }
}

export function remainingTimerMs(timer: NonNullable<CookingSession['timer']>, now = Date.now()): number {
  return Math.max(0, timer.deadlineAt === undefined ? timer.remainingMs : timer.deadlineAt - now)
}

export function recordPreparation(history: PreparationEvent[], session: CookingSession, now = new Date()): PreparationEvent[] {
  if (history.some((event) => event.recipeId === session.recipeId && event.sessionStartedAt === session.startedAt)) return history
  return [{ id: crypto.randomUUID(), recipeId: session.recipeId, cookedAt: now.toISOString(), portions: session.portions, sessionStartedAt: session.startedAt }, ...history]
}

export function scaleIngredients(recipe: Recipe, portions: number): Recipe['ingredients'] {
  return recipe.ingredients.map((item) => ({ ...item, quantity: Math.round(item.quantity * portions / recipe.portions * 100) / 100 }))
}

export function deductIngredients(pantry: PantryItem[], recipe: Recipe, portions: number, today = new Date()): PantryItem[] {
  const updated = pantry.map((item) => ({ ...item }))
  for (const ingredient of scaleIngredients(recipe, portions)) {
    let needed = ingredient.quantity
    const matches = updated.filter((item) => item.unit === ingredient.unit
      && normalizePantryName(item.name) === normalizePantryName(ingredient.name)
      && (!item.expiry || (daysUntilExpiry(item.expiry, today) ?? -1) >= 0))
      .sort((a, b) => (a.expiry || '9999-12-31').localeCompare(b.expiry || '9999-12-31'))
    for (const item of matches) {
      const used = Math.min(needed, item.quantity)
      item.quantity = Math.round((item.quantity - used) * 100) / 100
      needed = Math.round((needed - used) * 100) / 100
      if (needed <= 0) break
    }
  }
  return updated
}
