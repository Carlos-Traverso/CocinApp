import { getAdminData, saveAdminData } from './localAdminStore'
import type { AdminRecipe } from '../domain/adminModels'

export function createRecipe(recipe: Omit<AdminRecipe, 'id' | 'isDeleted'>): string {
  const data = getAdminData()
  const id = crypto.randomUUID()
  data.recipes.push({ ...recipe, id, isDeleted: false })
  saveAdminData(data)
  return id
}

export function updateRecipe(id: string, recipe: Omit<AdminRecipe, 'id' | 'isDeleted'>): void {
  const data = getAdminData()
  const index = data.recipes.findIndex(r => r.id === id)
  if (index !== -1) {
    data.recipes[index] = { ...recipe, id, isDeleted: data.recipes[index].isDeleted }
    saveAdminData(data)
  }
}

export function deleteRecipe(id: string, hasReferences: boolean): void {
  const data = getAdminData()
  const index = data.recipes.findIndex(r => r.id === id)
  if (index !== -1) {
    if (hasReferences) {
      data.recipes[index].isDeleted = true
    } else {
      data.recipes.splice(index, 1)
    }
    saveAdminData(data)
  }
}
