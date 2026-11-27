import { LoadingScreen } from '../components/LoadingScreen'
import { Navigate, Outlet, useLocation, useOutletContext } from 'react-router-dom'
import { useAuth } from '../features/auth/data/AuthRepository'
import type { SessionInfo, UserRole } from '../features/auth/data/localAuthStore'
import { roleHome } from '../features/auth/domain/routeAccess'
import { RouteErrorPage } from './RouteErrorPage'
import { SessionError } from './SessionError'
import { NotificationProvider } from '../shared/notifications/NotificationProvider'

export function RequireSession() {
  const { session, loading, error, retry } = useAuth()
  if (error) return <SessionError message={error} retry={retry} retrying={loading} />
  if (loading) return <LoadingScreen message="Comprobando sesión…" variant="fullscreen" />
  if (!session) return <Navigate to="/" replace />
  return <NotificationProvider key={JSON.stringify([session.token, session.email, session.role])} privateScope>
    <Outlet context={session} />
  </NotificationProvider>
}

export function RequireRole({ role }: { role: UserRole }) {
  const session = useOutletContext<SessionInfo>()
  if (session.role !== role) return <RouteErrorPage role={session.role} status={403} />
  return <Outlet context={session} />
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
