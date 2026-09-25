import { normalizePantryName } from '../../pantry/domain/pantry'
import { getAdminData } from './localAdminStore'

type ReferenceKind = 'ingredient' | 'unit' | 'category' | 'recipe'

function userDataValues(): unknown[] {
  const values: unknown[] = []
  // Personal keys retain their original CocinAPP names after the user prefix.
  for (let index = 0; index < localStorage.length; index += 1) {
    const key = localStorage.key(index)
    if (!key?.startsWith('cocinapp.user.')) continue
    try { values.push({ key, value: JSON.parse(localStorage.getItem(key) ?? 'null') }) } catch { /* Ignore malformed records. */ }
  }
  return values
}

function arrayRecords(values: unknown[]): Record<string, unknown>[] {
  return values.flatMap((value) => {
    if (Array.isArray(value)) return value.filter((entry): entry is Record<string, unknown> => Boolean(entry && typeof entry === 'object'))
    if (value && typeof value === 'object') {
      const record = value as Record<string, unknown>
      if (Array.isArray(record.value)) return record.value.filter((entry): entry is Record<string, unknown> => Boolean(entry && typeof entry === 'object'))
      return record.value && typeof record.value === 'object' ? [record.value as Record<string, unknown>] : []
    }
    return []
  })
}

export function hasAdminReferences(kind: ReferenceKind, id: string, name = ''): boolean {
  const data = getAdminData()
  if (kind === 'category' && data.ingredients.some((entry) => entry.categoryId === id)) return true
  if (kind === 'unit' && (data.units.some((entry) => entry.baseUnitId === id)
    || data.ingredients.some((entry) => entry.baseUnitId === id)
    || data.recipes.some((recipe) => recipe.ingredients.some((entry) => entry.unitId === id)))) return true
  if (kind === 'ingredient' && data.recipes.some((recipe) => recipe.ingredients.some((entry) => entry.ingredientId === id))) return true

  const values = userDataValues()
  if (kind === 'recipe') {
    return values.some((value) => {
      if (Array.isArray(value)) return value.includes(id)
      if (value && typeof value === 'object') {
        const record = value as Record<string, unknown>
        if (record.recipeId === id) return true
        const nested = record.value
        if (nested && typeof nested === 'object' && !Array.isArray(nested) && (nested as Record<string, unknown>).recipeId === id) return true
        if (Array.isArray(nested)) return nested.includes(id) || nested.some((entry) => typeof entry === 'object' && entry !== null && (entry as Record<string, unknown>).recipeId === id)
      }
      return false
    })
  }
  const records = arrayRecords(values)
  if (kind === 'ingredient') return records.some((entry) => entry.ingredientId === id || (name && typeof entry.name === 'string' && normalizePantryName(entry.name) === normalizePantryName(name)))
  if (kind === 'unit') return records.some((entry) => entry.unitId === id || entry.baseUnitId === id || (name && entry.unit === name))
  return records.some((entry) => entry.categoryId === id || (name && typeof entry.category === 'string' && normalizePantryName(entry.category) === normalizePantryName(name)))
}
