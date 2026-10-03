import { getAdminData, saveAdminData } from './localAdminStore'
import { hasAdminReferences } from './adminReferences'
import { validateCategoryName } from '../domain/adminValidation'

export function createCategory(name: string, active = true): string {
  const data = getAdminData()
  const cleanName = validateCategoryName(name, data.categories)
  const id = crypto.randomUUID()
  data.categories.push({ id, name: cleanName, active, isDeleted: false })
  saveAdminData(data)
  return id
}

export function updateCategory(id: string, name: string, active?: boolean): void {
  const data = getAdminData()
  const cleanName = validateCategoryName(name, data.categories, id)
  const index = data.categories.findIndex(c => c.id === id)
  if (index !== -1) {
    data.categories[index].name = cleanName
    if (active !== undefined) data.categories[index].active = active
    saveAdminData(data)
  }
}

export function deleteCategory(id: string): void {
  const data = getAdminData()
  const index = data.categories.findIndex(c => c.id === id)
  if (index !== -1) {
    if (hasAdminReferences('category', id, data.categories[index].name)) {
      data.categories[index].isDeleted = true
    } else {
      data.categories.splice(index, 1)
    }
    saveAdminData(data)
  }
}

export function restoreCategory(id: string): void {
  const data = getAdminData()
  const category = data.categories.find((entry) => entry.id === id)
  if (!category) return
  category.isDeleted = false
  category.active = true
  saveAdminData(data)
}

export function setCategoryActive(id: string, active: boolean): void {
  const data = getAdminData()
  const category = data.categories.find((entry) => entry.id === id)
  if (!category) return
  category.active = active
  saveAdminData(data)
}
