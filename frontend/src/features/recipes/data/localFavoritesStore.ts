import { getKnownRecipes } from './availableRecipes'
import { personalStorage } from '../../auth/data/personalStorage'
import type { FavoriteRepository } from './FavoriteRepository'
import { isSupabaseConfigured } from '../../../shared/data/supabaseClient'
import { loadPersonalData, savePersonalData } from '../../../shared/data/personalDataRepository'

const key = 'cocinapp.favorites.v1'
interface StorageLike { getItem(key: string): string | null; setItem(key: string, value: string): void }

export function readFavoriteIds(storage: StorageLike = personalStorage): string[] {
  try {
    const value: unknown = JSON.parse(storage.getItem(key) ?? '[]')
    if (!Array.isArray(value)) return []
    const known = new Set(getKnownRecipes().map((recipe) => recipe.id))
    return [...new Set(value.filter((id): id is string => typeof id === 'string' && known.has(id)))]
  } catch { return [] }
}

export function writeFavoriteIds(ids: string[], storage: StorageLike = personalStorage): void {
  storage.setItem(key, JSON.stringify(ids))
}

export const mockFavoriteRepository: FavoriteRepository = {
  async listIds() {
    if (!isSupabaseConfigured) return readFavoriteIds()
    const remote = await loadPersonalData('favorites')
    if (remote !== null) {
      writeFavoriteIds(Array.isArray(remote) ? remote.filter((id): id is string => typeof id === 'string') : [])
      return readFavoriteIds()
    }
    const local = readFavoriteIds()
    if (local.length) await savePersonalData('favorites', local)
    return local
  },
  async saveIds(ids) {
    const known = new Set(getKnownRecipes().map((recipe) => recipe.id))
    const safeIds = [...new Set(ids.filter((id) => known.has(id)))]
    if (isSupabaseConfigured) await savePersonalData('favorites', safeIds)
    writeFavoriteIds(safeIds)
  },
}

// Backward-compatible async methods delegate to the repository contract.
export async function getFavoriteIds(): Promise<string[]> { return mockFavoriteRepository.listIds() }
export async function saveFavoriteIds(ids: string[]): Promise<void> { return mockFavoriteRepository.saveIds(ids) }
