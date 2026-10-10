import { daysUntilExpiry, normalizePantryName, type PantryItem } from '../../pantry/domain/pantry'
import type { Recipe, RecipeStepMeta } from '../../recipes/domain/Recipe'
import { getIngredientDeficits } from '../../recipes/domain/recipeRules'
import { convertQuantity, quantityDeficit, roundQuantity } from '../../../shared/domain/units'
import type { AdminUnit } from '../../admin/domain/adminModels'

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

export function startStepTimer(session: CookingSession, durationMs: number, now = Date.now()): CookingSession {
  const previous = session.timer?.stepIndex === session.stepIndex ? remainingTimerMs(session.timer, now) : 0
  const remainingMs = previous > 0 ? previous : durationMs
  return { ...session, timer: { stepIndex: session.stepIndex, remainingMs, deadlineAt: now + remainingMs } }
}

export function pauseStepTimer(session: CookingSession, now = Date.now()): CookingSession {
  if (!session.timer || session.timer.stepIndex !== session.stepIndex || session.timer.deadlineAt === undefined) return session
  return { ...session, timer: { stepIndex: session.stepIndex, remainingMs: remainingTimerMs(session.timer, now) } }
}

export function resetStepTimer(session: CookingSession): CookingSession {
  return { ...session, timer: undefined }
}

function stepDuration(meta?: RecipeStepMeta): number {
  return meta?.durationMinutes ?? meta?.minutes ?? 0
}

export function getStepGuidance(recipe: Recipe, stepIndex: number, portions: number) {
  const meta = recipe.stepMeta?.[stepIndex]
  const scale = portions / recipe.portions
  return {
    durationMinutes: stepDuration(meta),
    stepIngredients: (meta?.stepIngredients ?? []).map((ingredient) => ({
      ...ingredient, quantity: roundQuantity(ingredient.quantity * scale),
    })),
    utensils: meta?.utensils ?? [],
    tip: meta?.tip,
    warning: meta?.warning,
    temperature: meta?.temperature,
    specialInstructions: meta?.specialInstructions,
    nextStepPreview: recipe.steps[stepIndex + 1],
  }
}

export function remainingRecipeMinutes(recipe: Recipe, stepIndex: number, currentTimerMs?: number): number {
  const currentMinutes = currentTimerMs === undefined
    ? stepDuration(recipe.stepMeta?.[stepIndex])
    : Math.ceil(currentTimerMs / 60_000)
  return currentMinutes + recipe.steps.slice(stepIndex + 1)
    .reduce((total, _, index) => total + stepDuration(recipe.stepMeta?.[stepIndex + index + 1]), 0)
}

export function recordPreparation(history: PreparationEvent[], session: CookingSession, now = new Date()): PreparationEvent[] {
  if (history.some((event) => event.recipeId === session.recipeId && event.sessionStartedAt === session.startedAt)) return history
  return [{ id: crypto.randomUUID(), recipeId: session.recipeId, cookedAt: now.toISOString(), portions: session.portions, sessionStartedAt: session.startedAt }, ...history]
}

export function scaleIngredients(recipe: Recipe, portions: number): Recipe['ingredients'] {
  return recipe.ingredients.map((item) => ({ ...item, quantity: roundQuantity(item.quantity * portions / recipe.portions) }))
}

export function deductIngredients(pantry: PantryItem[], recipe: Recipe, portions: number, today = new Date(), units?: AdminUnit[]): PantryItem[] {
  const updated = pantry.map((item) => ({ ...item }))
  for (const ingredient of scaleIngredients(recipe, portions)) {
    let needed = ingredient.quantity
    const matches = updated.filter((item) => normalizePantryName(item.name) === normalizePantryName(ingredient.name)
      && (!item.expiry || (daysUntilExpiry(item.expiry, today) ?? -1) >= 0))
      .sort((a, b) => (a.expiry || '9999-12-31').localeCompare(b.expiry || '9999-12-31'))
    for (const item of matches) {
      const stockInRecipeUnit = convertQuantity(item.quantity, item.unit, ingredient.unit, units)
      if (stockInRecipeUnit === null) continue
      const usedInRecipeUnit = Math.min(needed, stockInRecipeUnit)
      const usedInStockUnit = convertQuantity(usedInRecipeUnit, ingredient.unit, item.unit, units)
      if (usedInStockUnit === null) continue
      item.quantity = quantityDeficit(item.quantity, usedInStockUnit)
      needed = quantityDeficit(needed, usedInRecipeUnit)
      if (needed <= 0) break
    }
  }
  return updated
}

export function getCookingStockCheck(pantry: PantryItem[], recipe: Recipe, portions: number, today = new Date(), units?: AdminUnit[]) {
  return getIngredientDeficits(recipe, pantry, portions, today, units)
}
