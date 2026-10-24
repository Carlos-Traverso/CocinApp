import { getRecipeById } from '../../recipes/data/availableRecipes'
import { personalStorage } from '../../auth/data/personalStorage'
import type { CookingSession, PreparationEvent } from '../domain/cooking'
import type { Recipe } from '../../recipes/domain/Recipe'
import { readPantryItems, writePantryItems } from '../../pantry/data/localPantryStore'
import { deductIngredients, getCookingStockCheck, recordPreparation } from '../domain/cooking'
import { getAdminData } from '../../admin/data/localAdminStore'

const progressKey = 'cocinapp.cooking-progress.v1'
const historyKey = 'cocinapp.cooking-history.v1'
interface StorageLike { getItem(key: string): string | null; setItem(key: string, value: string): void; removeItem?(key: string): void }

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
  const savedHistory = readHistory(storage)
  if (savedHistory.some((event) => event.recipeId === session.recipeId && event.sessionStartedAt === session.startedAt)) {
    clearCookingSession(recipe.id, storage)
    return savedHistory
  }
  const pantry = discount ? readPantryItems(storage) : []
  const units = getAdminData().units
  const catalog = units.length ? units : undefined
  const deficits = discount ? getCookingStockCheck(pantry, recipe, session.portions, now, catalog).filter((item) => item.missing > 0) : []
  if (deficits.length > 0) {
    throw new Error(`Stock insuficiente: ${deficits.map((item) => `${item.ingredient.name} (${item.missing} ${item.ingredient.unit})`).join(', ')}`)
  }
  const previousHistory = storage.getItem(historyKey)
  const previousPantry = storage.getItem('cocinapp.pantry.v1')
  const previousProgress = storage.getItem(progressKey)
  const history = recordPreparation(readHistory(storage), session, now)
  try {
    writeHistory(history, storage)
    if (discount) writePantryItems(deductIngredients(pantry, recipe, session.portions, now, catalog), storage)
    clearCookingSession(recipe.id, storage)
    return history
  } catch (error) {
    try {
      if (previousHistory === null) storage.removeItem?.(historyKey)
      else storage.setItem(historyKey, previousHistory)
      if (previousPantry === null) storage.removeItem?.('cocinapp.pantry.v1')
      else storage.setItem('cocinapp.pantry.v1', previousPantry)
      if (previousProgress === null) storage.removeItem?.(progressKey)
      else storage.setItem(progressKey, previousProgress)
    } catch { /* Best-effort rollback for storage implementations that reject writes. */ }
    throw error
  }
}

// Promise based mock repository boundary for screens.
export async function getCookingSession(recipeId: string): Promise<CookingSession | null> { return readCookingSession(recipeId) }
export async function persistCookingSession(session: CookingSession): Promise<void> { saveCookingSession(session) }
export async function getCookingHistory(): Promise<PreparationEvent[]> { return readHistory() }
export async function finishCookingSession(recipe: Recipe, session: CookingSession, discount: boolean, now = new Date(), assertCurrent: () => void = () => {}): Promise<{ history: PreparationEvent[]; exhaustedIngredients: string[] }> {
  const savedHistory = readHistory()
  if (savedHistory.some((event) => event.recipeId === session.recipeId && event.sessionStartedAt === session.startedAt)) {
    assertCurrent()
    clearCookingSession(session.recipeId)
    return { history: savedHistory, exhaustedIngredients: [] }
  }
  const stockCheck = discount ? await checkCookingStock(recipe, session.portions, now) : []
  assertCurrent()
  const history = finalizeCookingSession(recipe, session, discount, personalStorage, now)
  const exhaustedIngredients = stockCheck.filter((item) => item.missing === 0 && item.available <= item.required).map((item) => item.ingredient.name)
  return { history, exhaustedIngredients }
}
export async function persistCookingHistory(history: PreparationEvent[]): Promise<void> { writeHistory(history) }
export async function removeCookingHistoryEntry(eventId: string): Promise<void> { writeHistory(readHistory().filter((event) => event.id !== eventId)) }
export async function clearCookingHistory(): Promise<void> { writeHistory([]) }
export async function checkCookingStock(recipe: Recipe, portions: number, now = new Date()) {
  const stock = readPantryItems()
  const units = getAdminData().units
  return getCookingStockCheck(stock, recipe, portions, now, units.length ? units : undefined)
}
