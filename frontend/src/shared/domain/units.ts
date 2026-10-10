import type { AdminUnit } from '../../features/admin/domain/adminModels'

type NormalizedQuantity = { dimension: string; baseUnit: string; quantity: number }

export function roundQuantity(value: number): number {
  if (!Number.isFinite(value)) return Number.NaN
  return Number(value.toPrecision(12))
}

export function quantityDeficit(required: number, available: number): number {
  if (!Number.isFinite(required) || !Number.isFinite(available)) return Number.NaN
  const difference = required - available
  const epsilon = Number.EPSILON * Math.max(Math.abs(required), Math.abs(available)) * 4
  return roundQuantity(Math.max(0, difference <= epsilon ? 0 : difference))
}

const builtIns: AdminUnit[] = [
  { id: 'g', name: 'Gramo', abbreviation: 'g', dimension: 'masa', active: true, isDeleted: false },
  { id: 'kg', name: 'Kilogramo', abbreviation: 'kg', dimension: 'masa', baseUnitId: 'g', equivalenceMultiplier: 1000, active: true, isDeleted: false },
  { id: 'ml', name: 'Mililitro', abbreviation: 'ml', dimension: 'volumen', active: true, isDeleted: false },
  { id: 'l', name: 'Litro', abbreviation: 'l', dimension: 'volumen', baseUnitId: 'ml', equivalenceMultiplier: 1000, active: true, isDeleted: false },
  { id: 'u', name: 'Unidad', abbreviation: 'u', dimension: 'conteo', active: true, isDeleted: false },
]

function catalog(units?: AdminUnit[]): AdminUnit[] {
  return units ?? builtIns
}

function resolve(unitKey: string, units: AdminUnit[]): NormalizedQuantity | null {
  const unit = units.find((entry) => !entry.isDeleted
    && (entry.id === unitKey || entry.abbreviation.toLocaleLowerCase('es') === unitKey.toLocaleLowerCase('es')))
  if (!unit || !unit.active) return null
  const visited = new Set<string>()
  let current = unit
  let quantity = 1
  while (current.baseUnitId) {
    if (visited.has(current.id) || !Number.isFinite(current.equivalenceMultiplier) || (current.equivalenceMultiplier ?? 0) <= 0) return null
    visited.add(current.id)
    quantity *= current.equivalenceMultiplier!
    if (!Number.isFinite(quantity)) return null
    const parent = units.find((entry) => entry.id === current.baseUnitId && !entry.isDeleted && entry.active)
    if (!parent || parent.dimension !== unit.dimension) return null
    current = parent
  }
  if (visited.has(current.id)) return null
  return { dimension: unit.dimension, baseUnit: current.abbreviation, quantity }
}

export function normalizeQuantity(quantity: number, unit: string, units?: AdminUnit[]): NormalizedQuantity | null {
  if (!Number.isFinite(quantity) || quantity < 0 || !unit.trim()) return null
  const entries = catalog(units)
  const resolved = resolve(unit, entries)
  if (!resolved) return null
  const normalized = quantity * resolved.quantity
  return Number.isFinite(normalized) ? { ...resolved, quantity: normalized } : null
}

export function convertQuantity(quantity: number, from: string, to: string, units?: AdminUnit[]): number | null {
  const entries = catalog(units)
  const source = resolve(from, entries)
  const target = resolve(to, entries)
  if (!source || !target || source.dimension !== target.dimension || source.baseUnit !== target.baseUnit || !Number.isFinite(quantity) || quantity < 0) return null
  const converted = quantity * source.quantity / target.quantity
  return Number.isFinite(converted) ? converted : null
}

export function compatibleUnitAbbreviations(baseUnit: string, units?: AdminUnit[]): string[] {
  const entries = catalog(units)
  const base = resolve(baseUnit, entries)
  if (!base) return []
  return entries.filter((unit) => unit.active && !unit.isDeleted).filter((unit) => {
    const resolved = resolve(unit.id, entries)
    return resolved?.dimension === base.dimension && resolved.baseUnit === base.baseUnit
  }).map((unit) => unit.abbreviation)
}
