import { supabase } from '../../../shared/data/supabaseClient'
import { capturePersonalDataSession, assertPersonalDataSessionCurrent } from '../../../shared/data/personalDataSession'

export type RelationalDietaryTag = { tagKey: string; label: string; active: boolean }

export async function listRelationalDietaryTags(): Promise<RelationalDietaryTag[]> {
  if (!supabase) throw new Error('Supabase no está configurado.')
  const session = capturePersonalDataSession()
  const rows: RelationalDietaryTag[] = []
  for (let offset = 0; ; offset += 500) {
    const { data, error } = await supabase.from('etiquetas_dieteticas').select('tag_key,label,active').order('tag_key').range(offset, offset + 499)
    assertPersonalDataSessionCurrent(session)
    if (error) throw error
    if (!Array.isArray(data)) throw new Error('No se pudieron leer las etiquetas dietéticas.')
    rows.push(...data.map((row) => {
    if (typeof row.tag_key !== 'string' || typeof row.label !== 'string' || typeof row.active !== 'boolean') throw new Error('Supabase devolvió una etiqueta dietética inválida.')
    return { tagKey: row.tag_key, label: row.label, active: row.active }
    }))
    if (data.length < 500) return rows
  }
}
