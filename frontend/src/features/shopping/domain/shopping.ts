import { daysUntilExpiry, normalizePantryName, type PantryCategory, type PantryItem, type PantryUnit } from '../../pantry/domain/pantry'
import type { Recipe } from '../../recipes/domain/Recipe'
import { compatibleUnitAbbreviations, convertQuantity, normalizeQuantity, quantityDeficit, roundQuantity } from '../../../shared/domain/units'
import type { AdminCategory, AdminIngredient, AdminUnit } from '../../admin/domain/adminModels'

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
  ingredientId?: string | null
}

export function isShoppingItemTransferable(item: ShoppingItem, catalog: { ingredients: AdminIngredient[]; units: AdminUnit[]; categories: AdminCategory[] }): boolean {
  if (!item.checked || item.transferredToPantry
    || !item.name.trim() || item.name.length > 70
    || !Number.isFinite(item.quantity) || item.quantity <= 0 || item.quantity > 1_000_000
    || !catalog.categories.some((category) => category.active && !category.isDeleted && category.name === item.category)
    || !normalizeQuantity(item.quantity, item.unit, catalog.units)) return false
  if (item.ingredientId === undefined || item.ingredientId === null) return true
  const ingredient = catalog.ingredients.find((candidate) => candidate.id === item.ingredientId && candidate.active && !candidate.isDeleted && normalizePantryName(candidate.name) === normalizePantryName(item.name))
  const baseUnit = ingredient && catalog.units.find((unit) => unit.id === ingredient.baseUnitId && unit.active && !unit.isDeleted)
  return Boolean(baseUnit && compatibleUnitAbbreviations(baseUnit.abbreviation, catalog.units).includes(item.unit))
}

export function addPurchaseToPantry(pantry: PantryItem[], purchase: ShoppingItem, units?: AdminUnit[]): PantryItem[] {
  if (pantry.some((item) => item.sourceShoppingIds?.includes(purchase.id))) return pantry
  const matchingIndex = pantry.findIndex((item) => {
    if (normalizePantryName(item.name) !== normalizePantryName(purchase.name)) return false
    if (item.expiry && (daysUntilExpiry(item.expiry) ?? -1) < 0) return false
    return convertQuantity(1, purchase.unit, item.unit, units) !== null
  })
  if (matchingIndex < 0) return [...pantry, {
    id: crypto.randomUUID(), name: purchase.name, category: purchase.category, quantity: purchase.quantity,
    unit: purchase.unit, minimum: 0, expiry: null, sourceShoppingIds: [purchase.id],
    ...(purchase.ingredientId ? { ingredientId: purchase.ingredientId } : {}),
  }]
  return pantry.map((item, index) => {
    if (index !== matchingIndex) return item
    const converted = convertQuantity(purchase.quantity, purchase.unit, item.unit, units)
    if (converted === null) return item
    return { ...item, quantity: roundQuantity(item.quantity + converted),
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

export function createShoppingShareText(items: ShoppingItem[], units?: AdminUnit[]): string {
  const consolidated = new Map<string, { name: string; unit: string; quantity: number; checked: boolean }>()
  for (const item of items.filter((entry) => !entry.transferredToPantry)) {
    const key = shoppingKey(item.name, item.unit, units)
    const existing = consolidated.get(key)
    if (!existing) consolidated.set(key, { name: item.name, unit: item.unit, quantity: item.quantity, checked: item.checked })
    else {
      const converted = convertQuantity(item.quantity, item.unit, existing.unit, units)
      if (converted !== null) existing.quantity = roundQuantity(existing.quantity + converted)
      existing.checked ||= item.checked
    }
  }
  const lines = [...consolidated.values()].map((item) => `• ${item.name}: ${new Intl.NumberFormat('es-AR', { maximumSignificantDigits: 12 }).format(item.quantity)} ${item.unit}${item.checked ? ' (comprado)' : ''}`)
  return ['Lista de compras CocinAPP', ...(lines.length ? lines : ['(sin artículos)'])].join('\n')
}

export function shoppingKey(name: string, unit: PantryUnit, units?: AdminUnit[]): string {
  const normalized = normalizeQuantity(1, unit, units)
  return `${normalizePantryName(name)}:${normalized ? `${normalized.dimension}:${normalized.baseUnit}` : unit}`
}

function usableQuantity(item: PantryItem, today: Date): number {
  return !item.expiry || (daysUntilExpiry(item.expiry, today) ?? -1) >= 0 ? item.quantity : 0
}

export function suggestForRecipes(recipes: Recipe[], pantry: PantryItem[], source: ShoppingSource, today = new Date(), units?: AdminUnit[], portionsByRecipe: ReadonlyMap<string, number> = new Map()): ShoppingSuggestion[] {
  const needs = new Map<string, ShoppingSuggestion>()
  for (const recipe of recipes) for (const ingredient of recipe.ingredients) {
    if (!normalizeQuantity(ingredient.quantity, ingredient.unit, units)) throw new Error(`La unidad ${ingredient.unit} de ${ingredient.name} no está disponible o no es válida.`)
    const portions = portionsByRecipe.get(recipe.id) ?? recipe.portions
    const quantity = ingredient.quantity * portions / recipe.portions
    const key = shoppingKey(ingredient.name, ingredient.unit, units)
    const existing = needs.get(key)
    if (existing) {
      const converted = convertQuantity(quantity, ingredient.unit, existing.unit, units)
      if (converted !== null) existing.quantity = roundQuantity(existing.quantity + converted)
      if (existing.category === 'Otros' && ingredient.category && ingredient.category !== 'Otros') existing.category = ingredient.category
    }
    else needs.set(key, {
      name: ingredient.name, unit: ingredient.unit, quantity,
      category: ingredient.category
        ?? pantry.find((item) => normalizePantryName(item.name) === normalizePantryName(ingredient.name) && item.category !== 'Otros')?.category
        ?? 'Otros', source,
    })
  }
  return [...needs.values()].map((need) => {
    const matchingStock = pantry.filter((item) => normalizePantryName(item.name) === normalizePantryName(need.name))
    for (const item of matchingStock) if (!normalizeQuantity(item.quantity, item.unit, units)) throw new Error(`La unidad ${item.unit} de ${item.name} en la despensa no es válida.`)
    const available = matchingStock.reduce((total, item) => {
      const usable = usableQuantity(item, today)
      const converted = convertQuantity(usable, item.unit, need.unit, units)
      return total + (converted ?? (item.unit === need.unit ? usable : 0))
    }, 0)
    return { ...need, quantity: quantityDeficit(need.quantity, available) }
  }).filter((item) => item.quantity > 0)
}

export function suggestPantryRestock(pantry: PantryItem[], today = new Date(), units?: AdminUnit[]): ShoppingSuggestion[] {
  const grouped = new Map<string, PantryItem[]>()
  for (const item of pantry) {
    if (!normalizeQuantity(item.quantity, item.unit, units)) throw new Error(`La unidad ${item.unit} de ${item.name} en la despensa no es válida.`)
    const key = shoppingKey(item.name, item.unit, units)
    grouped.set(key, [...(grouped.get(key) ?? []), item])
  }
  const suggestions: ShoppingSuggestion[] = []
  for (const items of grouped.values()) {
    const unit = items[0].unit
    const usable = items.reduce((total, item) => total + (convertQuantity(usableQuantity(item, today), item.unit, unit, units) ?? (item.unit === unit ? usableQuantity(item, today) : 0)), 0)
    const minimum = Math.max(...items.map((item) => convertQuantity(item.minimum, item.unit, unit, units) ?? (item.unit === unit ? item.minimum : 0)))
    const expired = items.some((item) => item.expiry && (daysUntilExpiry(item.expiry, today) ?? 0) < 0)
    const quantity = minimum > 0 ? Math.max(0, minimum - usable) : usable === 0 && (expired || items.some((item) => item.quantity === 0)) ? Math.max(1, ...items.map((item) => convertQuantity(item.quantity, item.unit, unit, units) ?? 0)) : 0
    if (quantity > 0) suggestions.push({ name: items[0].name, category: items[0].category, quantity, unit, source: 'pantry' })
  }
  return suggestions
}

export function mergeShoppingSuggestions(items: ShoppingItem[], suggestions: ShoppingSuggestion[], units?: AdminUnit[]): ShoppingItem[] {
  const merged = items.map((item) => ({ ...item, sources: [...item.sources] }))
  for (const suggestion of suggestions) {
    const key = shoppingKey(suggestion.name, suggestion.unit, units)
    const existing = merged.find((item) => shoppingKey(item.name, item.unit, units) === key)
    if (existing) {
      const converted = convertQuantity(suggestion.quantity, suggestion.unit, existing.unit, units)
      if (converted !== null) existing.quantity = Math.max(existing.quantity, converted)
      if (existing.category === 'Otros' && suggestion.category !== 'Otros') existing.category = suggestion.category
      if (!existing.sources.includes(suggestion.source)) existing.sources.push(suggestion.source)
    } else {
      merged.push({ id: crypto.randomUUID(), name: suggestion.name, category: suggestion.category, quantity: suggestion.quantity, unit: suggestion.unit, note: '', checked: false, transferredToPantry: false, transferredAt: null, sources: [suggestion.source] })
    }
  }
  return merged
}
