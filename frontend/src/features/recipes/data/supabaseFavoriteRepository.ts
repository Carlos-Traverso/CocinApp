import type { FavoriteRepository } from './FavoriteRepository'
import { supabaseRecipeRepository } from './SupabaseRecipeRepository'
import { assertPersonalDataOwner, assertPersonalDataSessionCurrent, capturePersonalDataSession, type PersonalDataSession } from '../../../shared/data/personalDataSession'
import { supabase } from '../../../shared/data/supabaseClient'

interface FavoriteDependencies {
  captureSession(): PersonalDataSession
  assertCurrent(session: PersonalDataSession): void
  assertOwner(session: PersonalDataSession, userId: string): void
  getUser(session: PersonalDataSession): Promise<string>
  rpc(name: string, args: Record<string, unknown>, session: PersonalDataSession): Promise<unknown>
  resolve(id: string): Promise<string | undefined>
}

export function createSupabaseFavoriteRepository(deps: FavoriteDependencies): FavoriteRepository {
  async function call(name: string, args: Record<string, unknown>, session: PersonalDataSession): Promise<unknown> {
    const owner = await deps.getUser(session)
    deps.assertCurrent(session)
    const result = await deps.rpc(name, args, session)
    deps.assertCurrent(session)
    const afterOwner = await deps.getUser(session)
    deps.assertCurrent(session)
    deps.assertOwner(session, afterOwner)
    if (owner !== afterOwner) throw new Error('La cuenta cambió mientras se procesaban tus favoritos.')
    return result
  }
  return {
    async listIds() {
      const session = deps.captureSession()
      const ids: string[] = []
      for (let offset = 0; offset <= 5000; offset += 100) {
        const result = await call('get_my_favorites', { p_limit: 100, p_offset: offset }, session)
        if (!result || typeof result !== 'object' || !Array.isArray((result as { items?: unknown }).items)) throw new Error('El servidor devolvió favoritos inválidos.')
        const items = (result as { items: unknown[] }).items
        ids.push(...items.flatMap((value) => {
          if (!value || typeof value !== 'object') return []
          const row = value as { recipe_id?: unknown; available?: unknown; recipe?: unknown }
          if (row.available !== true || typeof row.recipe_id !== 'string') return []
          if (row.recipe && typeof row.recipe === 'object' && typeof (row.recipe as { legacy_id?: unknown }).legacy_id === 'string') return [(row.recipe as { legacy_id: string }).legacy_id]
          return [row.recipe_id]
        }))
        const total = (result as { total?: unknown }).total
        if (items.length < 100 || typeof total === 'number' && offset + items.length >= total) return ids
      }
      throw new Error('La colección supera el límite de lectura permitido.')
    },
    async setFavorite(id, favorite) {
      const session = deps.captureSession()
      const recipeId = await deps.resolve(id)
      if (!recipeId) throw new Error('La receta ya no está disponible para favoritos.')
      await call('set_my_favorite', { p_recipe_id: recipeId, p_is_favorite: favorite }, session)
    },
    async saveIds() { throw new Error('Actualizá cada favorito de forma individual para conservar cambios hechos en otros dispositivos.') },
  }
}

export const supabaseFavoriteRepository = createSupabaseFavoriteRepository({
  captureSession: capturePersonalDataSession,
  assertCurrent: assertPersonalDataSessionCurrent,
  assertOwner: assertPersonalDataOwner,
  async getUser(session) {
    if (!supabase) throw new Error('No está disponible la conexión con favoritos.')
    assertPersonalDataSessionCurrent(session)
    const { data: { user }, error } = await supabase.auth.getUser()
    if (error) throw error
    if (!user) throw new Error('Iniciá sesión para consultar tus favoritos.')
    assertPersonalDataOwner(session, user.id)
    return user.id
  },
  async rpc(name, args, session) {
    if (!supabase) throw new Error('No está disponible la conexión con favoritos.')
    assertPersonalDataSessionCurrent(session)
    const { data, error } = await supabase.rpc(name, args)
    if (error) throw error
    return data
  },
  async resolve(id) { return (await supabaseRecipeRepository.getById(id, true))?.relationalId },
})
