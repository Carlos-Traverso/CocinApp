import { daysUntilExpiry, type PantryItem } from '../domain/pantry'
import { getActiveCategories, getActiveUnits } from '../../admin/data/localAdminStore'

const pantryKey = 'cocinapp.pantry.v1'
const legacyPantryKey = 'cocinapp-demo-pantry-v1'

interface PantryStorage {
  getItem(key: string): string | null
  setItem(key: string, value: string): void
}

function isPantryItem(value: unknown): value is PantryItem {
  if (!value || typeof value !== 'object') return false
  const item = value as Record<string, unknown>
  const activeCategories = getActiveCategories()
  const activeUnits = getActiveUnits()

  return typeof item.id === 'string'
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
    if (current === null && items.length > 0) {
      try { writePantryItems(items, storage) } catch { /* Existing data remains readable. */ }
    }
    return items
  } catch {
    return []
  }
}

export function writePantryItems(items: PantryItem[], storage: PantryStorage = localStorage): void {
  storage.setItem(pantryKey, JSON.stringify(items))
}

