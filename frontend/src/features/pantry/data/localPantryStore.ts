import { daysUntilExpiry, pantryCategories, pantryUnits, type PantryItem } from '../domain/pantry'

const pantryKey = 'cocinapp.pantry.v1'
const legacyPantryKey = 'cocinapp-demo-pantry-v1'

interface PantryStorage {
  getItem(key: string): string | null
  setItem(key: string, value: string): void
}

function isPantryItem(value: unknown): value is PantryItem {
  if (!value || typeof value !== 'object') return false
  const item = value as Record<string, unknown>
  return typeof item.id === 'string'
    && item.id.length > 0
    && typeof item.name === 'string'
    && item.name.trim().length > 0
    && pantryCategories.some((category) => category === item.category)
    && pantryUnits.some((unit) => unit === item.unit)
    && typeof item.quantity === 'number'
    && Number.isFinite(item.quantity)
    && item.quantity >= 0
    && item.quantity <= 1_000_000
    && typeof item.minimum === 'number'
    && Number.isFinite(item.minimum)
    && item.minimum >= 0
    && item.minimum <= 1_000_000
    && typeof item.expiry === 'string'
    && (item.expiry === '' || daysUntilExpiry(item.expiry) !== null)
}

export function readPantryItems(storage: PantryStorage = localStorage): PantryItem[] {
  try {
    const current = storage.getItem(pantryKey)
    const stored = current ?? storage.getItem(legacyPantryKey)
    if (!stored) return []
    const value: unknown = JSON.parse(stored)
    if (!Array.isArray(value)) return []
    const items = value.filter(isPantryItem)
    if (current === null && items.length > 0) writePantryItems(items, storage)
    return items
  } catch {
    return []
  }
}

export function writePantryItems(items: PantryItem[], storage: PantryStorage = localStorage): void {
  storage.setItem(pantryKey, JSON.stringify(items))
}
