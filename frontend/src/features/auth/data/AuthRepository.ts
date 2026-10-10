import { useCallback, useEffect, useState } from 'react'
import { authenticateUser, endSession, getSession, registerAccount, startDemoAdminSession, startUserSession, type SessionInfo } from './localAuthStore'

export interface AuthRepository {
  session(): Promise<SessionInfo | null>
  login(email: string, password: string): Promise<void>
  register(name: string, email: string, password: string): Promise<void>
  loginAsDemoAdmin(): Promise<void>
  logout(): Promise<void>
}

export const authRepository: AuthRepository = {
  async session() { await Promise.resolve(); return getSession() },
  async login(email, password) { await Promise.resolve(); startUserSession(authenticateUser(email, password)) },
  async register(name, email, password) { await Promise.resolve(); startUserSession(registerAccount(name, email, password)) },
  async loginAsDemoAdmin() { await Promise.resolve(); startDemoAdminSession() },
  async logout() { await Promise.resolve(); endSession() },
}

export function useAuth() {
  const [state, setState] = useState<{ session: SessionInfo | null; loading: boolean; error: string }>({ session: null, loading: true, error: '' })
  const retry = useCallback(() => {
    setState((current) => ({ ...current, loading: true, error: '' }))
    void authRepository.session().then((session) => setState({ session, loading: false, error: '' })).catch(() => setState({ session: null, loading: false, error: 'No se pudo cargar la sesión.' }))
  }, [])
  useEffect(() => {
    let mounted = true
    const refresh = () => { void authRepository.session().then((session) => { if (mounted) setState({ session, loading: false, error: '' }) }).catch(() => { if (mounted) setState({ session: null, loading: false, error: 'No se pudo cargar la sesión.' }) }) }
    refresh()
    window.addEventListener('auth-change', refresh)
    window.addEventListener('storage', refresh)
    return () => { mounted = false; window.removeEventListener('auth-change', refresh); window.removeEventListener('storage', refresh) }
  }, [])
  return { ...state, retry }
}
