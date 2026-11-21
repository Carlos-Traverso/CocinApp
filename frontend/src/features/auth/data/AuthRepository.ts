import { useCallback, useEffect, useRef, useState } from 'react'
import type { Session } from '@supabase/supabase-js'
import { authenticateUser, changeLocalPassword, clearStoredUserSession, endSession, getSession, getSessionRevision, registerAccount, startDemoAdminSession, startSupabaseUserSession, startUserSession, type SessionInfo } from './localAuthStore'
import { createIsolatedAuthClient, isRelationalProfilesEnabled, supabase } from '../../../shared/data/supabaseClient'
import type { UserRole } from './localAuthStore'
import { adminRepository } from '../../admin/data/AdminRepository'
import { assertAuthenticationConfigured } from '../domain/security'
import { clearSessionPolicy, detectSessionDevice, hasSessionExpired, monitorSessionPolicy, startSessionPolicy } from './sessionTimeout'

function policyIdentity(session: Pick<SessionInfo, 'token' | 'email'>): string {
  return `${session.token}|${session.email.toLocaleLowerCase('es')}`
}

function beginSessionPolicy(session: SessionInfo): void {
  startSessionPolicy(policyIdentity(session))
}

async function expireCurrentSession(identity: string): Promise<void> {
  const current = getSession()
  if (!current || policyIdentity(current) !== identity) return
  try {
    await supabase?.auth.signOut({ scope: 'local' })
  } catch {
    // Always clear this browser's local session when its inactivity limit is reached.
  }
  if (getSession() && policyIdentity(getSession()!) === identity) endSession()
}

let sessionRevision = 0
let remoteUserId: string | null | undefined
if (supabase) {
  supabase.auth.onAuthStateChange((event, session) => {
    const userId = session?.user.id ?? null
    if (userId !== remoteUserId) {
      remoteUserId = userId
      sessionRevision += 1
      if (userId && getSession()?.token !== `supabase-user:${userId}`) clearStoredUserSession()
    }
    if (event === 'SIGNED_OUT') {
      const current = getSession()
      if (current) clearSessionPolicy(policyIdentity(current))
      endSession()
    }
  })
}

function isRemoteSessionCurrent(userId: string, revision: number): boolean {
  return revision === sessionRevision && (remoteUserId === undefined || remoteUserId === userId)
}

function assertRemoteSessionCurrent(userId: string, revision: number): void {
  if (!isRemoteSessionCurrent(userId, revision)) throw new Error('La sesión cambió. Volvé a intentarlo.')
}

function requireConfiguredAuthentication() {
  assertAuthenticationConfigured(import.meta.env?.PROD === true, Boolean(supabase))
}

// Catalog loading is useful during sign-in, but it is separate from verifying
// credentials and the account role. A catalog migration or network issue must
// not turn a valid authentication into a failed login.
async function preloadCatalog(): Promise<void> {
  try {
    await adminRepository.getCatalog()
  } catch {
    // Catalog screens report their own loading errors and can be retried there.
  }
}

async function getRemoteRole(session: Session, revision: number): Promise<UserRole> {
  if (!supabase) return 'USER'
  const authorization = `Bearer ${session.access_token}`
  const { data: active, error: activeError } = await supabase.rpc('current_account_is_active').setHeader('Authorization', authorization)
  assertRemoteSessionCurrent(session.user.id, revision)
  if (activeError) throw new Error('No se pudo verificar el estado de la cuenta.', { cause: activeError })
  if (active !== true) {
    await supabase.auth.signOut({ scope: 'local' })
    throw new Error('Tu cuenta está desactivada. Contactá con un administrador.')
  }
  const { data, error } = await supabase.rpc('current_app_role').setHeader('Authorization', authorization)
  assertRemoteSessionCurrent(session.user.id, revision)
  if (error) throw new Error('No se pudo consultar el rol. Verificá que esté aplicada la migración 202610160004_create_user_roles.sql.', { cause: error })
  if (data !== 'USER' && data !== 'ADMIN') throw new Error('Supabase devolvió un rol desconocido.')
  return data
}

async function getCanonicalProfileName(fallback: string, session: Session): Promise<string> {
  if (!supabase || !isRelationalProfilesEnabled) return fallback
  const { data, error } = await supabase.rpc('get_my_profile').setHeader('Authorization', `Bearer ${session.access_token}`)
  if (error) throw new Error('No se pudo consultar el nombre del perfil.', { cause: error })
  if (!data || typeof data !== 'object') return fallback
  const profile = (data as Record<string, unknown>).profile
  if (!profile || typeof profile !== 'object') return fallback
  const name = (profile as Record<string, unknown>).display_name
  return typeof name === 'string' && name.trim() ? name.trim() : fallback
}

export interface AuthRepository {
  session(): Promise<SessionInfo | null>
  login(email: string, password: string): Promise<void>
  register(name: string, email: string, password: string): Promise<void>
  verifyCurrentPassword(currentPassword: string): Promise<void>
  changePassword(currentPassword: string, newPassword: string): Promise<void>
  loginAsDemoAdmin(): Promise<void>
  logout(): Promise<void>
}

export const authRepository: AuthRepository = {
  async session() {
    requireConfiguredAuthentication()
    const localSession = getSession()
    if (!supabase) {
      await Promise.resolve()
      if (!localSession) return null
      const identity = policyIdentity(localSession)
      if (hasSessionExpired(identity, detectSessionDevice())) {
        clearSessionPolicy(identity)
        endSession()
        return null
      }
      return localSession
    }

    const { data: { session }, error: sessionError } = await supabase.auth.getSession()
    if (sessionError) throw sessionError
    if (!session) { clearStoredUserSession(); return null }
    const revision = sessionRevision
    if (!isRemoteSessionCurrent(session.user.id, revision)) return null
    const identity = `supabase-user:${session.user.id}|${session.user.email?.toLocaleLowerCase('es') ?? ''}`
    if (hasSessionExpired(identity, detectSessionDevice())) {
      try { await supabase.auth.signOut({ scope: 'local' }) } catch { /* The local deadline still applies while offline. */ }
      if (revision === sessionRevision) endSession()
      return null
    }
    const { data: { user }, error: userError } = await supabase.auth.getUser(session.access_token)
    if (userError) throw userError
    if (!user?.email || user.id !== session.user.id || !isRemoteSessionCurrent(user.id, revision)) return null
    const metadataName = user.user_metadata.name ?? user.user_metadata.full_name
    const name = typeof metadataName === 'string' && metadataName.trim() ? metadataName : user.email.split('@')[0]
    const remoteRole = await getRemoteRole(session, revision)
    const canonicalName = await getCanonicalProfileName(name, session)
    if (!isRemoteSessionCurrent(user.id, revision)) return null
    const verified = startSupabaseUserSession(user.id, user.email, canonicalName, remoteRole)
    await preloadCatalog()
    return isRemoteSessionCurrent(user.id, revision) ? verified : null
  },
  async login(email, password) {
    requireConfiguredAuthentication()
    if (!supabase) { await Promise.resolve(); startUserSession(authenticateUser(email, password)); beginSessionPolicy(getSession()!); return }
    const { data, error } = await supabase.auth.signInWithPassword({ email: email.trim(), password })
    if (error) throw mapAuthError(error.message)
    if (!data.user?.email || !data.session) throw new Error('Supabase no devolvió los datos de la cuenta.')
    const metadataName = data.user.user_metadata.name ?? data.user.user_metadata.full_name
    const name = typeof metadataName === 'string' && metadataName.trim() ? metadataName : data.user.email.split('@')[0]
    const revision = sessionRevision
    assertRemoteSessionCurrent(data.user.id, revision)
    const remoteRole = await getRemoteRole(data.session, revision)
    const canonicalName = await getCanonicalProfileName(name, data.session)
    assertRemoteSessionCurrent(data.user.id, revision)
    beginSessionPolicy(startSupabaseUserSession(data.user.id, data.user.email, canonicalName, remoteRole))
    await preloadCatalog()
  },
  async register(name, email, password) {
    requireConfiguredAuthentication()
    if (!supabase) { await Promise.resolve(); startUserSession(registerAccount(name, email, password)); beginSessionPolicy(getSession()!); return }
    const cleanName = name.trim()
    const cleanEmail = email.trim().toLocaleLowerCase('es')
    if (!cleanName) throw new Error('Ingresá tu nombre.')
    if (cleanName.length > 80) throw new Error('El nombre no puede superar los 80 caracteres.')
    if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(cleanEmail)) throw new Error('Ingresá un correo electrónico válido.')
    if (password.length < 8) throw new Error('La contraseña debe tener al menos 8 caracteres.')
    const { data, error } = await supabase.auth.signUp({
      email: cleanEmail,
      password,
      options: { data: { name: cleanName }, emailRedirectTo: window.location.origin },
    })
    if (error) throw mapAuthError(error.message)
    if (!data.session || !data.user?.email) {
      throw new Error('La cuenta se creó. Confirmá tu correo desde el mensaje de Supabase y después iniciá sesión.')
    }
    const revision = sessionRevision
    assertRemoteSessionCurrent(data.user.id, revision)
    const remoteRole = await getRemoteRole(data.session, revision)
    const canonicalName = await getCanonicalProfileName(cleanName, data.session)
    assertRemoteSessionCurrent(data.user.id, revision)
    beginSessionPolicy(startSupabaseUserSession(data.user.id, data.user.email, canonicalName, remoteRole))
    await preloadCatalog()
  },
  async loginAsDemoAdmin() {
    requireConfiguredAuthentication()
    if (supabase) throw new Error('Ingresá con una cuenta que tenga el rol de administrador en Supabase.')
    startDemoAdminSession()
    beginSessionPolicy(getSession()!)
  },
  async verifyCurrentPassword(currentPassword) {
    requireConfiguredAuthentication()
    if (!supabase) {
      const account = getSession()
      if (!account || account.role !== 'USER') throw new Error('Volvé a iniciar sesión para cambiar tu contraseña.')
      try { authenticateUser(account.email, currentPassword) }
      catch { throw new Error('La contraseña actual es incorrecta.') }
      return
    }
    const account = getSession()
    const revision = getSessionRevision()
    const sessionError = 'Volvé a iniciar sesión para cambiar tu contraseña.'
    if (!account || account.role !== 'USER' || !account.token.startsWith('supabase-user:')) throw new Error(sessionError)

    // Supabase projects can omit the server's current-password requirement.
    // Verify against Auth before updating, even on projects with that setting off.
    const verifier = createIsolatedAuthClient()
    const { data, error: verificationError } = await verifier.auth.signInWithPassword({ email: account.email, password: currentPassword })
    if (verificationError?.code === 'invalid_credentials') throw new Error('La contraseña actual es incorrecta.')
    if (!data.session) throw new Error('No se pudo verificar la contraseña actual. Intentá de nuevo.')

    // The verification session is temporary. Keep the original login active.
    await verifier.auth.signOut({ scope: 'local' }).catch(() => undefined)
    const { data: { session }, error: activeSessionError } = await supabase.auth.getSession()
    if (activeSessionError || !session || account.token !== `supabase-user:${session.user.id}`
      || data.session.user.id !== session.user.id || revision !== getSessionRevision()
      || getSession()?.token !== account.token) throw new Error(sessionError)

  },
  async changePassword(currentPassword, newPassword) {
    requireConfiguredAuthentication()
    if (!supabase) {
      changeLocalPassword(currentPassword, newPassword)
      return
    }
    if (!currentPassword) throw new Error('Ingresá tu contraseña actual.')
    if (newPassword.length < 8) throw new Error('La nueva contraseña debe tener al menos 8 caracteres.')
    if (currentPassword === newPassword) throw new Error('La nueva contraseña debe ser distinta de la actual.')

    const account = getSession()
    const revision = getSessionRevision()
    await authRepository.verifyCurrentPassword(currentPassword)

    const { data: { session }, error: sessionError } = await supabase.auth.getSession()
    const sessionChanged = () => revision !== getSessionRevision() || getSession()?.token !== account?.token
    if (sessionError || !session || account?.token !== `supabase-user:${session.user.id}` || sessionChanged()) {
      throw new Error('Volvé a iniciar sesión para cambiar tu contraseña.')
    }
    const passwordClient = createIsolatedAuthClient()
    const { error: restoreError } = await passwordClient.auth.setSession(session)
    if (restoreError || sessionChanged()) throw new Error('Volvé a iniciar sesión para cambiar tu contraseña.')

    const { error } = await passwordClient.auth.updateUser({ current_password: currentPassword, password: newPassword })
    if (!error) return
    if (error.code === 'current_password_mismatch') throw new Error('La contraseña actual es incorrecta.')
    if (error.code === 'same_password') throw new Error('La nueva contraseña debe ser distinta de la actual.')
    if (error.code === 'weak_password') throw new Error('La nueva contraseña no cumple los requisitos de seguridad.')
    if (error.code === 'reauthentication_needed' || error.code === 'session_not_found') throw new Error('Volvé a iniciar sesión para cambiar tu contraseña.')
    throw new Error('No se pudo cambiar la contraseña. Intentá de nuevo.')
  },
  async logout() {
    const current = getSession()
    if (supabase) {
      const { error } = await supabase.auth.signOut()
      if (error) throw error
    } else await Promise.resolve()
    if (current) clearSessionPolicy(policyIdentity(current))
    endSession()
  },
}

function mapAuthError(message: string): Error {
  const normalized = message.toLocaleLowerCase('en')
  if (normalized.includes('invalid login credentials')) return new Error('El correo o la contraseña no son correctos.')
  if (normalized.includes('user already registered')) return new Error('Ya existe una cuenta con ese correo.')
  if (normalized.includes('email not confirmed')) return new Error('Primero confirmá tu correo desde el mensaje que te envió Supabase.')
  if (normalized.includes('email rate limit exceeded') || normalized.includes('over_email_send_rate_limit')) {
    return new Error('Se alcanzó el límite de envío de correos. Esperá antes de intentarlo otra vez o revisá la configuración del proveedor de correo.')
  }
  return new Error(message)
}

export function useAuth() {
  const [state, setState] = useState<{ session: SessionInfo | null; loading: boolean; error: string }>({ session: null, loading: true, error: '' })
  const sessionPolicyIdentity = state.session ? policyIdentity(state.session) : null
  const refreshRef = useRef<() => void>(() => {})
  const retry = useCallback(() => {
    setState((current) => ({ ...current, loading: true }))
    refreshRef.current()
  }, [])
  useEffect(() => {
    let mounted = true
    let request = 0
    const refresh = () => {
      const current = ++request
      void authRepository.session().then((session) => { if (mounted && current === request) setState({ session, loading: false, error: '' }) }).catch(() => { if (mounted && current === request) setState({ session: null, loading: false, error: 'No se pudo cargar la sesión.' }) })
    }
    const hidePreviousSession = (token: string | null, email?: string) => {
      setState((current) => current.session && (current.session.token !== token || email !== undefined && current.session.email !== email)
        ? { session: null, loading: true, error: '' } : current)
    }
    const refreshStoredSession = () => {
      const stored = getSession()
      hidePreviousSession(stored?.token ?? null, stored?.email)
      refresh()
    }
    // Defer remote work until Supabase releases its auth callback lock.
    const subscription = supabase?.auth.onAuthStateChange((event, session) => {
      request += 1
      if (event === 'SIGNED_OUT') {
        if (mounted) setState({ session: null, loading: false, error: '' })
      } else {
        const token = session ? `supabase-user:${session.user.id}` : null
        if (mounted) hidePreviousSession(token)
        window.setTimeout(() => { if (mounted) refresh() }, 0)
      }
    }).data.subscription
    refreshRef.current = refresh
    refresh()
    window.addEventListener('auth-change', refreshStoredSession)
    window.addEventListener('storage', refreshStoredSession)
    return () => { mounted = false; refreshRef.current = () => {}; subscription?.unsubscribe(); window.removeEventListener('auth-change', refreshStoredSession); window.removeEventListener('storage', refreshStoredSession) }
  }, [])
  useEffect(() => {
    if (!sessionPolicyIdentity) return
    return monitorSessionPolicy(sessionPolicyIdentity, () => { void expireCurrentSession(sessionPolicyIdentity) })
  }, [sessionPolicyIdentity])
  return { ...state, retry }
}
