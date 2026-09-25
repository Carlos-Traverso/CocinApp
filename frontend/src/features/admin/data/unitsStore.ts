import { getAdminData, saveAdminData } from './localAdminStore'

export function createUnit(name: string, abbreviation: string, dimension: string, baseUnitId?: string, equivalenceMultiplier?: number): string {
  const data = getAdminData()
  if (data.units.some(u => u.name.toLowerCase() === name.toLowerCase() && !u.isDeleted)) {
    throw new Error('La unidad ya existe')
  }
  const id = crypto.randomUUID()
  data.units.push({ id, name, abbreviation, dimension, baseUnitId, equivalenceMultiplier, isDeleted: false })
  saveAdminData(data)
  return id
}

export function updateUnit(id: string, name: string, abbreviation: string, dimension: string, baseUnitId?: string, equivalenceMultiplier?: number): void {
  const data = getAdminData()
  if (data.units.some(u => u.id !== id && u.name.toLowerCase() === name.toLowerCase() && !u.isDeleted)) {
    throw new Error('La unidad ya existe')
  }
  const index = data.units.findIndex(u => u.id === id)
  if (index !== -1) {
    data.units[index] = { ...data.units[index], name, abbreviation, dimension, baseUnitId, equivalenceMultiplier }
    saveAdminData(data)
  }
}

export function deleteUnit(id: string, hasReferences: boolean): void {
  const data = getAdminData()
  const index = data.units.findIndex(u => u.id === id)
  if (index !== -1) {
    if (hasReferences) {
      data.units[index].isDeleted = true
    } else {
      data.units.splice(index, 1)
    }
    saveAdminData(data)
  }
}
