import { Navigate, Outlet } from 'react-router-dom'
import { useAuth } from '../features/auth/data/localAuthStore'

export function RequireAuth() {
  const session = useAuth()
  if (!session) {
    return <Navigate to="/" replace />
  }
  return <Outlet />
}

export function RequireAdmin() {
  const session = useAuth()
  if (!session) {
    return <Navigate to="/" replace />
  }
  if (session.role !== 'ADMIN') {
    return <Navigate to="/panel" replace />
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
