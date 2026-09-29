import { getRecipeById } from '../../recipes/data/availableRecipes'
import { personalStorage } from '../../auth/data/personalStorage'
import type { CookingSession, PreparationEvent } from '../domain/cooking'
import type { Recipe } from '../../recipes/domain/Recipe'
import { readPantryItems, writePantryItems } from '../../pantry/data/localPantryStore'
import { deductIngredients, recordPreparation } from '../domain/cooking'

const progressKey = 'cocinapp.cooking-progress.v1'
const historyKey = 'cocinapp.cooking-history.v1'
interface StorageLike { getItem(key: string): string | null; setItem(key: string, value: string): void }

function isDate(value: unknown): value is string {
  return typeof value === 'string' && !Number.isNaN(Date.parse(value))
}

function isSession(value: unknown): value is CookingSession {
  if (!value || typeof value !== 'object') return false
  const session = value as Record<string, unknown>
  const recipe = getRecipeById(String(session.recipeId))
  return Boolean(recipe)
    && Number.isInteger(session.stepIndex) && (session.stepIndex as number) >= 0 && (session.stepIndex as number) < recipe!.steps.length
    && Array.isArray(session.completed) && session.completed.every((index: unknown) => Number.isInteger(index) && (index as number) >= 0 && (index as number) < recipe!.steps.length)
    && typeof session.portions === 'number' && Number.isInteger(session.portions) && session.portions >= 1 && session.portions <= 20
    && isDate(session.startedAt)
    && (session.timer === undefined || (typeof session.timer === 'object' && session.timer !== null
      && Number.isInteger((session.timer as Record<string, unknown>).stepIndex)
      && (session.timer as { stepIndex: number }).stepIndex === session.stepIndex
      && typeof (session.timer as Record<string, unknown>).remainingMs === 'number'
      && Number.isFinite((session.timer as { remainingMs: number }).remainingMs)
      && (session.timer as { remainingMs: number }).remainingMs >= 0
      && ((session.timer as { deadlineAt?: unknown }).deadlineAt === undefined || (typeof (session.timer as { deadlineAt?: unknown }).deadlineAt === 'number' && Number.isFinite((session.timer as { deadlineAt: number }).deadlineAt)))))
}

function isPreparation(value: unknown): value is PreparationEvent {
  if (!value || typeof value !== 'object') return false
  const event = value as Record<string, unknown>
  return typeof event.id === 'string' && event.id.length > 0
    && Boolean(getRecipeById(String(event.recipeId), true))
    && isDate(event.cookedAt)
    && typeof event.portions === 'number' && Number.isInteger(event.portions) && event.portions >= 1 && event.portions <= 20
    && (event.sessionStartedAt === undefined || isDate(event.sessionStartedAt))
}

function readSessions(storage: StorageLike): CookingSession[] {
  try {
    const value: unknown = JSON.parse(storage.getItem(progressKey) ?? '[]')
    return Array.isArray(value) ? value.filter(isSession) : []
  } catch { return [] }
}

export function readCookingSession(recipeId: string, storage: StorageLike = personalStorage): CookingSession | null {
  return readSessions(storage).find((session) => session.recipeId === recipeId) ?? null
}

export function saveCookingSession(session: CookingSession, storage: StorageLike = personalStorage): void {
  storage.setItem(progressKey, JSON.stringify([...readSessions(storage).filter((item) => item.recipeId !== session.recipeId), session]))
}

export function clearCookingSession(recipeId: string, storage: StorageLike = personalStorage): void {
  storage.setItem(progressKey, JSON.stringify(readSessions(storage).filter((item) => item.recipeId !== recipeId)))
}

export function readHistory(storage: StorageLike = personalStorage): PreparationEvent[] {
  try {
    const value: unknown = JSON.parse(storage.getItem(historyKey) ?? '[]')
    if (!Array.isArray(value)) return []
    const ids = new Set<string>()
    return value.filter((event): event is PreparationEvent => {
      if (!isPreparation(event) || ids.has(event.id)) return false
      ids.add(event.id)
      return true
    })
  } catch { return [] }
}

export function writeHistory(history: PreparationEvent[], storage: StorageLike = personalStorage): void {
  storage.setItem(historyKey, JSON.stringify(history))
}

export function finalizeCookingSession(recipe: Recipe, session: CookingSession, discount: boolean, storage: StorageLike = personalStorage, now = new Date()): PreparationEvent[] {
  const history = recordPreparation(readHistory(storage), session, now)
  writeHistory(history, storage)
  if (discount) writePantryItems(deductIngredients(readPantryItems(storage), recipe, session.portions, now), storage)
  clearCookingSession(recipe.id, storage)
  return history
}
