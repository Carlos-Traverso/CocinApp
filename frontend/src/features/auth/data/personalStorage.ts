import { getSession } from './localAuthStore'

const ownerKey = 'cocinapp.personal-data-owner.v1'
const legacyKeys = [
  'cocinapp.pantry.v1', 'cocinapp.pantry', 'cocinapp-demo-pantry-v1', 'cocinapp.profile.v1',
  'cocinapp.favorites.v1', 'cocinapp.planner.v1', 'cocinapp.shopping.v1',
  'cocinapp.cooking-progress.v1', 'cocinapp.cooking-history.v1', 'cocinapp.history.v1',
]

export function migrateLegacyPersonalData(email: string) {
  if (localStorage.getItem(ownerKey)) return
  let legacyEmail: string | undefined
  try {
    const profile: unknown = JSON.parse(localStorage.getItem('cocinapp.profile.v1') ?? 'null')
    if (profile && typeof profile === 'object' && typeof (profile as Record<string, unknown>).email === 'string') {
      legacyEmail = ((profile as Record<string, unknown>).email as string).trim().toLocaleLowerCase('es')
    }
  } catch { /* Keep unowned legacy data in place when it cannot be identified safely. */ }
  if (!legacyEmail || legacyEmail !== email.trim().toLocaleLowerCase('es')) return
  const prefix = `cocinapp.user.${encodeURIComponent(email.toLocaleLowerCase('es'))}.`
  for (const key of legacyKeys) {
    const value = localStorage.getItem(key)
    if (value !== null && localStorage.getItem(`${prefix}${key}`) === null) localStorage.setItem(`${prefix}${key}`, value)
  }
  localStorage.setItem(ownerKey, email.toLocaleLowerCase('es'))
}

function scopedKey(key: string): string {
  const session = getSession()
  if (!session || session.role !== 'USER') return key
  return `cocinapp.user.${encodeURIComponent(session.email.toLocaleLowerCase('es'))}.${key}`
}

export const personalStorage: Storage = {
  get length() { return localStorage.length },
  clear() {
    const session = getSession()
    const prefix = session?.role === 'USER' ? `cocinapp.user.${encodeURIComponent(session.email.toLocaleLowerCase('es'))}.` : ''
    for (let index = localStorage.length - 1; index >= 0; index -= 1) {
      const key = localStorage.key(index)
      if (key && (!prefix || key.startsWith(prefix))) localStorage.removeItem(key)
    }
  },
  key(index) { return localStorage.key(index) },
  getItem(key) { return localStorage.getItem(scopedKey(key)) },
  removeItem(key) { localStorage.removeItem(scopedKey(key)) },
  setItem(key, value) { localStorage.setItem(scopedKey(key), value) },
}
