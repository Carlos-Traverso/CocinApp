export const defaultPantryCategories = [
  'Frutas y verduras', 'Carnes y pescados', 'Lácteos',
  'Granos y legumbres', 'Huevos', 'Almacén', 'Otros',
]

export const defaultPantryUnits = ['g', 'kg', 'ml', 'l', 'u']

export type PantryCategory = string
export type PantryUnit = string
export type PantryStatus = 'ok' | 'low' | 'empty' | 'soon' | 'expired'

export interface PantryItem {
  id: string
  name: string
  category: PantryCategory
  quantity: number
  unit: PantryUnit
  minimum: number
  expiry: string
}

export interface PantryFilters {
  search: string
  category: PantryCategory | ''
  status: PantryStatus | ''
}

export function normalizePantryName(name: string): string {
  return name.trim().replace(/\s+/g, ' ').normalize('NFD').replace(/[\u0300-\u036f]/g, '').toLocaleLowerCase('es')
}

export function daysUntilExpiry(expiry: string, today = new Date()): number | null {
  if (!/^\d{4}-\d{2}-\d{2}$/.test(expiry)) return null
  const [year, month, day] = expiry.split('-').map(Number)
  const date = new Date(year, month - 1, day)
  if (date.getFullYear() !== year || date.getMonth() !== month - 1 || date.getDate() !== day) return null
  const expirationDay = Date.UTC(year, month - 1, day)
  const currentDay = Date.UTC(today.getFullYear(), today.getMonth(), today.getDate())
  return Math.round((expirationDay - currentDay) / 86_400_000)
}

export function getPantryFlags(item: PantryItem, today = new Date()) {
  const days = item.expiry ? daysUntilExpiry(item.expiry, today) : null
  return {
    days,
    empty: item.quantity === 0,
    low: item.minimum > 0 && item.quantity > 0 && item.quantity < item.minimum,
    soon: days !== null && days >= 0 && days <= 3,
    expired: days !== null && days < 0,
  }
}

export function getPantryStatus(item: PantryItem, today = new Date()): { kind: PantryStatus; label: string } {
  const flags = getPantryFlags(item, today)
  if (flags.expired) return { kind: 'expired', label: 'Vencido' }
  if (flags.empty) return { kind: 'empty', label: 'Sin stock' }
  if (flags.soon) return { kind: 'soon', label: 'Vence pronto' }
  if (flags.low) return { kind: 'low', label: 'Stock bajo' }
  return { kind: 'ok', label: 'Disponible' }
}

export function hasDuplicateItem(items: PantryItem[], candidate: PantryItem): boolean {
  return items.some((item) => item.id !== candidate.id
    && item.unit === candidate.unit
    && normalizePantryName(item.name) === normalizePantryName(candidate.name))
}

export function filterPantryItems(items: PantryItem[], filters: PantryFilters, today = new Date()): PantryItem[] {
  const search = normalizePantryName(filters.search)
  return items.filter((item) => {
    if (search && !normalizePantryName(item.name).includes(search)) return false
    if (filters.category && item.category !== filters.category) return false
    if (!filters.status) return true
    const flags = getPantryFlags(item, today)
    if (filters.status === 'low') return flags.low || flags.empty
    if (filters.status === 'ok') return !flags.low && !flags.empty && !flags.soon && !flags.expired
    return flags[filters.status]
  }).sort((first, second) => first.name.localeCompare(second.name, 'es'))
}

export function formatPantryAmount(quantity: number, unit: PantryUnit): string {
  const formatter = new Intl.NumberFormat('es-AR', { maximumFractionDigits: 2 })
  if (unit === 'g' && quantity >= 1000) return `${formatter.format(quantity / 1000)} kg`
  if (unit === 'ml' && quantity >= 1000) return `${formatter.format(quantity / 1000)} l`
  return `${formatter.format(quantity)} ${unit}`
}

export function pantryExpiryText(item: PantryItem, today = new Date()): string {
  if (!item.expiry) return 'Sin vencimiento registrado'
  const days = daysUntilExpiry(item.expiry, today)
  if (days === null) return 'Fecha de vencimiento inválida'
  if (days < 0) return `Venció hace ${-days} ${days === -1 ? 'día' : 'días'}`
  if (days === 0) return 'Vence hoy'
  if (days <= 3) return `Vence en ${days} ${days === 1 ? 'día' : 'días'}`
  return `Vence el ${new Date(`${item.expiry}T12:00:00`).toLocaleDateString('es-AR')}`
}
