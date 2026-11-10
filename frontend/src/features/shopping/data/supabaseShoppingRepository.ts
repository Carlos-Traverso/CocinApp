import { supabase } from '../../../shared/data/supabaseClient'
import { capturePersonalDataSession, assertPersonalDataOwner, assertPersonalDataSessionCurrent } from '../../../shared/data/personalDataSession'
import { supabasePantryRepository } from '../../pantry/data/supabasePantryRepository'
import type { ShoppingItem, ShoppingSuggestion, ShoppingSource } from '../domain/shopping'
import { isShoppingItemTransferable, mergeShoppingSuggestions, shoppingKey } from '../domain/shopping'
import type { ShoppingRepository } from './ShoppingRepository'
import type { AdminStorageData } from '../../admin/data/localAdminStore'

interface ShoppingListRow { id: string; version: number | string; status: string }
interface ShoppingRow { id: string; ingredient_id: string | null; name_snapshot: string; category_snapshot: string; quantity: number | string; unit_id: string; unit_detail: { abbreviation: string } | null; note: string; checked: boolean; transferred_at: string | null; sources: Array<{ source: ShoppingSource }> }
interface ShoppingPage { list: ShoppingListRow | null; items: ShoppingRow[]; total: number }
const sources: ShoppingSource[] = ['manual', 'recipe', 'plan', 'favorites', 'pantry']
const dateToday = () => new Intl.DateTimeFormat('en-CA', { timeZone: 'America/Argentina/Buenos_Aires' }).format(new Date())

function client() { if (!supabase) throw new Error('Falta configurar la conexión de Supabase.'); return supabase }
function fromRow(row: ShoppingRow, catalog?: Awaited<ReturnType<typeof supabasePantryRepository.getCatalog>>): ShoppingItem {
  if (!row || typeof row.id !== 'string' || typeof row.name_snapshot !== 'string' || typeof row.category_snapshot !== 'string'
    || !Number.isFinite(Number(row.quantity)) || typeof row.unit_detail?.abbreviation !== 'string'
    || !Array.isArray(row.sources) || row.sources.some((entry) => !sources.includes(entry.source))) throw new Error('La fila de compras no tiene un formato válido.')
  const relationalIngredient = row.ingredient_id ? catalog?.ingredients.find((entry) => entry.relationalId === row.ingredient_id) : undefined
  return { id: row.id, ...(relationalIngredient ? { ingredientId: relationalIngredient.id } : {}), ...(row.ingredient_id ? { ingredientRef: row.ingredient_id } : {}), unitRef: row.unit_id,
    sourceLinks: row.sources.map((entry) => ({ source: entry.source, ...('recipe_id' in entry ? { recipe_id: (entry as { recipe_id?: string }).recipe_id } : {}), ...('plan_id' in entry ? { plan_id: (entry as { plan_id?: string }).plan_id } : {}) })), name: row.name_snapshot, category: row.category_snapshot,
    quantity: Number(row.quantity), unit: row.unit_detail.abbreviation, note: row.note ?? '', checked: row.checked,
    transferredToPantry: row.transferred_at !== null, transferredAt: row.transferred_at, sources: [...new Set(row.sources.map((entry) => entry.source))] }
}

export function createSupabaseShoppingRepository(dependencies: { getClient: typeof client; captureSession: typeof capturePersonalDataSession; assertOwner: typeof assertPersonalDataOwner; assertSession: typeof assertPersonalDataSessionCurrent; getCatalog: typeof supabasePantryRepository.getCatalog }) {
  const { getClient, captureSession, assertOwner, assertSession, getCatalog } = dependencies
  let listId: string | null = null, listVersion = 0, loadedSession: ReturnType<typeof captureSession> | null = null
  let loadedItems: ShoppingItem[] = [], generation = 0
  let saveRequiresExplicitReload = false
  let pendingTransfer: { key: string; ids: string[]; receipt: string; version: number; sessionKey: string } | null = null
  let pendingList: { id: string; sessionKey: string } | null = null
  const pendingSuggestions = new Map<string, { id: string; sessionKey: string }>()
  let cacheIdentity: string | null = null
  const sessionKey = (session: ReturnType<typeof captureSession>) => `${session.token}:${session.localRevision}:${session.supabaseRevision}`
  async function owner(session: ReturnType<typeof captureSession>) {
    assertSession(session); const { data: { user }, error } = await getClient().auth.getUser(); if (error) throw error
    if (!user) throw new Error('Iniciá sesión para acceder a tus compras.')
    assertOwner(session, user.id); return user.id
  }
  async function read() {
    const session = captureSession(), currentGeneration = ++generation, userId = await owner(session), c = getClient()
    if (cacheIdentity !== sessionKey(session)) { listId = null; listVersion = 0; loadedItems = []; loadedSession = null; pendingTransfer = null; pendingList = null; pendingSuggestions.clear(); cacheIdentity = sessionKey(session) }
    const rawItems: ShoppingRow[] = []; let offset = 0, total = 0, selected: ShoppingListRow | null = null
    do {
      const { data, error } = await c.rpc('get_my_shopping_list', { p_list_id: listId, p_limit: 100, p_offset: offset })
      if (error) throw error; assertOwner(session, userId)
      const page = data as ShoppingPage
      if (!page || !Array.isArray(page.items) || !Number.isSafeInteger(page.total) || page.total < 0) throw new Error('La respuesta de compras no es válida.')
      if (!selected) selected = page.list
      if (page.list?.id !== selected?.id || Number(page.list?.version ?? 0) !== Number(selected?.version ?? 0)) throw new Error('La lista cambió mientras se cargaban sus páginas.')
      if (page.list && (!Number.isSafeInteger(Number(page.list.version)) || Number(page.list.version) < 1)) throw new Error('La versión de la lista no se puede verificar.')
      if (offset + page.items.length > page.total || (page.items.length === 0 && offset < page.total)) throw new Error('La página de compras está incompleta.')
      rawItems.push(...page.items); total = page.total; offset += page.items.length
    } while (offset < total)
    if (rawItems.length !== total || new Set(rawItems.map((item) => item.id)).size !== rawItems.length) throw new Error('No se pudo cargar la lista completa.')
    assertOwner(session, userId); if (currentGeneration !== generation) throw new Error('La lista o la sesión cambió durante la carga. Volvé a cargarla.')
    const catalog = await getCatalog()
    assertOwner(session, userId)
    if (currentGeneration !== generation) throw new Error('La lista o la sesión cambió durante la carga. Volvé a cargarla.')
    const items = rawItems.map((item) => fromRow(item, catalog))
    if (!selected) { listId = null; listVersion = 0 } else { listId = selected.id; listVersion = Number(selected.version) }
    loadedItems = items.map((item) => ({ ...item, sources: [...item.sources], sourceLinks: item.sourceLinks?.map((entry) => ({ ...entry })) })); loadedSession = session
    return items
  }
  async function ensureList(session: ReturnType<typeof captureSession>) {
    if (listId) return listId
    const key = sessionKey(session)
    if (pendingList?.sessionKey !== key) pendingList = { id: crypto.randomUUID(), sessionKey: key }
    const id = pendingList.id, response = await getClient().rpc('create_my_shopping_list', { p_list_id: id, p_name: 'Lista de compras', p_plan_id: null })
    if (response.error) throw response.error; const row = response.data as ShoppingListRow
    assertSession(session); if (!row || row.id !== id || !Number.isSafeInteger(Number(row.version))) throw new Error('No se pudo confirmar la lista de compras.')
    listId = id; listVersion = Number(row.version); pendingList = null; return id
  }
  async function mutate(name: string, args: Record<string, unknown>) {
    if (!listId || !loadedSession || loadedSession.token !== captureSession().token || loadedSession.localRevision !== captureSession().localRevision || loadedSession.supabaseRevision !== captureSession().supabaseRevision) throw new Error('Recargá la lista antes de guardar los cambios.')
    const session = captureSession(), userId = await owner(session)
    let response: Awaited<ReturnType<ReturnType<typeof getClient>['rpc']>>
    try { response = await getClient().rpc(name, { ...args, p_list_id: listId, p_expected_version: listVersion }) }
    catch (error) { loadedSession = null; saveRequiresExplicitReload = true; throw error }
    const { data, error } = response
    if (error) { loadedSession = null; saveRequiresExplicitReload = true; throw error } assertOwner(session, userId)
    const row = data as ShoppingListRow
    if (!row || row.id !== listId || !Number.isSafeInteger(Number(row.version)) || Number(row.version) < listVersion) { loadedSession = null; saveRequiresExplicitReload = true; throw new Error('La confirmación de compras no es válida.') }
    listVersion = Number(row.version)
  }
  async function save(items: ShoppingItem[]) {
    const session = captureSession();
    if (cacheIdentity !== null && cacheIdentity !== sessionKey(session)) throw new Error('La sesión cambió. Recargá las compras antes de guardar los cambios.')
    if (saveRequiresExplicitReload) throw new Error('La lista cambió. Recargá las compras antes de guardar los cambios.')
    if (!loadedSession) await read()
    assertSession(session)
    await ensureList(session)
    const before = new Map(loadedItems.map((item) => [item.id, item])), after = new Map(items.map((item) => [item.id, item]))
    const changed = items.filter((item) => JSON.stringify(item) !== JSON.stringify(before.get(item.id)))
    const removed = [...before.keys()].filter((id) => !after.has(id))
    if (changed.length + removed.length > 1) throw new Error('Se detectaron varios cambios. Recargá la lista y guardá un artículo por vez.')
    if (changed[0]) {
      const item = changed[0], catalog = await getCatalog(), unit = catalog.units.find((entry) => entry.abbreviation === item.unit)
      assertSession(session)
      const ingredient = item.ingredientId ? catalog.ingredients.find((entry) => entry.id === item.ingredientId) : undefined
      const meta = item
      const sourceLinks: Array<{ source: ShoppingSource; recipe_id?: string; plan_id?: string }> = meta.sourceLinks ?? item.sources.map((source) => ({ source }))
      if (sourceLinks.some((entry) => entry.source === 'recipe' && !entry.recipe_id)) throw new Error('No se puede guardar una sugerencia de receta sin su referencia relacional. Recargá y volvé a calcularla.')
      if (!unit || (item.ingredientId && !ingredient)) throw new Error('El artículo requiere una unidad o ingrediente activo del catálogo.')
      await mutate('put_my_shopping_item', { p_item: { id: item.id, ingredient_id: meta.ingredientRef ?? ingredient?.relationalId ?? null, name_snapshot: item.name, category_snapshot: item.category,
        quantity: item.quantity, unit_id: meta.unitRef ?? unit.id, note: item.note, checked: item.checked, source: item.sources[0] ?? 'manual', sources: sourceLinks } })
    } else if (removed[0]) await mutate('remove_my_shopping_item', { p_item_id: removed[0] })
    if (changed.length || removed.length) await read()
  }
  const repository: ShoppingRepository = {
    async list() { saveRequiresExplicitReload = false; return read() },
    save,
    async append(suggestions: ShoppingSuggestion[]) {
      const operationSession = captureSession()
      for (const suggestion of suggestions) {
        const base = await read(), catalog = await getCatalog(), merged = mergeShoppingSuggestions(base, [suggestion], catalog.units)
        assertSession(operationSession)
        const item = merged.find((entry) => shoppingKey(entry.name, entry.unit, catalog.units) === shoppingKey(suggestion.name, suggestion.unit, catalog.units))
        if (!item) continue
        if (suggestion.source === 'recipe' && !suggestion.sourceLinks?.some((entry) => entry.source === 'recipe' && entry.recipe_id)) throw new Error('No se puede guardar una sugerencia de receta sin su referencia relacional.')
        const previous = base.find((entry) => entry.id === item.id)
        const links = [...(previous?.sourceLinks ?? []), ...(suggestion.sourceLinks ?? [{ source: suggestion.source }])]
        const linkKey = (entry: { source: ShoppingSource; recipe_id?: string; plan_id?: string }) => `${entry.source}:${entry.recipe_id ?? ''}:${entry.plan_id ?? ''}`
        const sourceLinks = links.filter((entry, index) => links.findIndex((candidate) => linkKey(candidate) === linkKey(entry)) === index)
        const sig = JSON.stringify({ ...suggestion, sourceLinks })
        const key = sessionKey(captureSession())
        let stableId = pendingSuggestions.get(sig)
        if (!previous && (!stableId || stableId.sessionKey !== key)) { stableId = { id: crypto.randomUUID(), sessionKey: key }; pendingSuggestions.set(sig, stableId) }
        const withMetadata: ShoppingItem = { ...item, id: previous?.id ?? stableId?.id ?? item.id,
          ingredientId: suggestion.ingredientRef ? catalog.ingredients.find((entry) => entry.relationalId === suggestion.ingredientRef)?.id : item.ingredientId,
          ingredientRef: suggestion.ingredientRef ?? previous?.ingredientRef, unitRef: suggestion.unitRef ?? previous?.unitRef, sourceLinks }
        if (previous && JSON.stringify(previous) === JSON.stringify(withMetadata)) continue
        await save([...base.map((entry) => entry.id === item.id ? withMetadata : entry), ...(previous ? [] : [withMetadata])])
        pendingSuggestions.delete(sig)
      }
      return read()
    },
    async setPurchased(id: string, checked: boolean) { await read(); await mutate('set_my_shopping_checked', { p_item_ids: [id], p_checked: checked }); return read() },
    async markAllPurchased() { await read(); const ids = loadedItems.filter((item) => !item.checked).map((item) => item.id); if (ids.length) await mutate('set_my_shopping_checked', { p_item_ids: ids, p_checked: true }); return read() },
    async transferPurchased() {
      const operationSession = captureSession()
      await read(); assertSession(operationSession)
      const catalog = await getCatalog(); assertSession(operationSession)
      const eligible = loadedItems.filter((item) => isShoppingItemTransferable(item, catalog))
      if (!listId) return { items: loadedItems, transferredCount: 0, removedCount: 0 }
      const session = captureSession(), identity = sessionKey(session)
      const retrying = pendingTransfer?.sessionKey === identity && pendingTransfer.key.startsWith(`${listId}:`)
      if (!eligible.length && !retrying) return { items: loadedItems, transferredCount: 0, removedCount: 0 }
      const pending = pendingTransfer
      const ids = retrying && pending ? pending.ids : eligible.map((item) => item.id).sort(), key = `${listId}:${ids.join(',')}`
      if (!retrying) pendingTransfer = { key, ids, receipt: crypto.randomUUID(), version: listVersion, sessionKey: identity }
      const transferRequest = pendingTransfer
      if (!transferRequest) throw new Error('No se pudo preparar la transferencia.')
      const beforeCount = loadedItems.length
      const userId = await owner(session)
      const { data, error } = await getClient().rpc('transfer_my_shopping_to_pantry', { p_list_id: listId, p_item_ids: transferRequest.ids, p_idempotency_key: transferRequest.receipt, p_expected_version: transferRequest.version })
      if (error) { if ((error as { code?: string }).code === '40001') pendingTransfer = null; throw error } assertOwner(session, userId)
      if (!data || (data as { id?: string }).id == null) throw new Error('La transferencia no devolvió su comprobante.')
      pendingTransfer = null
      listVersion = Number((data as { resulting_list_version?: number }).resulting_list_version ?? listVersion + 1)
      const items = await read(); assertSession(operationSession); return { items, transferredCount: transferRequest.ids.length, removedCount: beforeCount - items.length }
    },
    async load() { saveRequiresExplicitReload = false; const session = captureSession(); const [items, catalog] = await Promise.all([read(), getCatalog()]); assertSession(session); return { items, catalog: catalog as AdminStorageData } },
    async suggestionsFromFavorites() { const session = captureSession(), rows = await suggestion('favorites', null); return mapSuggestions(rows, session) },
    async suggestionsFromWeek(dates: string[]) {
      if (!dates.length) return []
      const session = captureSession(), userId = await owner(session)
      const { data, error } = await getClient().rpc('suggest_my_shopping_for_dates', { p_dates: [...new Set(dates)], p_as_of: dateToday() })
      if (error) throw error; assertOwner(session, userId)
      if (!Array.isArray(data)) throw new Error('La respuesta de sugerencias no es válida.')
      return mapSuggestions(data as Array<Record<string, unknown>>, session)
    },
    async suggestionsForRestock() { const session = captureSession(), rows = await suggestion('pantry', null); return mapSuggestions(rows, session) },
  }
  return repository
  async function suggestion(source: string, planId: string | null) {
    const session = captureSession(), userId = await owner(session), { data, error } = await getClient().rpc('suggest_my_shopping', { p_source: source, p_plan_id: planId, p_as_of: dateToday() })
    if (error) throw error; assertOwner(session, userId); if (!Array.isArray(data)) throw new Error('La respuesta de sugerencias no es válida.'); return data as Array<Record<string, unknown>>
  }
  async function mapSuggestions(rows: Array<Record<string, unknown>>, session: ReturnType<typeof captureSession>): Promise<ShoppingSuggestion[]> {
    const catalogData = await getCatalog()
    const userId = await owner(session)
    assertOwner(session, userId)
    return rows.map((row) => {
    const suggestionRow = row as { name_snapshot?: string; category_snapshot?: string; quantity?: number; unit_id?: string; ingredient_id?: string | null; sources?: Array<{ source: ShoppingSource; recipe_id?: string; plan_id?: string }> }
    const unit = catalogData.units.find((entry) => entry.id === suggestionRow.unit_id)
    if (!unit || !Number.isFinite(Number(suggestionRow.quantity)) || typeof suggestionRow.name_snapshot !== 'string') throw new Error('La sugerencia tiene una unidad o cantidad no válida.')
    return { name: suggestionRow.name_snapshot, category: String(suggestionRow.category_snapshot ?? 'Otros'), quantity: Number(suggestionRow.quantity), unit: unit.abbreviation, source: (suggestionRow.sources?.[0]?.source ?? 'manual'), ingredientRef: suggestionRow.ingredient_id, unitRef: suggestionRow.unit_id, sourceLinks: suggestionRow.sources }
    })
  }
}

export const supabaseShoppingRepository = createSupabaseShoppingRepository({ getClient: client, captureSession: capturePersonalDataSession, assertOwner: assertPersonalDataOwner, assertSession: assertPersonalDataSessionCurrent, getCatalog: () => supabasePantryRepository.getCatalog() })
