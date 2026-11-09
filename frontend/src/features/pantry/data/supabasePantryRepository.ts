import { personalStorage } from '../../auth/data/personalStorage'
import { supabase } from '../../../shared/data/supabaseClient'
import type { PantryItem } from '../domain/pantry'
import { writePantryItems } from './localPantryStore'
import { assertPersonalDataOwner, assertPersonalDataSessionCurrent, capturePersonalDataSession } from '../../../shared/data/personalDataSession'
import type { AdminStorageData } from '../../admin/data/localAdminStore'
import type { AdminIngredient } from '../../admin/domain/adminModels'

export type RelationalPantryCatalog = Omit<AdminStorageData, 'ingredients'> & {
  ingredients: Array<AdminIngredient & { legacyId: string; relationalId: string }>
}

interface PantryRow {
  id: string
  ingredient_id: string | null
  ingredient_ref: string | null
  name: string
  category: string
  quantity: number | string
  unit: string
  minimum: number | string
  expiry: string | null
  source_shopping_ids: string[] | null
  version: number | string
}

interface PantryPage { items: PantryRow[]; total: number; as_of: string }

function getClient() {
  if (!supabase) throw new Error('Falta configurar la conexión de Supabase.')
  return supabase
}

function fromRow(row: PantryRow): PantryItem {
  if (typeof row.id !== 'string' || typeof row.name !== 'string' || typeof row.category !== 'string'
    || typeof row.unit !== 'string' || !Number.isFinite(Number(row.quantity)) || !Number.isFinite(Number(row.minimum))
    || !Number.isSafeInteger(Number(row.version)) || Number(row.version) < 1
    || row.expiry !== null && typeof row.expiry !== 'string') throw new Error('La fila de despensa no tiene un formato válido.')
  return {
    id: row.id,
    version: Number(row.version),
    ...(row.ingredient_id ? { ingredientId: row.ingredient_id } : {}),
    ...(row.ingredient_ref ? { ingredientRef: row.ingredient_ref } : {}),
    name: row.name,
    category: row.category,
    quantity: Number(row.quantity),
    unit: row.unit,
    minimum: Number(row.minimum),
    expiry: row.expiry,
    ...(row.source_shopping_ids?.length ? { sourceShoppingIds: row.source_shopping_ids } : {}),
  }
}

export function toRelationalPantrySnapshot(item: PantryItem) {
  // Legacy catalog identifiers are preserved as text. A relational UUID is
  // never guessed from a legacy ID; the RPC can safely retain existing refs.
  return {
    id: item.id,
    name: item.name.trim(),
    category: item.category,
    quantity: item.quantity,
    unit: item.unit,
    minimum: item.minimum,
    expiry: item.expiry || null,
    ingredient_id: item.ingredientId ?? null,
    ...(item.ingredientRef ? { ingredient_ref: item.ingredientRef } : {}),
  }
}

function snapshot(item: PantryItem) { return toRelationalPantrySnapshot(item) }
function snapshotKey(item: PantryItem): string { return JSON.stringify(snapshot(item)) }

export function createSupabasePantryRepository(dependencies: {
  getClient: typeof getClient
  captureSession: typeof capturePersonalDataSession
  assertOwner: typeof assertPersonalDataOwner
  assertSession: typeof assertPersonalDataSessionCurrent
  storage: typeof personalStorage
}) {
  const { getClient, storage: personalStorage } = dependencies
  const capturePersonalDataSession = dependencies.captureSession
  const assertPersonalDataOwner = dependencies.assertOwner
  const assertPersonalDataSessionCurrent = dependencies.assertSession
  async function requireOwner(session: ReturnType<typeof capturePersonalDataSession>): Promise<string> {
    assertPersonalDataSessionCurrent(session)
    const { data: { user }, error } = await getClient().auth.getUser()
    if (error) throw error
    if (!user) throw new Error('Iniciá sesión para acceder a tu despensa.')
    assertPersonalDataOwner(session, user.id)
    return user.id
  }
  let loadedUser: string | null = null
  let loadedSession: ReturnType<typeof capturePersonalDataSession> | null = null
  let loadedIds = new Set<string>()
  let loadedVersions = new Map<string, number>()
  let loadedSnapshots = new Map<string, string>()
  let listGeneration = 0
  return {
  async getCatalog(): Promise<RelationalPantryCatalog> {
    const session = capturePersonalDataSession()
    const userId = await requireOwner(session)
    const client = getClient()
    const [categories, units, ingredients] = await Promise.all([
      client.from('categorias').select('id,name,active,is_deleted').eq('active', true).eq('is_deleted', false).order('name'),
      client.from('unidades').select('id,name,abbreviation,dimension,base_unit_id,equivalence_multiplier,active,is_deleted').eq('active', true).eq('is_deleted', false).order('name'),
      client.from('ingredientes').select('id,legacy_id,name,category_id,base_unit_id,active,is_deleted').eq('active', true).eq('is_deleted', false).order('name'),
    ])
    if (categories.error) throw categories.error
    if (units.error) throw units.error
    if (ingredients.error) throw ingredients.error
    assertPersonalDataOwner(session, userId)
    return {
      categories: (categories.data ?? []).map((row) => ({ id: row.id, name: row.name, active: row.active, isDeleted: row.is_deleted })),
      units: (units.data ?? []).map((row) => ({
        id: row.id, name: row.name, abbreviation: row.abbreviation,
        dimension: row.dimension === 'mass' ? 'masa' as const : row.dimension === 'volume' ? 'volumen' as const : 'conteo' as const,
        baseUnitId: row.base_unit_id ?? undefined, equivalenceMultiplier: row.equivalence_multiplier ?? undefined,
        active: row.active, isDeleted: row.is_deleted,
      })),
      ingredients: (ingredients.data ?? []).map((row) => ({
        id: row.legacy_id ?? row.id, legacyId: row.legacy_id ?? row.id, relationalId: row.id, name: row.name, categoryId: row.category_id,
        baseUnitId: row.base_unit_id, active: row.active, isDeleted: row.is_deleted,
      })),
      recipes: [],
    }
  },

  async list(): Promise<PantryItem[]> {
    const session = capturePersonalDataSession()
    const generation = ++listGeneration
    const userId = await requireOwner(session)
    const client = getClient()
    const items: PantryItem[] = []
    let offset = 0
    let total = 0
    do {
      const { data, error } = await client.rpc('get_my_pantry', {
        p_search: null, p_category: null, p_status: 'all', p_limit: 100, p_offset: offset,
      })
      if (error) throw error
      assertPersonalDataOwner(session, userId)
      const page = data as PantryPage
      if (!page || !Array.isArray(page.items) || !Number.isInteger(page.total)) throw new Error('La respuesta de la despensa no es válida.')
      if (!Number.isSafeInteger(page.total) || page.total < 0 || items.length + page.items.length > page.total) throw new Error('El total de la despensa no coincide con sus páginas.')
      if (page.items.some((row) => !Number.isSafeInteger(Number(row.version)) || Number(row.version) < 1)) throw new Error('La versión recibida no se puede verificar.')
      if (new Set([...items.map((item) => item.id), ...page.items.map((row) => row.id)]).size !== items.length + page.items.length) throw new Error('La página repite ingredientes de la despensa.')
      items.push(...page.items.map(fromRow))
      total = page.total
      offset += page.items.length
      if (page.items.length === 0) break
    } while (offset < total)
    if (items.length !== total) throw new Error('No se pudo cargar la despensa completa. Volvé a intentarlo.')
    assertPersonalDataOwner(session, userId)
    if (generation !== listGeneration) throw new Error('La sesión o la carga de despensa cambió. Volvé a cargarla.')
    loadedUser = userId
    loadedSession = session
    loadedIds = new Set(items.map((item) => item.id))
    loadedVersions = new Map(items.map((item) => [item.id, item.version ?? 0]))
    loadedSnapshots = new Map(items.map((item) => [item.id, snapshotKey(item)]))
    writePantryItems(items, personalStorage, false)
    return items
  },

  async save(items: PantryItem[]): Promise<void> {
    const session = capturePersonalDataSession()
    const userId = await requireOwner(session)
    if (loadedUser !== userId || !loadedSession
      || loadedSession.token !== session.token
      || loadedSession.localRevision !== session.localRevision
      || loadedSession.supabaseRevision !== session.supabaseRevision) throw new Error('Recargá la despensa antes de guardar los cambios.')
    const client = getClient()
    const changed = items.filter((item) => !loadedSnapshots.has(item.id) || snapshotKey(item) !== loadedSnapshots.get(item.id))
    if (changed.length > 200) throw new Error('La despensa contiene demasiados cambios para guardar de una vez.')
    const retained = new Set(items.map((item) => item.id))
    const removed = [...loadedIds].filter((id) => !retained.has(id))
    if ((changed.length > 0 && removed.length > 0) || removed.length > 1) throw new Error('Guardá una eliminación por vez y luego volvé a intentar los otros cambios.')
    const upserts = changed.map((item) => {
      const expected = item.version ?? loadedVersions.get(item.id) ?? 0
      if (!Number.isSafeInteger(expected) || expected < 0) throw new Error('La versión de un ingrediente no se puede verificar. Recargá la despensa.')
      return { item: snapshot(item), expected_version: expected }
    })
    if (upserts.length > 0) {
      let response
      try { response = await client.rpc('put_my_pantry_items', { p_items: upserts }) }
      catch (error) { loadedUser = null; throw error }
      const { data, error } = response
      if (error) { loadedUser = null; throw error }
      assertPersonalDataOwner(session, userId)
      if (!Array.isArray(data) || data.length !== changed.length) { loadedUser = null; throw new Error('La confirmación de la despensa está incompleta.') }
      const expectedIds = new Set(changed.map((item) => item.id))
      if (data.some((row) => !row || typeof row !== 'object' || !expectedIds.has((row as PantryRow).id))
        || new Set((data as PantryRow[]).map((row) => row.id)).size !== changed.length) { loadedUser = null; throw new Error('La confirmación de la despensa no coincide con los cambios enviados.') }
      const saved = (data as PantryRow[]).map((row) => {
        try { return fromRow(row) } catch (error) { loadedUser = null; throw error }
      })
      for (const result of saved) {
        const version = result.version
        if (typeof version !== 'number' || !Number.isSafeInteger(version) || version < 1) { loadedUser = null; throw new Error('La versión recibida no se puede verificar.') }
        const index = items.findIndex((item) => item.id === result.id)
        if (index < 0) { loadedUser = null; throw new Error('La respuesta contiene un ingrediente inesperado.') }
        items[index] = result
        loadedVersions.set(result.id, version)
        loadedSnapshots.set(result.id, snapshotKey(items[index]!))
        loadedIds.add(result.id)
      }
    }
    for (const id of removed) {
      if (retained.has(id)) continue
      const expected = loadedVersions.get(id)
      if (!Number.isSafeInteger(expected) || !expected) throw new Error('La versión de un ingrediente no se puede verificar. Recargá la despensa.')
      let response
      try { response = await client.rpc('delete_my_pantry_item', { p_item_id: id, p_expected_version: expected }) }
      catch (error) { loadedUser = null; throw error }
      const { error } = response
      if (error) { loadedUser = null; throw error }
      assertPersonalDataOwner(session, userId)
      loadedIds.delete(id)
      loadedVersions.delete(id)
      loadedSnapshots.delete(id)
    }
    assertPersonalDataOwner(session, userId)
    loadedIds = retained
    loadedSession = session
    loadedVersions = new Map(items.flatMap((item) => Number.isSafeInteger(item.version) ? [[item.id, item.version!] as [string, number]] : []))
    loadedSnapshots = new Map(items.map((item) => [item.id, snapshotKey(item)]))
    writePantryItems(items, personalStorage, false)
  },
  }
}

export const supabasePantryRepository = createSupabasePantryRepository({
  getClient,
  captureSession: capturePersonalDataSession,
  assertOwner: assertPersonalDataOwner,
  assertSession: assertPersonalDataSessionCurrent,
  storage: personalStorage,
})
