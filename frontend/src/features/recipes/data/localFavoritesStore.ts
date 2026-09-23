import { sampleRecipes } from '../../../mocks/recipes'

const key = 'cocinapp.favorites.v1'
interface StorageLike { getItem(key: string): string | null; setItem(key: string, value: string): void }

export function readFavoriteIds(storage: StorageLike = localStorage): string[] {
  try {
    const value: unknown = JSON.parse(storage.getItem(key) ?? '[]')
    if (!Array.isArray(value)) return []
    const known = new Set(sampleRecipes.map((recipe) => recipe.id))
    return [...new Set(value.filter((id): id is string => typeof id === 'string' && known.has(id)))]
  } catch { return [] }
}

export function writeFavoriteIds(ids: string[], storage: StorageLike = localStorage): void {
  storage.setItem(key, JSON.stringify(ids))
}
