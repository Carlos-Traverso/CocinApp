import { supabase } from '../../../shared/data/supabaseClient'

export interface AdminAuditEvent {
  id: string
  occurredAt: string
  actorName: string | null
  actorEmail: string | null
  action: string
  targetName: string | null
  targetEmail: string | null
  details: Record<string, unknown>
}

export const adminAuditRepository = {
  async list(query = ''): Promise<AdminAuditEvent[]> {
    if (!supabase) throw new Error('El historial administrativo requiere una conexión con Supabase.')
    const { data, error } = await supabase.rpc('admin_search_audit_events', { p_query: query.trim() || null, p_limit: 100 })
    if (error) throw new Error('No se pudo consultar el historial administrativo. Verificá que esté aplicada su migración.', { cause: error })
    if (!Array.isArray(data)) throw new Error('Supabase devolvió un historial inválido.')
    return data.flatMap((row): AdminAuditEvent[] => {
      if (!row || typeof row.id !== 'string' || typeof row.occurred_at !== 'string'
        || typeof row.action !== 'string'
        || (row.actor_name !== null && typeof row.actor_name !== 'string')
        || (row.actor_email !== null && typeof row.actor_email !== 'string')
        || (row.target_name !== null && typeof row.target_name !== 'string')
        || (row.target_email !== null && typeof row.target_email !== 'string')) return []
      const details = row.details && typeof row.details === 'object' && !Array.isArray(row.details)
        ? row.details as Record<string, unknown>
        : {}
      return [{ id: row.id, occurredAt: row.occurred_at, actorName: row.actor_name, actorEmail: row.actor_email, action: row.action, targetName: row.target_name, targetEmail: row.target_email, details }]
    })
  },
}
