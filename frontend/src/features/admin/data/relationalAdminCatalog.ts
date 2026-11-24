import type { AdminRepository } from './AdminRepository'
import type { AdminCategory, AdminIngredient, AdminUnit } from '../domain/adminModels'
import type { DeleteResult } from './deleteResult'
import { supabase } from '../../../shared/data/supabaseClient'

type Kind = 'category' | 'unit' | 'ingredient'
type Row = Record<string, unknown>
type Core = { categories: AdminCategory[]; units: AdminUnit[]; ingredients: AdminIngredient[] }

const entityFields = {
  category: ['name'],
  unit: ['name', 'abbreviation', 'dimension', 'base_unit_id', 'equivalence_multiplier'],
  ingredient: ['name', 'category_id', 'base_unit_id'],
} satisfies Record<Kind, string[]>

function fail(message: string): never { throw new Error(message) }
function dimension(value: string): 'mass' | 'volume' | 'count' {
  const mapped = ({ masa: 'mass', volumen: 'volume', conteo: 'count' } as const)[value as 'masa' | 'volumen' | 'conteo']
  if (!mapped) return fail('La dimensión de la unidad no es válida.')
  return mapped
}
function fromDimension(value: unknown): AdminUnit['dimension'] {
  if (value === 'mass') return 'masa'
  if (value === 'volume') return 'volumen'
  if (value === 'count') return 'conteo'
  return fail('Supabase devolvió una dimensión de unidad inválida.')
}
function mapCategory(row: Row): AdminCategory {
  if (typeof row.id !== 'string' || typeof row.name !== 'string' || typeof row.active !== 'boolean' || typeof row.is_deleted !== 'boolean' || typeof row.version !== 'number') return fail('Supabase devolvió una categoría inválida.')
  return { id: row.id, name: row.name, active: row.active, isDeleted: row.is_deleted }
}
function mapUnit(row: Row): AdminUnit {
  if (typeof row.id !== 'string' || typeof row.name !== 'string' || typeof row.abbreviation !== 'string' || typeof row.active !== 'boolean' || typeof row.is_deleted !== 'boolean' || typeof row.version !== 'number') return fail('Supabase devolvió una unidad inválida.')
  const result: AdminUnit = { id: row.id, name: row.name, abbreviation: row.abbreviation, dimension: fromDimension(row.dimension), active: row.active, isDeleted: row.is_deleted }
  if (typeof row.base_unit_id === 'string') result.baseUnitId = row.base_unit_id
  if (typeof row.equivalence_multiplier === 'number') result.equivalenceMultiplier = row.equivalence_multiplier
  return result
}
function mapIngredient(row: Row): AdminIngredient {
  if (typeof row.id !== 'string' || typeof row.name !== 'string' || typeof row.category_id !== 'string' || typeof row.base_unit_id !== 'string' || typeof row.active !== 'boolean' || typeof row.is_deleted !== 'boolean' || typeof row.version !== 'number') return fail('Supabase devolvió un ingrediente inválido.')
  return { id: row.id, name: row.name, categoryId: row.category_id, baseUnitId: row.base_unit_id, active: row.active, isDeleted: row.is_deleted }
}

export interface RelationalAdminOptions { getClient?: () => NonNullable<typeof supabase> }

export function createRelationalAdminCatalog(options: RelationalAdminOptions = {}) {
  const getClient = options.getClient ?? (() => supabase)
  const baselines = new Map<Kind, Map<string, { row: Row; version: number }>>()
  const pendingCreateIds = new Map<string, string>()
  let baselineToken: string | undefined
  let readGeneration = 0
  async function create(kind: Kind, payload: Row): Promise<string> {
    const { token, verify } = await authorized()
    const key = `${token}:${kind}:${JSON.stringify(payload)}`
    await verify()
    const id = pendingCreateIds.get(key) ?? crypto.randomUUID()
    pendingCreateIds.set(key, id)
    await save(kind, { id, ...payload, is_deleted: false }, 0, token)
    pendingCreateIds.delete(key)
    return id
  }
  async function authorized() {
    const client = getClient()
    if (!client) fail('Supabase no está configurado.')
    const { data: before, error: sessionError } = await client.auth.getSession()
    if (sessionError || !before.session?.access_token || !before.session.user.id) fail('La sesión administrativa no está disponible.')
    const token = before.session.access_token
    const verify = async () => {
      const { data, error } = await client.auth.getSession()
      if (error || data.session?.access_token !== token) fail('La sesión cambió durante la operación. Volvé a cargar el catálogo.')
    }
    const { data: role, error } = await client.rpc('current_app_role')
    await verify()
    if (error) throw error
    if (role !== 'ADMIN') fail('Solo una cuenta administradora puede gestionar el catálogo.')
    return { client, verify, token }
  }
  async function readTable(client: NonNullable<typeof supabase>, table: string, verify: () => Promise<void>): Promise<Row[]> {
    const rows: Row[] = []
    for (let offset = 0; ; offset += 500) {
      const { data, error } = await client.from(table).select('*').order('id').range(offset, offset + 499)
      await verify()
      if (error) throw error
      const page = data as Row[] | null
      if (!page) fail('No se pudo leer el catálogo administrativo.')
      rows.push(...page)
      if (page.length < 500) return rows
    }
  }
  async function getCatalogCore(): Promise<Core> {
    const { client, verify, token } = await authorized()
    const generation = ++readGeneration
    const [categories, units, ingredients] = await Promise.all([
      readTable(client, 'categorias', verify), readTable(client, 'unidades', verify), readTable(client, 'ingredientes', verify),
    ])
    const core = { categories: categories.map(mapCategory), units: units.map(mapUnit), ingredients: ingredients.map(mapIngredient) }
    if (generation === readGeneration) {
      baselineToken = token
      baselines.set('category', new Map(categories.map((row) => [String(row.id), { row, version: Number(row.version) }])))
      baselines.set('unit', new Map(units.map((row) => [String(row.id), { row, version: Number(row.version) }])))
      baselines.set('ingredient', new Map(ingredients.map((row) => [String(row.id), { row, version: Number(row.version) }])))
    }
    return core
  }
  async function save(kind: Kind, entity: Row, expectedVersion: number, expectedToken?: string): Promise<Row> {
    const { client, verify, token } = await authorized()
    if (expectedToken && token !== expectedToken || expectedVersion > 0 && baselineToken !== token) fail('La sesión cambió desde que cargaste el catálogo. Volvé a cargarlo.')
    const rpc = `admin_put_${kind}`
    const { data, error } = await client.rpc(rpc, { p_entity: entity, p_expected_version: expectedVersion })
    await verify()
    if (error) throw new Error(error.code === '40001' ? 'El registro cambió desde que lo cargaste. Recargá el catálogo y volvé a intentarlo.' : error.message || 'No se pudo guardar el registro.', { cause: error })
    if (!data || typeof data !== 'object') fail('Supabase devolvió una respuesta de guardado inválida.')
    return data as Row
  }
  async function update(kind: Kind, id: string, fields: Row, active?: boolean): Promise<void> {
    const current = baselines.get(kind)?.get(id)
    if (!current) throw new Error('No se encontró el registro en el catálogo cargado. Volvé a cargarlo.')
    await save(kind, { id, ...fields, active: active ?? current.row.active, is_deleted: current.row.is_deleted }, current.version)
  }

  async function archive(kind: Kind, id: string, archived: boolean): Promise<DeleteResult> {
    const current = baselines.get(kind)?.get(id)
    if (!current) return 'not-found'
    if (archived && current.row.is_deleted) return 'deactivated'
    const fields = Object.fromEntries(entityFields[kind].map((field) => [field, current.row[field]]))
    await save(kind, { id, ...fields, active: !archived, is_deleted: archived }, current.version)
    return 'deactivated'
  }

  async function restore(kind: Kind, id: string): Promise<void> {
    if (await archive(kind, id, false) === 'not-found') throw new Error('No se encontró el registro en el catálogo cargado. Volvé a cargarlo.')
  }

  const unitFields = (name: string, abbreviation: string, dim: string, baseUnitId?: string, multiplier?: number) => ({
    name: name.trim(), abbreviation, dimension: dimension(dim), base_unit_id: baseUnitId ?? null, equivalence_multiplier: multiplier ?? null,
  })
  const ingredientFields = (name: string, categoryId: string, baseUnitId: string) => ({
    name: name.trim(), category_id: categoryId, base_unit_id: baseUnitId,
  })

  return {
    getCatalogCore,
    createCategory(name, active = true) { return create('category', { name: name.trim(), active }) },
    updateCategory(id, name, active) { return update('category', id, { name: name.trim() }, active) },
    deleteCategory(id) { return archive('category', id, true) },
    restoreCategory(id) { return restore('category', id) },
    async createUnit(name, abbreviation, dim, baseUnitId, multiplier, active = true) {
      return create('unit', { ...unitFields(name, abbreviation, dim, baseUnitId, multiplier), active })
    },
    async updateUnit(id, name, abbreviation, dim, baseUnitId, multiplier, active) {
      return update('unit', id, unitFields(name, abbreviation, dim, baseUnitId, multiplier), active)
    },
    deleteUnit(id) { return archive('unit', id, true) },
    restoreUnit(id) { return restore('unit', id) },
    createIngredient(name, categoryId, baseUnitId, active = true) {
      return create('ingredient', { ...ingredientFields(name, categoryId, baseUnitId), active })
    },
    updateIngredient(id, name, categoryId, baseUnitId, active) {
      return update('ingredient', id, ingredientFields(name, categoryId, baseUnitId), active)
    },
    deleteIngredient(id) { return archive('ingredient', id, true) },
    restoreIngredient(id) { return restore('ingredient', id) },
  } satisfies Pick<AdminRepository, 'createCategory' | 'updateCategory' | 'deleteCategory' | 'restoreCategory' | 'createUnit' | 'updateUnit' | 'deleteUnit' | 'restoreUnit' | 'createIngredient' | 'updateIngredient' | 'deleteIngredient' | 'restoreIngredient'> & { getCatalogCore: () => Promise<Core> }
}

export const relationalAdminCatalog = createRelationalAdminCatalog()
