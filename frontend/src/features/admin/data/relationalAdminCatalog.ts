import type { AdminRepository } from './AdminRepository'
import type { AdminCategory, AdminIngredient, AdminUnit } from '../domain/adminModels'
import type { DeleteResult } from './deleteResult'
import { supabase } from '../../../shared/data/supabaseClient'

type Kind = 'category' | 'unit' | 'ingredient'
type Row = Record<string, unknown>
type Core = { categories: AdminCategory[]; units: AdminUnit[]; ingredients: AdminIngredient[] }

function fail(message: string): never { throw new Error(message) }
function uuid(): string { return globalThis.crypto.randomUUID() }
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
  function createId(kind: Kind, payload: Row, token: string): string {
    const key = `${token}:${kind}:${JSON.stringify(payload)}`
    const existing = pendingCreateIds.get(key)
    if (existing) return existing
    const id = uuid()
    pendingCreateIds.set(key, id)
    return id
  }
  async function create(kind: Kind, payload: Row): Promise<string> {
    const { token, verify } = await authorized()
    const key = `${token}:${kind}:${JSON.stringify(payload)}`
    await verify()
    const id = createId(kind, payload, token)
    await save(kind, { id, ...payload }, 0, token)
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
  async function current(kind: Kind, id: string): Promise<{ row: Row | undefined; version: number }> {
    const found = baselines.get(kind)?.get(id)
    return { row: found?.row, version: found?.version ?? 0 }
  }
  async function putExisting(kind: Kind, id: string, updates: Row): Promise<void> {
    const found = await current(kind, id)
    if (!found.row) return
    await save(kind, { ...updates, id }, found.version)
  }
  const repo = {
    async getCatalog() { return { ...(await getCatalogCore()), recipes: [] } },
    async createCategory(name: string, active = true) { return create('category', { name: name.trim(), active, is_deleted: false }) },
    async updateCategory(id: string, name: string, active?: boolean) { const found = await current('category', id); if (!found.row) return; await save('category', { id, name: name.trim(), active: active ?? found.row.active, is_deleted: found.row.is_deleted }, found.version) },
    async deleteCategory(id: string): Promise<DeleteResult> { const found = await current('category', id); if (!found.row) return 'not-found'; if (found.row.is_deleted) return 'deactivated'; await save('category', { id, name: found.row.name, active: false, is_deleted: true }, found.version); return 'deactivated' },
    async restoreCategory(id: string) { const found = await current('category', id); if (found.row) await save('category', { id, name: found.row.name, active: true, is_deleted: false }, found.version) },
    async createUnit(name: string, abbreviation: string, dim: string, baseUnitId?: string, multiplier?: number, active = true) { return create('unit', { name: name.trim(), abbreviation, dimension: dimension(dim), base_unit_id: baseUnitId ?? null, equivalence_multiplier: multiplier ?? null, active, is_deleted: false }) },
    async updateUnit(id: string, name: string, abbreviation: string, dim: string, baseUnitId?: string, multiplier?: number, active?: boolean) { const found = await current('unit', id); if (!found.row) return; await save('unit', { id, name: name.trim(), abbreviation, dimension: dimension(dim), base_unit_id: baseUnitId ?? null, equivalence_multiplier: multiplier ?? null, active: active ?? found.row.active, is_deleted: found.row.is_deleted }, found.version) },
    async deleteUnit(id: string): Promise<DeleteResult> { const f = await current('unit', id); if (!f.row) return 'not-found'; if (f.row.is_deleted) return 'deactivated'; await save('unit', { id, name: f.row.name, abbreviation: f.row.abbreviation, dimension: f.row.dimension, base_unit_id: f.row.base_unit_id, equivalence_multiplier: f.row.equivalence_multiplier, active: false, is_deleted: true }, f.version); return 'deactivated' },
    async restoreUnit(id: string) { const f = await current('unit', id); if (f.row) await save('unit', { id, name: f.row.name, abbreviation: f.row.abbreviation, dimension: f.row.dimension, base_unit_id: f.row.base_unit_id, equivalence_multiplier: f.row.equivalence_multiplier, active: true, is_deleted: false }, f.version) },
    async createIngredient(name: string, categoryId: string, baseUnitId: string, active = true) { return create('ingredient', { name: name.trim(), category_id: categoryId, base_unit_id: baseUnitId, active, is_deleted: false }) },
    async updateIngredient(id: string, name: string, categoryId: string, baseUnitId: string, active?: boolean) { const f = await current('ingredient', id); if (!f.row) return; await save('ingredient', { id, name: name.trim(), category_id: categoryId, base_unit_id: baseUnitId, active: active ?? f.row.active, is_deleted: f.row.is_deleted }, f.version) },
    async deleteIngredient(id: string): Promise<DeleteResult> { const f = await current('ingredient', id); if (!f.row) return 'not-found'; if (f.row.is_deleted) return 'deactivated'; await save('ingredient', { id, name: f.row.name, category_id: f.row.category_id, base_unit_id: f.row.base_unit_id, active: false, is_deleted: true }, f.version); return 'deactivated' },
    async restoreIngredient(id: string) { const f = await current('ingredient', id); if (f.row) await save('ingredient', { id, name: f.row.name, category_id: f.row.category_id, base_unit_id: f.row.base_unit_id, active: true, is_deleted: false }, f.version) },
  }
  return { ...repo, getCatalogCore, putExisting } satisfies Pick<AdminRepository, 'getCatalog' | 'createCategory' | 'updateCategory' | 'deleteCategory' | 'restoreCategory' | 'createUnit' | 'updateUnit' | 'deleteUnit' | 'restoreUnit' | 'createIngredient' | 'updateIngredient' | 'deleteIngredient' | 'restoreIngredient'> & { getCatalogCore: () => Promise<Core>; putExisting: typeof putExisting }
}

export const relationalAdminCatalog = createRelationalAdminCatalog()
