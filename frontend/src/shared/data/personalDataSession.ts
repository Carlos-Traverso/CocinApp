import { getSession, getSessionRevision } from '../../features/auth/data/localAuthStore'
import { supabase } from './supabaseClient'

let supabaseRevision = 0

supabase?.auth.onAuthStateChange((event) => {
  if (event === 'SIGNED_IN' || event === 'SIGNED_OUT' || event === 'USER_UPDATED' || event === 'PASSWORD_RECOVERY') {
    supabaseRevision += 1
  }
})

export interface PersonalDataSession {
  supabaseRevision: number
  localRevision: number
  token: string | null
}

export function capturePersonalDataSession(): PersonalDataSession {
  return { supabaseRevision, localRevision: getSessionRevision(), token: getSession()?.token ?? null }
}

export function isPersonalDataSessionCurrent(session: PersonalDataSession): boolean {
  return session.supabaseRevision === supabaseRevision
    && session.localRevision === getSessionRevision()
    && session.token === (getSession()?.token ?? null)
}

export function assertPersonalDataSessionCurrent(session: PersonalDataSession): void {
  if (!isPersonalDataSessionCurrent(session)) {
    throw new Error('La sesión cambió mientras se procesaban tus datos. Volvé a intentarlo.')
  }
}

export function assertPersonalDataOwner(session: PersonalDataSession, userId: string): void {
  assertPersonalDataSessionCurrent(session)
  if (!session.token?.startsWith('supabase-user:') || session.token.slice('supabase-user:'.length) !== userId) {
    throw new Error('La cuenta cambió mientras se procesaban tus datos. Volvé a intentarlo.')
  }
}

/** Pin requests to the account that supplied the data, including during SDK token lookup. */
export async function getPersonalDataAuthorization(expected: PersonalDataSession): Promise<string> {
  assertPersonalDataSessionCurrent(expected)
  if (!supabase) throw new Error('Falta configurar la conexión de Supabase.')
  const { data: { session }, error } = await supabase.auth.getSession()
  if (error) throw error
  if (!session) throw new Error('Iniciá sesión para acceder a tus datos.')
  assertPersonalDataOwner(expected, session.user.id)
  return `Bearer ${session.access_token}`
}
