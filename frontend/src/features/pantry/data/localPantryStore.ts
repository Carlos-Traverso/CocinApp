import { personalStorage } from '../../auth/data/personalStorage'
import { daysUntilExpiry, type PantryItem } from '../domain/pantry'
import { getActiveCategories, getActiveUnits } from '../../admin/data/localAdminStore'

const pantryKey = 'cocinapp.pantry.v1'
const legacyPantryKey = 'cocinapp-demo-pantry-v1'

interface PantryStorage {
  getItem(key: string): string | null
  setItem(key: string, value: string): void
}

function readPantryItem(value: unknown): PantryItem | undefined {
  if (!value || typeof value !== 'object') return undefined
  const item = value as Record<string, unknown>
  const activeCategories = getActiveCategories()
  const activeUnits = getActiveUnits()

  const valid = typeof item.id === 'string'
    && item.id.length > 0
    && typeof item.name === 'string'
    && item.name.trim().length > 0
    && activeCategories.includes(item.category as string)
    && activeUnits.includes(item.unit as string)
    && typeof item.quantity === 'number'
    && Number.isFinite(item.quantity)
    && item.quantity >= 0
    && item.quantity <= 1_000_000
    && typeof item.minimum === 'number'
    && Number.isFinite(item.minimum)
    && item.minimum >= 0
    && item.minimum <= 1_000_000
    && (item.expiry === null || item.expiry === '' || typeof item.expiry === 'string' && daysUntilExpiry(item.expiry) !== null)
  if (!valid) return undefined
  const parsed = { ...(item as unknown as PantryItem), expiry: typeof item.expiry === 'string' && item.expiry ? item.expiry : null }
  if (Array.isArray(item.sourceShoppingIds)) parsed.sourceShoppingIds = item.sourceShoppingIds.filter((id): id is string => typeof id === 'string')
  else delete parsed.sourceShoppingIds
  return parsed
}

export function readPantryItems(storage: PantryStorage = personalStorage): PantryItem[] {
  try {
    const current = storage.getItem(pantryKey)
    const stored = current ?? storage.getItem(legacyPantryKey)
    if (!stored) return []
    const value: unknown = JSON.parse(stored)
    if (!Array.isArray(value)) return []
    const items = value.flatMap((item) => {
      const parsed = readPantryItem(item)
      return parsed ? [parsed] : []
    })
    if (current === null && items.length > 0) {
      try { writePantryItems(items, storage) } catch { /* Existing data remains readable. */ }
    }
    const seen = new Set<string>()
    return items.filter((item) => { if (seen.has(item.id)) return false; seen.add(item.id); return true })
  } catch {
    return []
  }
}

export function writePantryItems(items: PantryItem[], storage: PantryStorage = personalStorage): void {
  storage.setItem(pantryKey, JSON.stringify(items))
  if (typeof window !== 'undefined') window.dispatchEvent(new Event('cocinapp:pantry-updated'))
}

