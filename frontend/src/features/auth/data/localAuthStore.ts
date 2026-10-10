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
  /** Older stored accounts omit this field and are treated as active. */
  active?: boolean
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
    return Array.isArray(value) ? value.filter((entry): entry is LocalAccount => Boolean(entry && typeof entry === 'object' && typeof entry.email === 'string' && typeof entry.name === 'string' && typeof entry.password === 'string' && entry.role === 'USER' && (entry.active === undefined || typeof entry.active === 'boolean'))).map((entry) => ({ ...entry, active: entry.active ?? true })) : []
  } catch { return [] }
}

export function registerAccount(name: string, email: string, password: string): LocalAccount {
  const cleanName = name.trim()
  const cleanEmail = email.trim().toLocaleLowerCase('es')
  if (!cleanName) throw new Error('Ingresá tu nombre.')
  if (cleanName.length > 80) throw new Error('El nombre no puede superar los 80 caracteres.')
  if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(cleanEmail)) throw new Error('Ingresá un correo electrónico válido.')
  if (password.length < 8) throw new Error('La contraseña debe tener al menos 8 caracteres.')
  const accounts = getAccounts()
  if (cleanEmail === demoAdminEmail || accounts.some((account) => account.email.toLocaleLowerCase('es') === cleanEmail)) throw new Error('Ya existe una cuenta con ese correo.')
  const account: LocalAccount = { name: cleanName, email: cleanEmail, password, role: 'USER', active: true }
  localStorage.setItem(accountsKey, JSON.stringify([...accounts, account]))
  return account
}

export function authenticateUser(email: string, password: string): LocalAccount {
  const account = getAccounts().find((entry) => entry.email === email.trim().toLocaleLowerCase('es') && entry.password === password)
  if (!account || account.active === false) throw new Error('El correo o la contraseña no son correctos.')
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
    if (value.role === 'USER' && !getAccounts().some((account) => account.email === value.email && account.active !== false)) {
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
  const cleanEmail = email.trim().toLocaleLowerCase('es')
  if (role === 'USER' && !getAccounts().some((account) => account.email === cleanEmail && account.active !== false)) throw new Error('La cuenta no está disponible.')
  const session: SessionInfo = { token: 'local-demo-session', role, email: cleanEmail, name: name.trim() }
  localStorage.setItem(authKey, JSON.stringify(session))
  dispatchAuthChange()
}

export function startUserSession(account: LocalAccount) {
  const storedAccount = getAccounts().find((entry) => entry.email === account.email && entry.active !== false)
  if (!storedAccount) throw new Error('La cuenta no está disponible.')
  account = storedAccount
  migrateLegacyPersonalData(account.email)
  startSession('USER', account.email, account.name)
  if (personalStorage.getItem('cocinapp.profile.v1') === null) {
    personalStorage.setItem('cocinapp.profile.v1', JSON.stringify({ name: account.name, email: account.email }))
  }
}

/** Update a stored account without changing its password or personal data. */
export function updateStoredAccount(email: string, update: (account: LocalAccount) => LocalAccount): LocalAccount {
  const accounts = getAccounts()
  const index = accounts.findIndex((account) => account.email === email)
  if (index < 0) throw new Error('No existe una cuenta con ese correo.')
  const updated = update(accounts[index])
  accounts[index] = updated
  localStorage.setItem(accountsKey, JSON.stringify(accounts))
  return updated
}

export function startDemoAdminSession() {
  startSession('ADMIN', demoAdminEmail, 'Administrador de demostración')
}

export function endSession() {
  localStorage.removeItem(authKey)
  dispatchAuthChange()
}
