import { getAdminData, saveAdminData } from './localAdminStore'

export function createIngredient(name: string, categoryId: string, baseUnitId: string): string {
  const data = getAdminData()
  if (data.ingredients.some(i => i.name.toLowerCase() === name.toLowerCase() && !i.isDeleted)) {
    throw new Error('El ingrediente ya existe')
  }
  const id = crypto.randomUUID()
  data.ingredients.push({ id, name, categoryId, baseUnitId, isDeleted: false })
  saveAdminData(data)
  return id
}

export function updateIngredient(id: string, name: string, categoryId: string, baseUnitId: string): void {
  const data = getAdminData()
  if (data.ingredients.some(i => i.id !== id && i.name.toLowerCase() === name.toLowerCase() && !i.isDeleted)) {
    throw new Error('El ingrediente ya existe')
  }
  const index = data.ingredients.findIndex(i => i.id === id)
  if (index !== -1) {
    data.ingredients[index] = { ...data.ingredients[index], name, categoryId, baseUnitId }
    saveAdminData(data)
  }
}

export function deleteIngredient(id: string, hasReferences: boolean): void {
  const data = getAdminData()
  const index = data.ingredients.findIndex(i => i.id === id)
  if (index !== -1) {
    if (hasReferences) {
      data.ingredients[index].isDeleted = true
    } else {
      data.ingredients.splice(index, 1)
    }
    saveAdminData(data)
  }
}
