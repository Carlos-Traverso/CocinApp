import type { AdminCategory, AdminUnit, AdminIngredient, AdminRecipe } from '../domain/adminModels'
import { defaultPantryCategories, defaultPantryUnits } from '../../pantry/domain/pantry'
import { normalizePantryName } from '../../pantry/domain/pantry'

const ADMIN_KEY = 'cocinapp.admin.v1'

export interface AdminStorageData {
  categories: AdminCategory[]
  units: AdminUnit[]
  ingredients: AdminIngredient[]
  recipes: AdminRecipe[]
}

function getAdminData(): AdminStorageData {
  try {
    const raw = localStorage.getItem(ADMIN_KEY)
    if (raw) {
      const data: unknown = JSON.parse(raw)
      if (!data || typeof data !== 'object') return { categories: [], units: [], ingredients: [], recipes: [] }
      const record = data as Record<string, unknown>
      return {
        categories: Array.isArray(record.categories) ? record.categories : [],
        units: Array.isArray(record.units) ? record.units.map((value) => {
          if (!value || typeof value !== 'object') return value
          const unit = value as AdminUnit
          const legacyDimension = String((value as { dimension?: unknown }).dimension)
          const dimension = legacyDimension === 'mass' ? 'masa' : legacyDimension === 'volume' ? 'volumen' : legacyDimension === 'count' || legacyDimension === 'unidad' ? 'conteo' : legacyDimension
          return { ...unit, dimension }
        }) : [],
        ingredients: Array.isArray(record.ingredients) ? record.ingredients : [],
        recipes: Array.isArray(record.recipes) ? record.recipes.map((value) => {
          if (!value || typeof value !== 'object') return value
          const recipe = value as AdminRecipe & { status?: string }
          return { ...recipe, status: recipe.status === 'published' ? 'published' : 'draft', isDeleted: Boolean(recipe.isDeleted), mealShift: recipe.mealShift || recipe.category || 'Almuerzo', calories: Number.isFinite(recipe.calories) ? recipe.calories : 0, dietaryTags: Array.isArray(recipe.dietaryTags) ? recipe.dietaryTags : [], ingredients: Array.isArray(recipe.ingredients) ? recipe.ingredients : [], steps: Array.isArray(recipe.steps) ? recipe.steps : [], stepMeta: Array.isArray(recipe.stepMeta) ? recipe.stepMeta : [] }
        }) : [],
      }
    }
  } catch {
    // Ignore corrupt data
  }
  return { categories: [], units: [], ingredients: [], recipes: [] }
}

export function saveAdminData(data: AdminStorageData): void {
  localStorage.setItem(ADMIN_KEY, JSON.stringify(data))
  window.dispatchEvent(new Event('storage'))
}

// Helpers for merging defaults with admin data

export function getActiveCategories(): string[] {
  const data = getAdminData()
  const custom = data.categories.filter((c) => c && !c.isDeleted && typeof c.name === 'string').map((c) => c.name)
  const combined = new Set([...defaultPantryCategories, ...custom])
  return Array.from(combined).sort((a, b) => a.localeCompare(b, 'es'))
}

export function getActiveUnits(): string[] {
  const data = getAdminData()
  const custom = data.units.filter((u) => u && !u.isDeleted && typeof u.abbreviation === 'string').map((u) => u.abbreviation)
  const combined = new Set([...defaultPantryUnits, ...custom])
  return Array.from(combined)
}

export function getKnownCategories(): string[] {
  return [...new Set([...defaultPantryCategories, ...getAdminData().categories.filter((category) => category && typeof category.name === 'string').map((category) => category.name)])]
}

export function getKnownUnits(): string[] {
  return [...new Set([...defaultPantryUnits, ...getAdminData().units.filter((unit) => unit && typeof unit.abbreviation === 'string').map((unit) => unit.abbreviation)])]
}

export function findActiveIngredient(name: string) {
  const normalized = normalizePantryName(name)
  if (!normalized) return undefined
  return getAdminData().ingredients.find((ingredient) => !ingredient.isDeleted && normalizePantryName(ingredient.name) === normalized)
}

export function getUnitsForIngredient(name: string): string[] {
  const data = getAdminData()
  const ingredient = findActiveIngredient(name)
  const base = data.units.find((unit) => unit.id === ingredient?.baseUnitId && !unit.isDeleted)
  if (!base) return getActiveUnits()
  const defaultsByDimension: Record<AdminUnit['dimension'], string[]> = {
    masa: ['g', 'kg'], volumen: ['ml', 'l'], conteo: ['u'],
  }
  return [...new Set([...defaultsByDimension[base.dimension], ...data.units.filter((unit) => !unit.isDeleted && unit.dimension === base.dimension).map((unit) => unit.abbreviation)])]
}

export { getAdminData }
