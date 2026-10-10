import { demoAdminEmail, getAccounts, getSession, registerAccount, updateStoredAccount } from '../../auth/data/localAuthStore'

export interface ManagedUser {
  email: string
  name: string
  role: 'USER' | 'ADMIN'
  active: boolean
  isDemoAdmin: boolean
}

function requireAdmin() {
  const session = getSession()
  if (session?.role !== 'ADMIN' || session.email !== demoAdminEmail) throw new Error('Se requiere una sesión de administrador.')
}

function validateName(name: string) {
  const clean = name.trim()
  if (!clean) throw new Error('Ingresá un nombre.')
  if (clean.length > 80) throw new Error('El nombre no puede superar los 80 caracteres.')
  return clean
}

export const adminUsersRepository = {
  async list(): Promise<ManagedUser[]> {
    requireAdmin()
    return [
      { email: demoAdminEmail, name: 'Administrador de demostración', role: 'ADMIN', active: true, isDemoAdmin: true },
      ...getAccounts().map(({ email, name, active }) => ({ email, name, role: 'USER' as const, active: active !== false, isDemoAdmin: false })),
    ]
  },

  async create(name: string, email: string, password: string): Promise<void> {
    requireAdmin()
    registerAccount(validateName(name), email, password)
  },

  async updateName(email: string, name: string): Promise<void> {
    requireAdmin()
    const cleanEmail = email.trim().toLocaleLowerCase('es')
    if (cleanEmail === demoAdminEmail) throw new Error('El administrador de demostración no se puede modificar.')
    const cleanName = validateName(name)
    updateStoredAccount(cleanEmail, (account) => ({ ...account, name: cleanName }))
  },

  async setActive(email: string, active: boolean): Promise<void> {
    requireAdmin()
    if (typeof active !== 'boolean') throw new Error('El estado de la cuenta no es válido.')
    const cleanEmail = email.trim().toLocaleLowerCase('es')
    if (cleanEmail === demoAdminEmail) throw new Error('El administrador de demostración no se puede modificar.')
    updateStoredAccount(cleanEmail, (account) => ({ ...account, active }))
  },
}
