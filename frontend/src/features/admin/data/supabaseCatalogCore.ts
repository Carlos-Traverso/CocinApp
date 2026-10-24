import type { AdminCategory, AdminIngredient, AdminUnit } from '../domain/adminModels'
import { isSupabaseConfigured, supabase } from '../../../shared/data/supabaseClient'

/** The shared catalog data stored remotely; recipes are intentionally excluded. */
export interface CatalogCore {
  categories: AdminCategory[]
  units: AdminUnit[]
  ingredients: AdminIngredient[]
}

export type RemoteCatalogRead =
  | { status: 'unavailable' }
  | { status: 'empty' }
  | { status: 'found'; catalog: CatalogCore; version: number }

function readVersion(value: unknown): number {
  if (typeof value !== 'number' || !Number.isInteger(value) || value < 1) {
    throw new Error('La versión del catálogo compartido no es válida.')
  }
  return value
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return value !== null && typeof value === 'object' && !Array.isArray(value)
}

function readCategories(value: unknown): AdminCategory[] | undefined {
  if (!Array.isArray(value)) return undefined
  const result: AdminCategory[] = []
  for (const entry of value) {
    if (!isRecord(entry) || typeof entry.id !== 'string' || typeof entry.name !== 'string'
      || typeof entry.active !== 'boolean' || typeof entry.isDeleted !== 'boolean') return undefined
    result.push({ id: entry.id, name: entry.name, active: entry.active, isDeleted: entry.isDeleted })
  }
  return result
}

function readUnits(value: unknown): AdminUnit[] | undefined {
  if (!Array.isArray(value)) return undefined
  const result: AdminUnit[] = []
  for (const entry of value) {
    if (!isRecord(entry) || typeof entry.id !== 'string' || typeof entry.name !== 'string'
      || typeof entry.abbreviation !== 'string'
      || (entry.dimension !== 'masa' && entry.dimension !== 'volumen' && entry.dimension !== 'conteo')
      || typeof entry.active !== 'boolean' || typeof entry.isDeleted !== 'boolean'
      || (entry.baseUnitId !== undefined && typeof entry.baseUnitId !== 'string')
      || (entry.equivalenceMultiplier !== undefined && (typeof entry.equivalenceMultiplier !== 'number' || !Number.isFinite(entry.equivalenceMultiplier)))) return undefined
    result.push({
      id: entry.id,
      name: entry.name,
      abbreviation: entry.abbreviation,
      dimension: entry.dimension,
      baseUnitId: entry.baseUnitId,
      equivalenceMultiplier: entry.equivalenceMultiplier,
      active: entry.active,
      isDeleted: entry.isDeleted,
    })
  }
  return result
}

function readIngredients(value: unknown): AdminIngredient[] | undefined {
  if (!Array.isArray(value)) return undefined
  const result: AdminIngredient[] = []
  for (const entry of value) {
    if (!isRecord(entry) || typeof entry.id !== 'string' || typeof entry.name !== 'string'
      || typeof entry.categoryId !== 'string' || typeof entry.baseUnitId !== 'string'
      || typeof entry.active !== 'boolean' || typeof entry.isDeleted !== 'boolean') return undefined
    result.push({
      id: entry.id,
      name: entry.name,
      categoryId: entry.categoryId,
      baseUnitId: entry.baseUnitId,
      active: entry.active,
      isDeleted: entry.isDeleted,
    })
  }
  return result
}

function parseCatalog(value: unknown): CatalogCore {
  if (!isRecord(value)) throw new Error('El catálogo compartido de Supabase tiene un formato inválido.')
  const categories = readCategories(value.categories)
  const units = readUnits(value.units)
  const ingredients = readIngredients(value.ingredients)
  if (!categories || !units || !ingredients) throw new Error('El catálogo compartido de Supabase tiene datos inválidos.')
  return { categories, units, ingredients }
}

/** Returns `empty` for a configured project without a catalog row, preserving local data for first upload. */
export async function readSupabaseCatalogCore(): Promise<RemoteCatalogRead> {
  if (!isSupabaseConfigured || !supabase) return { status: 'unavailable' }
  const { data, error } = await supabase
    .from('catalog_core')
    .select('payload, version')
    .eq('catalog_key', 'main')
    .maybeSingle()
  if (error) throw error
  if (!data) return { status: 'empty' }
  return { status: 'found', catalog: parseCatalog(data.payload), version: readVersion(data.version) }
}

/** Saves only if the row still has the version observed when it was read. */
export async function writeSupabaseCatalogCore(catalog: CatalogCore, expectedVersion: number | null): Promise<number> {
  if (!isSupabaseConfigured || !supabase) throw new Error('Supabase no está configurado.')
  const { data, error } = await supabase.rpc('admin_save_catalog_core', {
    p_expected_version: expectedVersion,
    p_payload: catalog,
  })
  if (error) throw new Error(error.code === '40001'
    ? error.message
    : 'No se pudo guardar el catálogo en Supabase.', { cause: error })
  return readVersion(data)
}
