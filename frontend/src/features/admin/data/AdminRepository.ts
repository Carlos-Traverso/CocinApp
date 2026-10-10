import type { AdminStorageData } from './localAdminStore'
import { getAdminData, saveAdminData } from './localAdminStore'
import { createCategory, updateCategory, deleteCategory, restoreCategory } from './categoriesStore'
import { createUnit, updateUnit, deleteUnit, restoreUnit } from './unitsStore'
import { createIngredient, updateIngredient, deleteIngredient, restoreIngredient } from './ingredientsStore'
import { createRecipe, createSeedRecipeOverride, deleteRecipe, duplicateRecipe, setRecipeActive, setRecipeFeatured, updateRecipe, type AdminRecipeInput } from './recipesStore'
import type { AdminRecipe } from '../domain/adminModels'
import type { Recipe } from '../../recipes/domain/Recipe'
import type { DeleteResult } from './deleteResult'

export type { DeleteResult } from './deleteResult'

export interface AdminRepository {
  getCatalog(): Promise<AdminStorageData>
  saveCatalog(data: AdminStorageData): Promise<void>
  createCategory(name: string, active?: boolean): Promise<string>
  updateCategory(id: string, name: string, active?: boolean): Promise<void>
  deleteCategory(id: string): Promise<DeleteResult>
  restoreCategory(id: string): Promise<void>
  createUnit(name: string, abbreviation: string, dimension: string, baseUnitId?: string, multiplier?: number, active?: boolean): Promise<string>
  updateUnit(id: string, name: string, abbreviation: string, dimension: string, baseUnitId?: string, multiplier?: number, active?: boolean): Promise<void>
  deleteUnit(id: string): Promise<DeleteResult>
  restoreUnit(id: string): Promise<void>
  createIngredient(name: string, categoryId: string, baseUnitId: string, active?: boolean): Promise<string>
  updateIngredient(id: string, name: string, categoryId: string, baseUnitId: string, active?: boolean): Promise<void>
  deleteIngredient(id: string): Promise<DeleteResult>
  restoreIngredient(id: string): Promise<void>
  createRecipe(recipe: AdminRecipeInput): Promise<string>
  updateRecipe(id: string, recipe: AdminRecipeInput): Promise<void>
  deleteRecipe(id: string): Promise<DeleteResult>
  duplicateRecipe(id: string): Promise<string>
  setRecipeActive(id: string, active: boolean): Promise<void>
  setRecipeFeatured(id: string, featured: boolean): Promise<void>
  createSeedRecipeOverride(recipe: Recipe): Promise<AdminRecipe>
}

// Delayed local mock keeps the async boundary identical to a future HTTP repository.
export const adminRepository: AdminRepository = {
  async getCatalog() { await Promise.resolve(); return getAdminData() },
  async saveCatalog(data) { await Promise.resolve(); saveAdminData(data) },
  async createCategory(...args) { await Promise.resolve(); return createCategory(...args) },
  async updateCategory(...args) { await Promise.resolve(); updateCategory(...args) },
  async deleteCategory(...args) { await Promise.resolve(); return deleteCategory(...args) },
  async restoreCategory(...args) { await Promise.resolve(); restoreCategory(...args) },
  async createUnit(...args) { await Promise.resolve(); return createUnit(...args) },
  async updateUnit(...args) { await Promise.resolve(); updateUnit(...args) },
  async deleteUnit(...args) { await Promise.resolve(); return deleteUnit(...args) },
  async restoreUnit(...args) { await Promise.resolve(); restoreUnit(...args) },
  async createIngredient(...args) { await Promise.resolve(); return createIngredient(...args) },
  async updateIngredient(...args) { await Promise.resolve(); updateIngredient(...args) },
  async deleteIngredient(...args) { await Promise.resolve(); return deleteIngredient(...args) },
  async restoreIngredient(...args) { await Promise.resolve(); restoreIngredient(...args) },
  async createRecipe(...args) { await Promise.resolve(); return createRecipe(...args) },
  async updateRecipe(...args) { await Promise.resolve(); updateRecipe(...args) },
  async deleteRecipe(...args) { await Promise.resolve(); return deleteRecipe(...args) },
  async duplicateRecipe(...args) { await Promise.resolve(); return duplicateRecipe(...args) },
  async setRecipeActive(...args) { await Promise.resolve(); setRecipeActive(...args) },
  async setRecipeFeatured(...args) { await Promise.resolve(); setRecipeFeatured(...args) },
  async createSeedRecipeOverride(...args) { await Promise.resolve(); return createSeedRecipeOverride(...args) },
}
