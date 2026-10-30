import { LoadingScreen } from '../components/LoadingScreen'
import { Navigate, Outlet, useLocation } from 'react-router-dom'
import { useAuth } from '../features/auth/data/AuthRepository'
import { canAccessPath, roleHome } from '../features/auth/domain/routeAccess'
import { SessionError } from './SessionError'

export function RequireAuth() {
  const { session, loading, error, retry } = useAuth()
  if (error) return <SessionError message={error} retry={retry} retrying={loading} />
  if (loading) return <LoadingScreen message="Comprobando sesión…" variant="fullscreen" />
  if (!session) {
    return <Navigate to="/" replace />
  }
  return <Outlet />
}

export function RequireUser() {
  const auth = useAuth()
  const location = useLocation()
  if (auth.error) return <SessionError message={auth.error} retry={auth.retry} retrying={auth.loading} />
  if (auth.loading) return <LoadingScreen message="Comprobando sesión…" variant="fullscreen" />
  const { session } = auth
  if (!session) return <Navigate to="/" replace />
  if (!canAccessPath(session.role, location.pathname)) return <Navigate to={roleHome(session.role)} replace />
  return <Outlet />
}

export function RequireAdmin() {
  const { session, loading, error, retry } = useAuth()
  if (error) return <SessionError message={error} retry={retry} retrying={loading} />
  if (loading) return <LoadingScreen message="Comprobando sesión…" variant="fullscreen" />
  if (!session) {
    return <Navigate to="/" replace />
  }
  if (!canAccessPath(session.role, '/admin')) {
    return <Navigate to={roleHome(session.role)} replace />
  }
  return <Outlet />
}

export function RedirectIfAuthenticated() {
  const location = useLocation()
  // Let the user reach the public sign-in screen even when session checks fail.
  // Protected routes still run their normal authentication and role checks.
  if (location.state?.showSignIn === true) return <Outlet />
  return <SessionRedirect />
}

function SessionRedirect() {
  const { session, loading, error, retry } = useAuth()
  if (error) return <SessionError message={error} retry={retry} retrying={loading} />
  if (loading) return <LoadingScreen message="Comprobando sesión…" variant="fullscreen" />
  if (session) {
    return <Navigate to={roleHome(session.role)} replace />
  }
  return <Outlet />
}
