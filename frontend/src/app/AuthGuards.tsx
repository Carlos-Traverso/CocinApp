import { Navigate, Outlet } from 'react-router-dom'
import { useAuth } from '../features/auth/data/localAuthStore'
import { canAccessPath, roleHome } from '../features/auth/domain/routeAccess'
import { useLocation } from 'react-router-dom'

export function RequireAuth() {
  const session = useAuth()
  if (!session) {
    return <Navigate to="/" replace />
  }
  return <Outlet />
}

export function RequireUser() {
  const session = useAuth()
  const location = useLocation()
  if (!session) return <Navigate to="/" replace />
  if (!canAccessPath(session.role, location.pathname)) return <Navigate to={roleHome(session.role)} replace />
  return <Outlet />
}

export function RequireAdmin() {
  const session = useAuth()
  if (!session) {
    return <Navigate to="/" replace />
  }
  if (!canAccessPath(session.role, '/admin')) {
    return <Navigate to={roleHome(session.role)} replace />
  }
  return <Outlet />
}

export function RedirectIfAuthenticated() {
  const session = useAuth()
  if (session) {
    return <Navigate to={session.role === 'ADMIN' ? '/admin' : '/panel'} replace />
  }
  return <Outlet />
}
