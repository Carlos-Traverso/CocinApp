import type { UserRole } from '../data/localAuthStore'

export function roleHome(role: UserRole): '/admin' | '/panel' {
  return role === 'ADMIN' ? '/admin' : '/panel'
}

export function canAccessPath(role: UserRole, pathname: string): boolean {
  const isAdminPath = pathname === '/admin' || pathname.startsWith('/admin/')
  return role === 'ADMIN' ? isAdminPath : !isAdminPath
}

export function unknownPathDestination(role: UserRole): '/admin' | '/panel' {
  return roleHome(role)
}
