import { demoAdminEmail, getAccounts, getSession, registerAccount, updateStoredAccount } from '../../auth/data/localAuthStore'
import { supabase } from '../../../shared/data/supabaseClient'

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

async function manageSupabaseUser(body: Record<string, unknown>): Promise<void> {
  if (!supabase) throw new Error('Supabase no está configurado.')
  const { data, error } = await supabase.functions.invoke('admin-users', { body })
  if (error) {
    let message = error.message
    if (error.context instanceof Response) {
      try {
        const result = await error.context.json() as { error?: unknown }
        if (typeof result.error === 'string') message = result.error
      } catch { /* Use the SDK message when the response has no JSON body. */ }
    }
    throw new Error(message)
  }
  if (!data || data.success !== true) throw new Error('Supabase no confirmó el cambio solicitado.')
}

export const adminUsersRepository = {
  async list(): Promise<ManagedUser[]> {
    if (supabase) {
      const { data, error } = await supabase.rpc('admin_list_users')
      if (error) throw new Error('No se pudo consultar la lista de usuarios. Verificá que esté aplicada la migración admin_user_directory.', { cause: error })
      if (!Array.isArray(data)) throw new Error('Supabase devolvió una lista de usuarios inválida.')
      return data.flatMap((row): ManagedUser[] => {
        if (!row || typeof row.email !== 'string' || typeof row.display_name !== 'string'
          || (row.role !== 'USER' && row.role !== 'ADMIN') || typeof row.active !== 'boolean') return []
        return [{ email: row.email, name: row.display_name, role: row.role, active: row.active, isDemoAdmin: false }]
      })
    }
    requireAdmin()
    return [
      { email: demoAdminEmail, name: 'Administrador de demostración', role: 'ADMIN', active: true, isDemoAdmin: true },
      ...getAccounts().map(({ email, name, active }) => ({ email, name, role: 'USER' as const, active: active !== false, isDemoAdmin: false })),
    ]
  },

  async create(name: string, email: string, password: string): Promise<void> {
    if (supabase) {
      const cleanName = validateName(name)
      const cleanEmail = email.trim().toLocaleLowerCase('es')
      if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(cleanEmail)) throw new Error('Ingresá un correo electrónico válido.')
      if (password.length < 8 || password.length > 72) throw new Error('La contraseña debe tener entre 8 y 72 caracteres.')
      await manageSupabaseUser({ action: 'create', name: cleanName, email: cleanEmail, password })
      return
    }
    requireAdmin()
    registerAccount(validateName(name), email, password)
  },

  async updateName(email: string, name: string): Promise<void> {
    if (supabase) {
      await manageSupabaseUser({ action: 'update_name', email: email.trim().toLocaleLowerCase('es'), name: validateName(name) })
      return
    }
    requireAdmin()
    const cleanEmail = email.trim().toLocaleLowerCase('es')
    if (cleanEmail === demoAdminEmail) throw new Error('El administrador de demostración no se puede modificar.')
    const cleanName = validateName(name)
    updateStoredAccount(cleanEmail, (account) => ({ ...account, name: cleanName }))
  },

  async setActive(email: string, active: boolean): Promise<void> {
    if (supabase) {
      if (typeof active !== 'boolean') throw new Error('El estado de la cuenta no es válido.')
      await manageSupabaseUser({ action: 'set_active', email: email.trim().toLocaleLowerCase('es'), active })
      return
    }
    requireAdmin()
    if (typeof active !== 'boolean') throw new Error('El estado de la cuenta no es válido.')
    const cleanEmail = email.trim().toLocaleLowerCase('es')
    if (cleanEmail === demoAdminEmail) throw new Error('El administrador de demostración no se puede modificar.')
    updateStoredAccount(cleanEmail, (account) => ({ ...account, active }))
  },

  async setRole(email: string, role: 'USER' | 'ADMIN'): Promise<void> {
    if (!supabase) throw new Error('El cambio de roles está disponible con cuentas Supabase.')
    if (role !== 'USER' && role !== 'ADMIN') throw new Error('El rol solicitado no es válido.')
    await manageSupabaseUser({ action: 'set_role', email: email.trim().toLocaleLowerCase('es'), role })
  },
}
