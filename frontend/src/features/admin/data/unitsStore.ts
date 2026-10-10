import { getAdminData, saveAdminData } from './localAdminStore'
import { hasAdminReferences } from './adminReferences'
import { validateUnit } from '../domain/adminValidation'
import type { DeleteResult } from './deleteResult'

export function createUnit(name: string, abbreviation: string, dimension: string, baseUnitId?: string, equivalenceMultiplier?: number, active = true): string {
  const data = getAdminData()
  const unit = validateUnit({ name, abbreviation, dimension: dimension as 'masa' | 'volumen' | 'conteo', baseUnitId, equivalenceMultiplier, active }, data.units)
  const id = crypto.randomUUID()
  data.units.push({ ...unit, id, isDeleted: false })
  saveAdminData(data)
  return id
}

export function updateUnit(id: string, name: string, abbreviation: string, dimension: string, baseUnitId?: string, equivalenceMultiplier?: number, active?: boolean): void {
  const data = getAdminData()
  const index = data.units.findIndex(u => u.id === id)
  const unit = validateUnit({ name, abbreviation, dimension: dimension as 'masa' | 'volumen' | 'conteo', baseUnitId, equivalenceMultiplier, active: active ?? data.units[index]?.active ?? true }, data.units, id)
  if (index !== -1) {
    data.units[index] = { ...data.units[index], ...unit }
    saveAdminData(data)
  }
}

export function deleteUnit(id: string): DeleteResult {
  const data = getAdminData()
  const index = data.units.findIndex(u => u.id === id)
  if (index === -1) return 'not-found'
  const unit = data.units[index]
  if (unit.isDeleted) return 'deactivated'
  const deactivated = hasAdminReferences('unit', id, unit.abbreviation)
  if (deactivated) {
    unit.isDeleted = true
    unit.active = false
  } else data.units.splice(index, 1)
  saveAdminData(data)
  return deactivated ? 'deactivated' : 'deleted'
}

export function restoreUnit(id: string): void {
  const data = getAdminData()
  const unit = data.units.find((entry) => entry.id === id)
  if (!unit) return
  unit.isDeleted = false
  unit.active = true
  saveAdminData(data)
}

export function setUnitActive(id: string, active: boolean): void {
  const data = getAdminData()
  const unit = data.units.find((entry) => entry.id === id)
  if (!unit) return
  unit.active = active
  saveAdminData(data)
}
