import { pantryCategories, pantryUnits } from '../../pantry/domain/pantry'
import { mergeShoppingSuggestions, type ShoppingItem, type ShoppingSource, type ShoppingSuggestion } from '../domain/shopping'

const key = 'cocinapp.shopping.v1'
const sources: ShoppingSource[] = ['manual', 'recipe', 'plan', 'favorites', 'pantry']
interface StorageLike { getItem(key: string): string | null; setItem(key: string, value: string): void }

function isShoppingItem(value: unknown): value is ShoppingItem {
  if (!value || typeof value !== 'object') return false
  const item = value as Record<string, unknown>
  return typeof item.id === 'string' && item.id.length > 0
    && typeof item.name === 'string' && item.name.trim().length > 0 && item.name.length <= 70
    && pantryCategories.some((category) => category === item.category)
    && pantryUnits.some((unit) => unit === item.unit)
    && typeof item.quantity === 'number' && Number.isFinite(item.quantity) && item.quantity > 0 && item.quantity <= 1_000_000
    && typeof item.note === 'string' && item.note.length <= 200
    && typeof item.checked === 'boolean'
    && Array.isArray(item.sources) && item.sources.length > 0
    && item.sources.every((source: unknown) => sources.includes(source as ShoppingSource))
}

export function readShoppingItems(storage: StorageLike = localStorage): ShoppingItem[] {
  try {
    const value: unknown = JSON.parse(storage.getItem(key) ?? '[]')
    if (!Array.isArray(value)) return []
    const seen = new Set<string>()
    return value.filter((item): item is ShoppingItem => {
      if (!isShoppingItem(item) || seen.has(item.id)) return false
      seen.add(item.id)
      return true
    })
  } catch { return [] }
}

export function writeShoppingItems(items: ShoppingItem[], storage: StorageLike = localStorage): void {
  storage.setItem(key, JSON.stringify(items))
}

export function appendShoppingSuggestions(suggestions: ShoppingSuggestion[], storage: StorageLike = localStorage): ShoppingItem[] {
  const merged = mergeShoppingSuggestions(readShoppingItems(storage), suggestions)
  writeShoppingItems(merged, storage)
  return merged
}
