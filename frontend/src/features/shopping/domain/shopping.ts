import { daysUntilExpiry, normalizePantryName, type PantryCategory, type PantryItem, type PantryUnit } from '../../pantry/domain/pantry'
import type { Recipe } from '../../recipes/domain/Recipe'

export type ShoppingSource = 'manual' | 'recipe' | 'plan' | 'favorites' | 'pantry'
export interface ShoppingItem {
  id: string
  name: string
  category: PantryCategory
  quantity: number
  unit: PantryUnit
  note: string
  checked: boolean
  transferredToPantry: boolean
  transferredAt: string | null
  sources: ShoppingSource[]
}

const baseUnits: Record<string, { dimension: string; factor: number; base: string }> = {
  g: { dimension: 'mass', factor: 1, base: 'g' }, kg: { dimension: 'mass', factor: 1000, base: 'g' },
  ml: { dimension: 'volume', factor: 1, base: 'ml' }, l: { dimension: 'volume', factor: 1000, base: 'ml' },
  u: { dimension: 'count', factor: 1, base: 'u' },
}

export function addPurchaseToPantry(pantry: PantryItem[], purchase: ShoppingItem): PantryItem[] {
  if (pantry.some((item) => item.sourceShoppingIds?.includes(purchase.id))) return pantry
  const incoming = baseUnits[purchase.unit]
  const matchingIndex = pantry.findIndex((item) => {
    if (normalizePantryName(item.name) !== normalizePantryName(purchase.name) || item.category !== purchase.category) return false
    if (item.expiry && (daysUntilExpiry(item.expiry) ?? -1) < 0) return false
    const stored = baseUnits[item.unit]
    return item.unit === purchase.unit || Boolean(incoming && stored && incoming.dimension === stored.dimension)
  })
  if (matchingIndex < 0) return [...pantry, {
    id: crypto.randomUUID(), name: purchase.name, category: purchase.category, quantity: purchase.quantity,
    unit: purchase.unit, minimum: 0, expiry: null, sourceShoppingIds: [purchase.id],
  }]
  return pantry.map((item, index) => {
    if (index !== matchingIndex) return item
    const stored = baseUnits[item.unit]
    const converted = incoming && stored ? purchase.quantity * incoming.factor / stored.factor : purchase.quantity
    return { ...item, quantity: Math.round((item.quantity + converted) * 1000) / 1000,
      sourceShoppingIds: [...(item.sourceShoppingIds ?? []), purchase.id] }
  })
}
export interface ShoppingSuggestion {
  name: string
  category: PantryCategory
  quantity: number
  unit: PantryUnit
  source: ShoppingSource
}

export type ShoppingStatusFilter = 'all' | 'pending' | 'checked'
export interface ShoppingFilters { search: string; category: PantryCategory | ''; status: ShoppingStatusFilter }

export function filterShoppingItems(items: ShoppingItem[], filters: ShoppingFilters): ShoppingItem[] {
  const search = normalizePantryName(filters.search)
  return items.filter((item) => {
    if (search && !normalizePantryName(item.name).includes(search)) return false
    if (filters.category && item.category !== filters.category) return false
    if (filters.status === 'pending' && item.checked) return false
    if (filters.status === 'checked' && !item.checked) return false
    return true
  })
}

export function shoppingKey(name: string, unit: PantryUnit): string {
  return `${normalizePantryName(name)}:${unit}`
}

function usableQuantity(item: PantryItem, today: Date): number {
  return !item.expiry || (daysUntilExpiry(item.expiry, today) ?? -1) >= 0 ? item.quantity : 0
}

export function suggestForRecipes(recipes: Recipe[], pantry: PantryItem[], source: ShoppingSource, today = new Date()): ShoppingSuggestion[] {
  const needs = new Map<string, ShoppingSuggestion>()
  for (const recipe of recipes) for (const ingredient of recipe.ingredients) {
    const key = shoppingKey(ingredient.name, ingredient.unit)
    const existing = needs.get(key)
    if (existing) existing.quantity += ingredient.quantity
    else needs.set(key, {
      name: ingredient.name, unit: ingredient.unit, quantity: ingredient.quantity,
      category: pantry.find((item) => shoppingKey(item.name, item.unit) === key)?.category ?? 'Otros', source,
    })
  }
  return [...needs.entries()].map(([key, need]) => ({
    ...need,
    quantity: Math.max(0, Math.round((need.quantity - pantry.filter((item) => shoppingKey(item.name, item.unit) === key)
      .reduce((total, item) => total + usableQuantity(item, today), 0)) * 100) / 100),
  })).filter((item) => item.quantity > 0)
}

export function suggestPantryRestock(pantry: PantryItem[], today = new Date()): ShoppingSuggestion[] {
  const grouped = new Map<string, PantryItem[]>()
  for (const item of pantry) {
    const key = shoppingKey(item.name, item.unit)
    grouped.set(key, [...(grouped.get(key) ?? []), item])
  }
  const suggestions: ShoppingSuggestion[] = []
  for (const items of grouped.values()) {
    const usable = items.reduce((total, item) => total + usableQuantity(item, today), 0)
    const minimum = Math.max(...items.map((item) => item.minimum))
    const expired = items.some((item) => item.expiry && (daysUntilExpiry(item.expiry, today) ?? 0) < 0)
    const quantity = minimum > 0 ? Math.max(0, minimum - usable) : usable === 0 && (expired || items.some((item) => item.quantity === 0)) ? Math.max(1, ...items.map((item) => item.quantity)) : 0
    if (quantity > 0) suggestions.push({ name: items[0].name, category: items[0].category, quantity, unit: items[0].unit, source: 'pantry' })
  }
  return suggestions
}

export function mergeShoppingSuggestions(items: ShoppingItem[], suggestions: ShoppingSuggestion[]): ShoppingItem[] {
  const merged = items.map((item) => ({ ...item, sources: [...item.sources] }))
  for (const suggestion of suggestions) {
    const key = shoppingKey(suggestion.name, suggestion.unit)
    const existing = merged.find((item) => shoppingKey(item.name, item.unit) === key)
    if (existing) {
      existing.quantity = Math.max(existing.quantity, suggestion.quantity)
      if (!existing.sources.includes(suggestion.source)) existing.sources.push(suggestion.source)
    } else {
      merged.push({ id: crypto.randomUUID(), name: suggestion.name, category: suggestion.category, quantity: suggestion.quantity, unit: suggestion.unit, note: '', checked: false, transferredToPantry: false, transferredAt: null, sources: [suggestion.source] })
    }
  }
  return merged
}
