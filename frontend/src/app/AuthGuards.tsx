import { useEffect } from 'react'
import { Navigate, Outlet } from 'react-router-dom'
import { useAuth } from '../features/auth/data/AuthRepository'
import { canAccessPath, roleHome } from '../features/auth/domain/routeAccess'
import { useLocation } from 'react-router-dom'
import { useNotifications } from '../shared/notifications/NotificationProvider'

function SessionError({ message, retry }: { message: string; retry: () => void }) {
  const { notify } = useNotifications()
  useEffect(() => { void notify({ type: 'error', title: 'No se pudo comprobar la sesión', message }) }, [message, notify])
  return <main className="page"><button className="button button-primary" onClick={retry} type="button">Reintentar</button></main>
}

export function RequireAuth() {
  const { session, loading, error, retry } = useAuth()
  if (error) return <SessionError message={error} retry={retry} />
  if (loading) return <p className="route-loading" role="status">Comprobando sesión…</p>
  if (!session) {
    return <Navigate to="/" replace />
  }
  return <Outlet />
}

export function RequireUser() {
  const auth = useAuth()
  const location = useLocation()
  if (auth.error) return <SessionError message={auth.error} retry={auth.retry} />
  if (auth.loading) return <p className="route-loading" role="status">Comprobando sesión…</p>
  const { session } = auth
  if (!session) return <Navigate to="/" replace />
  if (!canAccessPath(session.role, location.pathname)) return <Navigate to={roleHome(session.role)} replace />
  return <Outlet />
}

export function RequireAdmin() {
  const { session, loading, error, retry } = useAuth()
  if (error) return <SessionError message={error} retry={retry} />
  if (loading) return <p className="route-loading" role="status">Comprobando sesión…</p>
  if (!session) {
    return <Navigate to="/" replace />
  }
  if (!canAccessPath(session.role, '/admin')) {
    return <Navigate to={roleHome(session.role)} replace />
  }
  return <Outlet />
}

export function RedirectIfAuthenticated() {
  const { session, loading, error, retry } = useAuth()
  if (error) return <SessionError message={error} retry={retry} />
  if (loading) return <p className="route-loading" role="status">Comprobando sesión…</p>
  if (session) {
    return <Navigate to={roleHome(session.role)} replace />
  }
  return <Outlet />
}
