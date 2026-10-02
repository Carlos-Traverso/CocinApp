import { getAdminData, saveAdminData } from './localAdminStore'
import { hasAdminReferences } from './adminReferences'
import { validateIngredient } from '../domain/adminValidation'

export function createIngredient(name: string, categoryId: string, baseUnitId: string): string {
  const data = getAdminData()
  const ingredient = validateIngredient({ name, categoryId, baseUnitId }, data.ingredients, data.categories, data.units)
  const id = crypto.randomUUID()
  data.ingredients.push({ ...ingredient, id, isDeleted: false })
  saveAdminData(data)
  return id
}

export function updateIngredient(id: string, name: string, categoryId: string, baseUnitId: string): void {
  const data = getAdminData()
  const ingredient = validateIngredient({ name, categoryId, baseUnitId }, data.ingredients, data.categories, data.units, id)
  const index = data.ingredients.findIndex(i => i.id === id)
  if (index !== -1) {
    data.ingredients[index] = { ...data.ingredients[index], ...ingredient }
    saveAdminData(data)
  }
}

export function deleteIngredient(id: string): void {
  const data = getAdminData()
  const index = data.ingredients.findIndex(i => i.id === id)
  if (index !== -1) {
    if (hasAdminReferences('ingredient', id, data.ingredients[index].name)) {
      data.ingredients[index].isDeleted = true
    } else {
      data.ingredients.splice(index, 1)
    }
    saveAdminData(data)
  }
}

export function restoreIngredient(id: string): void {
  const data = getAdminData()
  const ingredient = data.ingredients.find((entry) => entry.id === id)
  if (!ingredient) return
  ingredient.isDeleted = false
  saveAdminData(data)
}
