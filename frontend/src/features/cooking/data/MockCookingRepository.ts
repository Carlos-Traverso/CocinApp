import { checkCookingStock, clearCookingHistory, finishCookingSession, getCookingHistory, getCookingSession, persistCookingSession, removeCookingHistoryEntry } from './localCookingStore'
import type { CookingRepository } from './CookingRepository'

export const mockCookingRepository: CookingRepository = {
  getSession: getCookingSession,
  saveSession: persistCookingSession,
  getHistory: getCookingHistory,
  removeHistoryEntry: removeCookingHistoryEntry,
  clearHistory: clearCookingHistory,
  checkStock: checkCookingStock,
  finalize: finishCookingSession,
}
