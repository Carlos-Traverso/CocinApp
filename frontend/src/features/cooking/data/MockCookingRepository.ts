import { checkCookingStock, finishCookingSession, getCookingHistory, getCookingSession, persistCookingSession, persistCookingHistory, removeCookingHistoryEntry, clearCookingHistory } from './localCookingStore'
import type { CookingRepository } from './CookingRepository'
import { isSupabaseConfigured } from '../../../shared/data/supabaseClient'
import { loadPersonalData, savePersonalData } from '../../../shared/data/personalDataRepository'
import type { CookingSession, PreparationEvent } from '../domain/cooking'

async function loadCookingData(key: 'cooking_progress' | 'cooking_history'): Promise<unknown | null> {
  if (!isSupabaseConfigured) return null
  return loadPersonalData(key)
}

async function loadSession(recipeId: string): Promise<CookingSession | null> {
  const remote = await loadCookingData('cooking_progress')
  if (remote !== null) {
    const sessions = Array.isArray(remote) ? remote as CookingSession[] : []
    const session = sessions.find((entry) => entry.recipeId === recipeId) ?? null
    for (const session of sessions) await persistCookingSession(session)
    return session
  }
  return getCookingSession(recipeId)
}

async function saveSession(session: CookingSession): Promise<void> {
  const current = await loadCookingData('cooking_progress')
  const sessions = Array.isArray(current) ? current as CookingSession[] : []
  const next = [...sessions.filter((item) => item.recipeId !== session.recipeId), session]
  await savePersonalData('cooking_progress', next)
  await persistCookingSession(session)
}

async function loadHistory(): Promise<PreparationEvent[]> {
  const remote = await loadCookingData('cooking_history')
  if (remote !== null) {
    const history = Array.isArray(remote) ? remote as PreparationEvent[] : []
    await persistCookingHistory(history)
    return getCookingHistory()
  }
  return getCookingHistory()
}

async function saveHistory(history: PreparationEvent[]): Promise<void> {
  await savePersonalData('cooking_history', history)
  await persistCookingHistory(history)
}

export const mockCookingRepository: CookingRepository = {
  async getSession(recipeId) { return isSupabaseConfigured ? loadSession(recipeId) : getCookingSession(recipeId) },
  async saveSession(session) { if (!isSupabaseConfigured) return persistCookingSession(session); await saveSession(session) },
  async getHistory() { return isSupabaseConfigured ? loadHistory() : getCookingHistory() },
  async removeHistoryEntry(eventId) {
    if (!isSupabaseConfigured) return removeCookingHistoryEntry(eventId)
    await saveHistory((await loadHistory()).filter((event) => event.id !== eventId))
  },
  async clearHistory() { if (!isSupabaseConfigured) return clearCookingHistory(); await saveHistory([]) },
  checkStock: checkCookingStock,
  async finalize(recipe, session, discount) {
    const result = await finishCookingSession(recipe, session, discount)
    if (isSupabaseConfigured) {
      const history = await loadHistory()
      const updated = [...history.filter((event) => !result.history.some((saved) => saved.id === event.id)), ...result.history]
      await saveHistory(updated)
      const sessions = await loadCookingData('cooking_progress')
      const nextSessions = (Array.isArray(sessions) ? sessions as CookingSession[] : []).filter((entry) => entry.recipeId !== session.recipeId)
      await savePersonalData('cooking_progress', nextSessions)
    }
    return result
  },
}
