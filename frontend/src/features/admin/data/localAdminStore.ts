import type { AdminCategory, AdminUnit, AdminIngredient, AdminRecipe } from '../domain/adminModels'
import { defaultPantryCategories, defaultPantryUnits } from '../../pantry/domain/pantry'

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
      const data = JSON.parse(raw)
      return {
        categories: data.categories || [],
        units: data.units || [],
        ingredients: data.ingredients || [],
        recipes: data.recipes || [],
      }
    }
  } catch {
    // Ignore corrupt data
  }
  return { categories: [], units: [], ingredients: [], recipes: [] }
}

export function saveAdminData(data: AdminStorageData): void {
  try {
    localStorage.setItem(ADMIN_KEY, JSON.stringify(data))
    window.dispatchEvent(new Event('storage')) // Trigger reactivity
  } catch {
    console.error('Failed to save admin data')
  }
}

// Helpers for merging defaults with admin data

export function getActiveCategories(): string[] {
  const data = getAdminData()
  const custom = data.categories.filter((c) => !c.isDeleted).map((c) => c.name)
  const combined = new Set([...defaultPantryCategories, ...custom])
  return Array.from(combined).sort((a, b) => a.localeCompare(b, 'es'))
}

export function getActiveUnits(): string[] {
  const data = getAdminData()
  const custom = data.units.filter((u) => !u.isDeleted).map((u) => u.abbreviation)
  const combined = new Set([...defaultPantryUnits, ...custom])
  return Array.from(combined)
}

export { getAdminData }
