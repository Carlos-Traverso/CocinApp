import { useCallback, useEffect, useState } from 'react'
import { authenticateUser, clearStoredUserSession, endSession, getSession, registerAccount, startDemoAdminSession, startSupabaseUserSession, startUserSession, type SessionInfo } from './localAuthStore'
import { supabase } from '../../../shared/data/supabaseClient'
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
if (supabase) {
  supabase.auth.onAuthStateChange((event) => {
    if (event === 'SIGNED_OUT') {
      sessionRevision += 1
      const current = getSession()
      if (current) clearSessionPolicy(policyIdentity(current))
      endSession()
    }
  })
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

async function getRemoteRole(): Promise<UserRole> {
  if (!supabase) return 'USER'
  const { data: active, error: activeError } = await supabase.rpc('current_account_is_active')
  if (activeError) throw new Error('No se pudo verificar el estado de la cuenta.', { cause: activeError })
  if (active !== true) {
    await supabase.auth.signOut({ scope: 'local' })
    throw new Error('Tu cuenta está desactivada. Contactá con un administrador.')
  }
  const { data, error } = await supabase.rpc('current_app_role')
  if (error) throw new Error('No se pudo consultar el rol. Verificá que esté aplicada la migración 202610160004_create_user_roles.sql.', { cause: error })
  if (data !== 'USER' && data !== 'ADMIN') throw new Error('Supabase devolvió un rol desconocido.')
  return data
}

export interface AuthRepository {
  session(): Promise<SessionInfo | null>
  login(email: string, password: string): Promise<void>
  register(name: string, email: string, password: string): Promise<void>
  loginAsDemoAdmin(): Promise<void>
  logout(): Promise<void>
}

export const authRepository: AuthRepository = {
  async session() {
    requireConfiguredAuthentication()
    const revision = sessionRevision
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
    const identity = `supabase-user:${session.user.id}|${session.user.email?.toLocaleLowerCase('es') ?? ''}`
    if (hasSessionExpired(identity, detectSessionDevice())) {
      try { await supabase.auth.signOut({ scope: 'local' }) } catch { /* The local deadline still applies while offline. */ }
      if (revision === sessionRevision) endSession()
      return null
    }
    const { data: { user }, error: userError } = await supabase.auth.getUser()
    if (userError) throw userError
    if (!user?.email) { clearStoredUserSession(); return null }
    const metadataName = user.user_metadata.name ?? user.user_metadata.full_name
    const name = typeof metadataName === 'string' && metadataName.trim() ? metadataName : user.email.split('@')[0]
    const remoteRole = await getRemoteRole()
    if (revision !== sessionRevision) return null
    startSupabaseUserSession(user.id, user.email, name, remoteRole)
    await preloadCatalog()
    if (revision !== sessionRevision) return null
    return getSession()
  },
  async login(email, password) {
    requireConfiguredAuthentication()
    if (!supabase) { await Promise.resolve(); startUserSession(authenticateUser(email, password)); beginSessionPolicy(getSession()!); return }
    const { data, error } = await supabase.auth.signInWithPassword({ email: email.trim(), password })
    if (error) throw mapAuthError(error.message)
    if (!data.user?.email) throw new Error('Supabase no devolvió los datos de la cuenta.')
    const metadataName = data.user.user_metadata.name ?? data.user.user_metadata.full_name
    const name = typeof metadataName === 'string' && metadataName.trim() ? metadataName : data.user.email.split('@')[0]
    beginSessionPolicy(startSupabaseUserSession(data.user.id, data.user.email, name, await getRemoteRole()))
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
    beginSessionPolicy(startSupabaseUserSession(data.user.id, data.user.email, cleanName, await getRemoteRole()))
    await preloadCatalog()
  },
  async loginAsDemoAdmin() {
    requireConfiguredAuthentication()
    if (supabase) throw new Error('Ingresá con una cuenta que tenga el rol de administrador en Supabase.')
    startDemoAdminSession()
    beginSessionPolicy(getSession()!)
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
  const retry = useCallback(() => {
    setState((current) => ({ ...current, loading: true }))
    void authRepository.session().then((session) => setState({ session, loading: false, error: '' })).catch(() => setState({ session: null, loading: false, error: 'No se pudo cargar la sesión.' }))
  }, [])
  useEffect(() => {
    let mounted = true
    let request = 0
    const refresh = () => {
      const current = ++request
      void authRepository.session().then((session) => { if (mounted && current === request) setState({ session, loading: false, error: '' }) }).catch(() => { if (mounted && current === request) setState({ session: null, loading: false, error: 'No se pudo cargar la sesión.' }) })
    }
    // Defer remote work until Supabase releases its auth callback lock.
    const subscription = supabase?.auth.onAuthStateChange((event) => {
      if (event === 'SIGNED_OUT') {
        request += 1
        if (mounted) setState({ session: null, loading: false, error: '' })
      } else {
        window.setTimeout(() => { if (mounted) refresh() }, 0)
      }
    }).data.subscription
    refresh()
    window.addEventListener('auth-change', refresh)
    window.addEventListener('storage', refresh)
    return () => { mounted = false; subscription?.unsubscribe(); window.removeEventListener('auth-change', refresh); window.removeEventListener('storage', refresh) }
  }, [])
  useEffect(() => {
    if (!sessionPolicyIdentity) return
    return monitorSessionPolicy(sessionPolicyIdentity, () => { void expireCurrentSession(sessionPolicyIdentity) })
  }, [sessionPolicyIdentity])
  return { ...state, retry }
}
