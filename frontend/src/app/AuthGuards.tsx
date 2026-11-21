import { LoadingScreen } from '../components/LoadingScreen'
import { Navigate, Outlet, useLocation, useOutletContext } from 'react-router-dom'
import { useAuth } from '../features/auth/data/AuthRepository'
import type { UserRole } from '../features/auth/data/localAuthStore'
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
    <Outlet context={session.role} />
  </NotificationProvider>
}

export function RequireRole({ role }: { role: UserRole }) {
  const sessionRole = useOutletContext<UserRole>()
  if (sessionRole !== role) return <RouteErrorPage role={sessionRole} status={403} />
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
