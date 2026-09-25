import { useState, useEffect } from 'react'

export type UserRole = 'USER' | 'ADMIN'

export interface SessionInfo {
  token: string
  role: UserRole
  email: string
  name: string
}

const authKey = 'cocinapp.auth.v1'

export function getSession(): SessionInfo | null {
  const data = localStorage.getItem(authKey)
  if (!data) return null
  try {
    const session = JSON.parse(data)
    if (session && (session.role === 'USER' || session.role === 'ADMIN')) {
      return session as SessionInfo
    }
    return null
  } catch {
    return null
  }
}

export function startSession(role: UserRole, email: string, name: string) {
  localStorage.setItem(authKey, JSON.stringify({ token: 'mock-token', role, email, name }))
  window.dispatchEvent(new Event('auth-change'))
}

export function endSession() {
  localStorage.removeItem(authKey)
  window.dispatchEvent(new Event('auth-change'))
}

export function useAuth() {
  const [session, setSession] = useState<SessionInfo | null>(getSession())

  useEffect(() => {
    const handleAuthChange = () => setSession(getSession())
    window.addEventListener('auth-change', handleAuthChange)
    window.addEventListener('storage', handleAuthChange)
    return () => {
      window.removeEventListener('auth-change', handleAuthChange)
      window.removeEventListener('storage', handleAuthChange)
    }
  }, [])

  return session
}
