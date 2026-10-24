import { checkCookingStock, finishCookingSession, getCookingHistory, getCookingSession, persistCookingSession, persistCookingHistory, removeCookingHistoryEntry, clearCookingHistory } from './localCookingStore'
import type { CookingRepository } from './CookingRepository'
import { isSupabaseConfigured } from '../../../shared/data/supabaseClient'
import { loadPersonalData, savePersonalData } from '../../../shared/data/personalDataRepository'
import type { CookingSession, PreparationEvent } from '../domain/cooking'
import { assertPersonalDataSessionCurrent, capturePersonalDataSession, type PersonalDataSession } from '../../../shared/data/personalDataSession'

async function loadCookingData(key: 'cooking_progress' | 'cooking_history', session: PersonalDataSession): Promise<unknown | null> {
  if (!isSupabaseConfigured) return null
  const data = await loadPersonalData(key, session)
  assertPersonalDataSessionCurrent(session)
  return data
}

async function loadSession(recipeId: string, sessionContext: PersonalDataSession): Promise<CookingSession | null> {
  const remote = await loadCookingData('cooking_progress', sessionContext)
  if (remote !== null) {
    const sessions = Array.isArray(remote) ? remote as CookingSession[] : []
    const session = sessions.find((entry) => entry.recipeId === recipeId) ?? null
    for (const savedSession of sessions) {
      assertPersonalDataSessionCurrent(sessionContext)
      await persistCookingSession(savedSession)
      assertPersonalDataSessionCurrent(sessionContext)
    }
    return session
  }
  return getCookingSession(recipeId)
}

async function saveSession(session: CookingSession, sessionContext: PersonalDataSession): Promise<void> {
  const current = await loadCookingData('cooking_progress', sessionContext)
  const sessions = Array.isArray(current) ? current as CookingSession[] : []
  const next = [...sessions.filter((item) => item.recipeId !== session.recipeId), session]
  assertPersonalDataSessionCurrent(sessionContext)
  await savePersonalData('cooking_progress', next, sessionContext)
  assertPersonalDataSessionCurrent(sessionContext)
  await persistCookingSession(session)
  assertPersonalDataSessionCurrent(sessionContext)
}

async function loadHistory(sessionContext: PersonalDataSession): Promise<PreparationEvent[]> {
  const remote = await loadCookingData('cooking_history', sessionContext)
  if (remote !== null) {
    const history = Array.isArray(remote) ? remote as PreparationEvent[] : []
    assertPersonalDataSessionCurrent(sessionContext)
    await persistCookingHistory(history)
    assertPersonalDataSessionCurrent(sessionContext)
    return history
  }
  return getCookingHistory()
}

async function saveHistory(history: PreparationEvent[], sessionContext: PersonalDataSession): Promise<void> {
  await savePersonalData('cooking_history', history, sessionContext)
  assertPersonalDataSessionCurrent(sessionContext)
  await persistCookingHistory(history)
  assertPersonalDataSessionCurrent(sessionContext)
}

export const mockCookingRepository: CookingRepository = {
  async getSession(recipeId) { const context = capturePersonalDataSession(); return isSupabaseConfigured ? loadSession(recipeId, context) : getCookingSession(recipeId) },
  async saveSession(session) { const context = capturePersonalDataSession(); if (!isSupabaseConfigured) return persistCookingSession(session); await saveSession(session, context) },
  async getHistory() { const context = capturePersonalDataSession(); return isSupabaseConfigured ? loadHistory(context) : getCookingHistory() },
  async removeHistoryEntry(eventId) {
    if (!isSupabaseConfigured) return removeCookingHistoryEntry(eventId)
    const context = capturePersonalDataSession()
    const history = await loadHistory(context)
    assertPersonalDataSessionCurrent(context)
    await saveHistory(history.filter((event) => event.id !== eventId), context)
  },
  async clearHistory() { if (!isSupabaseConfigured) return clearCookingHistory(); await saveHistory([], capturePersonalDataSession()) },
  checkStock: checkCookingStock,
  async finalize(recipe, session, discount) {
    const context = capturePersonalDataSession()
    const result = await finishCookingSession(recipe, session, discount, new Date(), () => assertPersonalDataSessionCurrent(context))
    assertPersonalDataSessionCurrent(context)
    if (isSupabaseConfigured) {
      const history = await loadHistory(context)
      const updated = [...history.filter((event) => !result.history.some((saved) => saved.id === event.id)), ...result.history]
      await saveHistory(updated, context)
      const sessions = await loadCookingData('cooking_progress', context)
      const nextSessions = (Array.isArray(sessions) ? sessions as CookingSession[] : []).filter((entry) => entry.recipeId !== session.recipeId)
      await savePersonalData('cooking_progress', nextSessions, context)
    }
    return result
  },
}
