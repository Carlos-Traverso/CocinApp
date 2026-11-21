import type { Session } from '@supabase/supabase-js'

/** A production deployment must never fall back to browser-only demo accounts. */
export function assertAuthenticationConfigured(production: boolean, configured: boolean): void {
  if (production && !configured) {
    throw new Error('El acceso no está disponible: falta configurar la conexión segura con Supabase.')
  }
}

/** Identify the recovery session across token refreshes. Supabase validates the token. */
export function authSessionIdentity(session: Pick<Session, 'access_token'> & { user: Pick<Session['user'], 'id'> } | null): string | null {
  if (!session) return null
  try {
    const payload = session.access_token.split('.')[1].replace(/-/g, '+').replace(/_/g, '/')
    const claims = JSON.parse(atob(payload)) as { sub?: string; session_id?: string }
    if (claims.sub === session.user.id && typeof claims.session_id === 'string' && claims.session_id) {
      return `${session.user.id}:${claims.session_id}`
    }
  } catch { /* An unreadable token cannot be bound to the recovery form. */ }
  return null
}
