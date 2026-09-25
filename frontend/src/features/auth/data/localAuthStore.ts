import { useEffect, useState } from 'react'
import { migrateLegacyPersonalData, personalStorage } from './personalStorage'

export type UserRole = 'USER' | 'ADMIN'

export interface SessionInfo {
  token: string
  role: UserRole
  email: string
  name: string
}

export interface LocalAccount {
  email: string
  name: string
  password: string
  role: 'USER'
}

const authKey = 'cocinapp.auth.v1'
const accountsKey = 'cocinapp.accounts.v1'
export const demoAdminEmail = 'admin@cocinapp.local'

function dispatchAuthChange() {
  window.dispatchEvent(new Event('auth-change'))
}

export function getAccounts(): LocalAccount[] {
  try {
    const value: unknown = JSON.parse(localStorage.getItem(accountsKey) ?? '[]')
    return Array.isArray(value) ? value.filter((entry): entry is LocalAccount => Boolean(entry && typeof entry === 'object' && typeof entry.email === 'string' && typeof entry.name === 'string' && typeof entry.password === 'string' && entry.role === 'USER')) : []
  } catch { return [] }
}

export function registerAccount(name: string, email: string, password: string): LocalAccount {
  const cleanName = name.trim()
  const cleanEmail = email.trim().toLocaleLowerCase('es')
  if (!cleanName) throw new Error('Ingresá tu nombre.')
  if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(cleanEmail)) throw new Error('Ingresá un correo electrónico válido.')
  if (password.length < 8) throw new Error('La contraseña debe tener al menos 8 caracteres.')
  const accounts = getAccounts()
  if (cleanEmail === demoAdminEmail || accounts.some((account) => account.email.toLocaleLowerCase('es') === cleanEmail)) throw new Error('Ya existe una cuenta con ese correo.')
  const account: LocalAccount = { name: cleanName, email: cleanEmail, password, role: 'USER' }
  localStorage.setItem(accountsKey, JSON.stringify([...accounts, account]))
  return account
}

export function authenticateUser(email: string, password: string): LocalAccount {
  const account = getAccounts().find((entry) => entry.email === email.trim().toLocaleLowerCase('es') && entry.password === password)
  if (!account) throw new Error('El correo o la contraseña no son correctos.')
  return account
}

function isSession(value: unknown): value is SessionInfo {
  if (!value || typeof value !== 'object') return false
  const session = value as Record<string, unknown>
  return typeof session.token === 'string' && session.token.length > 0
    && (session.role === 'USER' || session.role === 'ADMIN')
    && typeof session.email === 'string' && typeof session.name === 'string'
    && (session.role !== 'ADMIN' || session.email === demoAdminEmail)
}

export function getSession(): SessionInfo | null {
  try {
    const raw = localStorage.getItem(authKey)
    if (!raw) return null
    const value: unknown = JSON.parse(raw)
    if (!isSession(value)) {
      localStorage.removeItem(authKey)
      return null
    }
    if (value.role === 'USER' && !getAccounts().some((account) => account.email === value.email)) {
      localStorage.removeItem(authKey)
      return null
    }
    return value
  } catch {
    localStorage.removeItem(authKey)
    return null
  }
}

export function startSession(role: UserRole, email: string, name: string) {
  if (role === 'ADMIN' && email !== demoAdminEmail) throw new Error('Solo está disponible el administrador de demostración.')
  const session: SessionInfo = { token: 'local-demo-session', role, email: email.trim().toLocaleLowerCase('es'), name: name.trim() }
  localStorage.setItem(authKey, JSON.stringify(session))
  dispatchAuthChange()
}

export function startUserSession(account: LocalAccount) {
  migrateLegacyPersonalData(account.email)
  startSession('USER', account.email, account.name)
  if (personalStorage.getItem('cocinapp.profile.v1') === null) {
    personalStorage.setItem('cocinapp.profile.v1', JSON.stringify({ name: account.name, email: account.email }))
  }
}

export function startDemoAdminSession() {
  startSession('ADMIN', demoAdminEmail, 'Administrador de demostración')
}

export function endSession() {
  localStorage.removeItem(authKey)
  dispatchAuthChange()
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
