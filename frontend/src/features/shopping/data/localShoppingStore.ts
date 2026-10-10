import { getAdminData, getKnownCategories, getKnownUnits, resolveIngredientCategory } from '../../admin/data/localAdminStore'
import { createInitialAdminData } from '../../admin/data/adminSeed'
import { personalStorage } from '../../auth/data/personalStorage'
import { readPantryItems, writePantryItems } from '../../pantry/data/localPantryStore'
import { addPurchaseToPantry } from '../domain/shopping'
import { mergeShoppingSuggestions, type ShoppingItem, type ShoppingSource, type ShoppingSuggestion } from '../domain/shopping'
import { normalizePantryName } from '../../pantry/domain/pantry'
import { compatibleUnitAbbreviations } from '../../../shared/domain/units'
import { inferIngredientCategory } from '../../admin/domain/ingredientCategory'

const key = 'cocinapp.shopping.v1'
const sources: ShoppingSource[] = ['manual', 'recipe', 'plan', 'favorites', 'pantry']
interface StorageLike { getItem(key: string): string | null; setItem(key: string, value: string): void }

function catalogData() {
  try { return getAdminData() } catch { return createInitialAdminData() }
}

function readShoppingItem(value: unknown, transferredIds: Set<string>): ShoppingItem | undefined {
  if (!value || typeof value !== 'object') return undefined
  const item = value as Record<string, unknown>
  let knownCategories: string[]
  let knownUnits: string[]
  try { knownCategories = getKnownCategories(); knownUnits = getKnownUnits() }
  catch { knownCategories = getAdminDataFallback().categories.map((entry) => entry.name); knownUnits = getAdminDataFallback().units.map((entry) => entry.abbreviation) }
  const storedCategory = typeof item.category === 'string' && knownCategories.includes(item.category) ? item.category : undefined
  let category = storedCategory
  let catalog = catalogData()
  try { if (!category || category === 'Otros') category = resolveIngredientCategory(String(item.name ?? '')) }
  catch { category ??= inferIngredientCategory(String(item.name ?? '')) ?? 'Otros' }
  const catalogMatch = catalog.ingredients.find((ingredient) => ingredient.active && !ingredient.isDeleted && ingredient.name.trim().toLocaleLowerCase('es') === String(item.name ?? '').trim().toLocaleLowerCase('es'))

  const valid = typeof item.id === 'string' && item.id.length > 0
    && typeof item.name === 'string' && item.name.trim().length > 0 && item.name.length <= 70
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
  const hasAssociation = Object.prototype.hasOwnProperty.call(item, 'ingredientId')
  const associated = hasAssociation
    ? typeof item.ingredientId === 'string' ? catalog.ingredients.find((ingredient) => ingredient.id === item.ingredientId && ingredient.active && !ingredient.isDeleted && normalizePantryName(ingredient.name) === normalizePantryName(String(item.name))) : undefined
    : catalogMatch
  return { ...(item as unknown as ShoppingItem), category, ...(hasAssociation ? { ingredientId: associated?.id ?? null } : associated ? { ingredientId: associated.id } : {}), transferredToPantry,
    transferredAt: transferredToPantry && typeof item.transferredAt === 'string' ? item.transferredAt : null }
}

function getAdminDataFallback() { return createInitialAdminData() }

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
  const catalog = catalogData()
  const merged = mergeShoppingSuggestions(readShoppingItems(storage), suggestions, catalog.units).map((item) => {
    if (Object.prototype.hasOwnProperty.call(item, 'ingredientId')) return item
    const ingredient = catalog.ingredients.find((entry) => entry.active && !entry.isDeleted && normalizePantryName(entry.name) === normalizePantryName(item.name))
    return ingredient ? { ...item, ingredientId: ingredient.id } : item
  })
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
  const catalog = catalogData()
  const purchases = items.filter((item) => {
    if (!item.checked || item.transferredToPantry || !item.ingredientId) return false
    const ingredient = catalog.ingredients.find((candidate) => candidate.id === item.ingredientId && candidate.active && !candidate.isDeleted && normalizePantryName(candidate.name) === normalizePantryName(item.name))
    const baseUnit = ingredient && catalog.units.find((unit) => unit.id === ingredient.baseUnitId && unit.active && !unit.isDeleted)
    return Boolean(baseUnit && compatibleUnitAbbreviations(baseUnit.abbreviation, catalog.units).includes(item.unit))
  })
  if (purchases.length === 0) return { items, transferredCount: 0, removedCount: 0 }

  const transferredAt = now.toISOString()
  const transferred = purchases.map((item) => ({ ...item, transferredToPantry: true, transferredAt }))
  const pantryAfter = transferred.reduce((pantry, item) => addPurchaseToPantry(pantry, item, catalog.units), pantryBefore)
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
