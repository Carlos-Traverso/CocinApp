import { getKnownCategories, getKnownUnits } from '../../admin/data/localAdminStore'
import { personalStorage } from '../../auth/data/personalStorage'
import { readPantryItems, writePantryItems } from '../../pantry/data/localPantryStore'
import { addPurchaseToPantry } from '../domain/shopping'
import { mergeShoppingSuggestions, type ShoppingItem, type ShoppingSource, type ShoppingSuggestion } from '../domain/shopping'

const key = 'cocinapp.shopping.v1'
const sources: ShoppingSource[] = ['manual', 'recipe', 'plan', 'favorites', 'pantry']
interface StorageLike { getItem(key: string): string | null; setItem(key: string, value: string): void }

function readShoppingItem(value: unknown, transferredIds: Set<string>): ShoppingItem | undefined {
  if (!value || typeof value !== 'object') return undefined
  const item = value as Record<string, unknown>
  const knownCategories = getKnownCategories()
  const knownUnits = getKnownUnits()

  const valid = typeof item.id === 'string' && item.id.length > 0
    && typeof item.name === 'string' && item.name.trim().length > 0 && item.name.length <= 70
    && knownCategories.includes(item.category as string)
    && knownUnits.includes(item.unit as string)
    && typeof item.quantity === 'number' && Number.isFinite(item.quantity) && item.quantity > 0 && item.quantity <= 1_000_000
    && typeof item.note === 'string' && item.note.length <= 200
    && typeof item.checked === 'boolean'
    && (item.transferredToPantry === undefined || typeof item.transferredToPantry === 'boolean')
    && (item.transferredAt === undefined || item.transferredAt === null || typeof item.transferredAt === 'string')
    && Array.isArray(item.sources) && item.sources.length > 0
    && item.sources.every((source: unknown) => sources.includes(source as ShoppingSource))
  if (!valid) return undefined
  const transferredToPantry = transferredIds.has(item.id as string) || item.transferredToPantry === true
  return { ...(item as unknown as ShoppingItem), transferredToPantry,
    transferredAt: transferredToPantry && typeof item.transferredAt === 'string' ? item.transferredAt : null }
}

export function readShoppingItems(storage: StorageLike = personalStorage): ShoppingItem[] {
  try {
    const value: unknown = JSON.parse(storage.getItem(key) ?? '[]')
    if (!Array.isArray(value)) return []
    const transferredIds = new Set(readPantryItems(storage).flatMap((item) => item.sourceShoppingIds ?? []))
    const seen = new Set<string>()
    return value.flatMap((value): ShoppingItem[] => {
      const item = readShoppingItem(value, transferredIds)
      if (!item || item.transferredToPantry || seen.has(item.id)) return []
      seen.add(item.id)
      return [item]
    })
  } catch { return [] }
}

export function writeShoppingItems(items: ShoppingItem[], storage: StorageLike = personalStorage): void {
  storage.setItem(key, JSON.stringify(items))
}

export function appendShoppingSuggestions(suggestions: ShoppingSuggestion[], storage: StorageLike = personalStorage): ShoppingItem[] {
  const merged = mergeShoppingSuggestions(readShoppingItems(storage), suggestions)
  writeShoppingItems(merged, storage)
  return merged
}

export function setShoppingPurchased(id: string, checked: boolean, storage: StorageLike = personalStorage): ShoppingItem[] {
  const items = readShoppingItems(storage)
  const next = items.map((entry) => entry.id === id ? { ...entry, checked } : entry)
  writeShoppingItems(next, storage)
  return next
}

export function markAllShoppingPurchased(storage: StorageLike = personalStorage): ShoppingItem[] {
  const next = readShoppingItems(storage).map((item) => item.transferredToPantry ? item : { ...item, checked: true })
  writeShoppingItems(next, storage)
  return next
}

export interface PantryTransferResult { items: ShoppingItem[]; transferredCount: number; removedCount: number }

export function transferPurchasedToPantry(storage: StorageLike = personalStorage, now = new Date()): PantryTransferResult {
  const items = readShoppingItems(storage)
  const pantryBefore = readPantryItems(storage)
  const purchases = items.filter((item) => item.checked && !item.transferredToPantry)
  if (purchases.length === 0) return { items, transferredCount: 0, removedCount: 0 }

  const transferredAt = now.toISOString()
  const transferred = purchases.map((item) => ({ ...item, transferredToPantry: true, transferredAt }))
  const pantryAfter = transferred.reduce(addPurchaseToPantry, pantryBefore)
  const transferredIds = new Set(transferred.map((item) => item.id))
  const shoppingAfter = items.filter((item) => !transferredIds.has(item.id))

  let pantryCommitted = false
  try {
    writePantryItems(pantryAfter, storage)
    pantryCommitted = true
    writeShoppingItems(shoppingAfter, storage)
  } catch (cause) {
    if (pantryCommitted) {
      try { writePantryItems(pantryBefore, storage) } catch { /* Preserve the original transfer error. */ }
    }
    throw new Error('La transferencia no se pudo confirmar.', { cause })
  }

  return { items: shoppingAfter, transferredCount: transferred.length, removedCount: items.length - shoppingAfter.length }
}
