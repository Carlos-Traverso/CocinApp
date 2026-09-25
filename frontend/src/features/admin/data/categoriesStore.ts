import { getAdminData, saveAdminData } from './localAdminStore'

export function createCategory(name: string): string {
  const data = getAdminData()
  if (data.categories.some(c => c.name.toLowerCase() === name.toLowerCase() && !c.isDeleted)) {
    throw new Error('La categoría ya existe')
  }
  const id = crypto.randomUUID()
  data.categories.push({ id, name, isDeleted: false })
  saveAdminData(data)
  return id
}

export function updateCategory(id: string, name: string): void {
  const data = getAdminData()
  if (data.categories.some(c => c.id !== id && c.name.toLowerCase() === name.toLowerCase() && !c.isDeleted)) {
    throw new Error('La categoría ya existe')
  }
  const index = data.categories.findIndex(c => c.id === id)
  if (index !== -1) {
    data.categories[index].name = name
    saveAdminData(data)
  }
}

export function deleteCategory(id: string, hasReferences: boolean): void {
  const data = getAdminData()
  const index = data.categories.findIndex(c => c.id === id)
  if (index !== -1) {
    if (hasReferences) {
      data.categories[index].isDeleted = true
    } else {
      data.categories.splice(index, 1)
    }
    saveAdminData(data)
  }
}
