import { personalStorage } from '../../auth/data/personalStorage'
import { supabase } from '../../../shared/data/supabaseClient'
import type { PantryItem } from '../domain/pantry'
import { readPantryItems, writePantryItems } from './localPantryStore'
import { assertPersonalDataOwner, assertPersonalDataSessionCurrent, capturePersonalDataSession, type PersonalDataSession } from '../../../shared/data/personalDataSession'

interface PantryRow { id: string; ingredient_id: string | null; name: string; category: string; quantity: number; unit: string; minimum: number; expiry: string | null; source_shopping_ids: string[] }
function client() { if (!supabase) throw new Error('Falta configurar la conexión de Supabase.'); return supabase }
async function owner(session: PersonalDataSession) {
  assertPersonalDataSessionCurrent(session)
  const { data: { user }, error } = await client().auth.getUser()
  if (error) throw error
  if (!user) throw new Error('Iniciá sesión para acceder a tu despensa.')
  assertPersonalDataOwner(session, user.id)
  return user.id
}
function fromRow(row: PantryRow): PantryItem {
  return { id: row.id, ...(row.ingredient_id ? { ingredientId: row.ingredient_id } : {}), name: row.name, category: row.category, quantity: Number(row.quantity), unit: row.unit, minimum: Number(row.minimum), expiry: row.expiry, ...(row.source_shopping_ids?.length ? { sourceShoppingIds: row.source_shopping_ids } : {}) }
}
let activeUser: string | null = null
let pending: Promise<void> = Promise.resolve()
async function persist(userId: string, items: PantryItem[], session: PersonalDataSession) {
  assertPersonalDataOwner(session, userId)
  const db = client()
  const { data: current, error: readError } = await db.from('articulos_despensa').select('id').eq('user_id', userId)
  if (readError) throw readError
  assertPersonalDataOwner(session, userId)
  if (items.length) {
    const rows = items.map((item) => ({ id: item.id, user_id: userId, ingredient_id: item.ingredientId ?? null, name: item.name.trim(), category: item.category, quantity: item.quantity, unit: item.unit, minimum: item.minimum, expiry: item.expiry || null, source_shopping_ids: item.sourceShoppingIds ?? [], updated_at: new Date().toISOString() }))
    const { error } = await db.from('articulos_despensa').upsert(rows, { onConflict: 'id' })
    if (error) throw error
    assertPersonalDataOwner(session, userId)
  }
  const retained = new Set(items.map((item) => item.id))
  const removed = (current ?? []).map((row) => row.id).filter((id) => !retained.has(id))
  if (removed.length) {
    const { error } = await db.from('articulos_despensa').delete().in('id', removed).eq('user_id', userId)
    if (error) throw error
    assertPersonalDataOwner(session, userId)
  }
}
if (typeof window !== 'undefined') {
  window.addEventListener('auth-change', () => { activeUser = null })
  window.addEventListener('cocinapp:pantry-updated', () => {
    const session = capturePersonalDataSession(), userId = activeUser
    if (!userId) return
    try { assertPersonalDataOwner(session, userId) } catch { return }
    const items = readPantryItems()
    pending = pending.then(async () => { if (activeUser === userId && session.token === `supabase-user:${userId}`) await persist(userId, items, session) })
      .catch(() => { window.dispatchEvent(new Event('cocinapp:pantry-sync-error')) })
  })
}
export const legacySupabasePantryRepository = {
  async list(): Promise<PantryItem[]> {
    const session = capturePersonalDataSession(), userId = await owner(session)
    const { data, error } = await client().from('articulos_despensa').select('id, ingredient_id, name, category, quantity, unit, minimum, expiry, source_shopping_ids').eq('user_id', userId).order('name')
    if (error) throw error
    assertPersonalDataOwner(session, userId)
    const items = (data as PantryRow[]).map(fromRow)
    writePantryItems(items, personalStorage, false)
    assertPersonalDataOwner(session, userId)
    activeUser = userId
    return items
  },
  async save(items: PantryItem[]): Promise<void> {
    const session = capturePersonalDataSession(), userId = await owner(session)
    await persist(userId, items, session)
    assertPersonalDataOwner(session, userId)
    writePantryItems(items, personalStorage, false)
    activeUser = userId
  },
}
