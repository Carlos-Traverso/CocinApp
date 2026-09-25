import { getAdminData, saveAdminData } from './localAdminStore'
import type { AdminRecipe } from '../domain/adminModels'
import { hasAdminReferences } from './adminReferences'
import { validateRecipe } from '../domain/adminValidation'

export function createRecipe(recipe: Omit<AdminRecipe, 'id' | 'isDeleted'>): string {
  const data = getAdminData()
  const validRecipe = validateRecipe(recipe, data.recipes, data.ingredients, data.units)
  const id = crypto.randomUUID()
  data.recipes.push({ ...validRecipe, id, isDeleted: false })
  saveAdminData(data)
  return id
}

export function updateRecipe(id: string, recipe: Omit<AdminRecipe, 'id' | 'isDeleted'>): void {
  const data = getAdminData()
  const validRecipe = validateRecipe(recipe, data.recipes, data.ingredients, data.units, id)
  const index = data.recipes.findIndex(r => r.id === id)
  if (index !== -1) {
    data.recipes[index] = { ...validRecipe, id, isDeleted: data.recipes[index].isDeleted }
    saveAdminData(data)
  }
}

export function deleteRecipe(id: string): void {
  const data = getAdminData()
  const index = data.recipes.findIndex(r => r.id === id)
  if (index !== -1) {
    if (hasAdminReferences('recipe', id)) {
      data.recipes[index].isDeleted = true
    } else {
      data.recipes.splice(index, 1)
    }
    saveAdminData(data)
  }
}
