import type { UserRole } from '../data/localAuthStore'

export function roleHome(role: UserRole): '/admin' | '/panel' {
  return role === 'ADMIN' ? '/admin' : '/panel'
}
