import type { AdminStorageData } from './localAdminStore'
import { getAdminData, saveAdminData } from './localAdminStore'
import { createCategory, updateCategory, deleteCategory, restoreCategory } from './categoriesStore'
import { createUnit, updateUnit, deleteUnit, restoreUnit } from './unitsStore'
import { createIngredient, updateIngredient, deleteIngredient, restoreIngredient } from './ingredientsStore'
import { createRecipe, createSeedRecipeOverride, deleteRecipe, duplicateRecipe, setRecipeActive, setRecipeFeatured, updateRecipe, type AdminRecipeInput } from './recipesStore'
import type { AdminRecipe } from '../domain/adminModels'
import type { Recipe } from '../../recipes/domain/Recipe'
import type { DeleteResult } from './deleteResult'
import { readSupabaseCatalogCore, writeSupabaseCatalogCore } from './supabaseCatalogCore'
import { supabase } from '../../../shared/data/supabaseClient'
import { readSupabaseRecipes, writeSupabaseRecipes } from './supabaseRecipes'

export type { DeleteResult } from './deleteResult'

interface CatalogSnapshot {
  data: AdminStorageData
  coreVersion: number | null
  recipesVersion: number | null
}

async function isRemoteAdmin(): Promise<boolean> {
  if (!supabase) return false
  const { data, error } = await supabase.rpc('current_app_role')
  if (error) throw error
  return data === 'ADMIN'
}

async function loadCatalogSnapshot(): Promise<CatalogSnapshot> {
  const local = getAdminData()
  const [remoteCore, remoteRecipes] = await Promise.all([readSupabaseCatalogCore(), readSupabaseRecipes()])
  if (remoteCore.status === 'unavailable') return { data: local, coreVersion: null, recipesVersion: null }

  const isAdmin = await isRemoteAdmin()
  if (remoteCore.status === 'empty' || remoteRecipes.status === 'empty') {
    if (!isAdmin) throw new Error('El administrador todavía no inicializó el catálogo compartido. Ingresá primero con la cuenta administradora.')
  }

  let coreVersion = remoteCore.status === 'found' ? remoteCore.version : null
  let recipesVersion = remoteRecipes.status === 'found' ? remoteRecipes.version : null
  if (remoteCore.status === 'empty') coreVersion = await writeSupabaseCatalogCore(local, null)
  if (remoteRecipes.status === 'empty') recipesVersion = await writeSupabaseRecipes(local.recipes, null)

  const catalog = {
    ...local,
    ...(remoteCore.status === 'found' ? remoteCore.catalog : {}),
    recipes: remoteRecipes.status === 'found' ? remoteRecipes.recipes : local.recipes,
  }
  saveAdminData(catalog)
  return { data: catalog, coreVersion, recipesVersion }
}

async function loadCatalog(): Promise<AdminStorageData> {
  return (await loadCatalogSnapshot()).data
}

async function mutateCore<T>(mutation: () => T): Promise<T> {
  if (!supabase) return mutation()
  const snapshot = await loadCatalogSnapshot()
  const previous = snapshot.data
  if (!await isRemoteAdmin()) throw new Error('Solo una cuenta administradora puede modificar el catálogo.')
  const result = mutation()
  const updated = getAdminData()
  try {
    await writeSupabaseCatalogCore(updated, snapshot.coreVersion)
    return result
  } catch (error) {
    saveAdminData(previous)
    throw error
  }
}

async function mutateRecipes<T>(mutation: () => T): Promise<T> {
  if (!supabase) return mutation()
  const snapshot = await loadCatalogSnapshot()
  const previous = snapshot.data
  if (!await isRemoteAdmin()) throw new Error('Solo una cuenta administradora puede modificar las recetas.')
  const result = mutation()
  const updated = getAdminData()
  try {
    await writeSupabaseRecipes(updated.recipes, snapshot.recipesVersion)
    return result
  } catch (error) {
    saveAdminData(previous)
    throw error
  }
}

export interface AdminRepository {
  getCatalog(): Promise<AdminStorageData>
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
  async getCatalog() { return loadCatalog() },
  async createCategory(...args) { return mutateCore(() => createCategory(...args)) },
  async updateCategory(...args) { return mutateCore(() => updateCategory(...args)) },
  async deleteCategory(...args) { return mutateCore(() => deleteCategory(...args)) },
  async restoreCategory(...args) { return mutateCore(() => restoreCategory(...args)) },
  async createUnit(...args) { return mutateCore(() => createUnit(...args)) },
  async updateUnit(...args) { return mutateCore(() => updateUnit(...args)) },
  async deleteUnit(...args) { return mutateCore(() => deleteUnit(...args)) },
  async restoreUnit(...args) { return mutateCore(() => restoreUnit(...args)) },
  async createIngredient(...args) { return mutateCore(() => createIngredient(...args)) },
  async updateIngredient(...args) { return mutateCore(() => updateIngredient(...args)) },
  async deleteIngredient(...args) { return mutateCore(() => deleteIngredient(...args)) },
  async restoreIngredient(...args) { return mutateCore(() => restoreIngredient(...args)) },
  async createRecipe(...args) { return mutateRecipes(() => createRecipe(...args)) },
  async updateRecipe(...args) { return mutateRecipes(() => updateRecipe(...args)) },
  async deleteRecipe(...args) { return mutateRecipes(() => deleteRecipe(...args)) },
  async duplicateRecipe(...args) { return mutateRecipes(() => duplicateRecipe(...args)) },
  async setRecipeActive(...args) { return mutateRecipes(() => setRecipeActive(...args)) },
  async setRecipeFeatured(...args) { return mutateRecipes(() => setRecipeFeatured(...args)) },
  async createSeedRecipeOverride(...args) { return mutateRecipes(() => createSeedRecipeOverride(...args)) },
}
