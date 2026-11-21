import { ArrowLeft, RefreshCw } from 'lucide-react'
import { isRouteErrorResponse, Link, useRouteError } from 'react-router-dom'
import type { UserRole } from '../features/auth/data/localAuthStore'
import { roleHome } from '../features/auth/domain/routeAccess'
import { ErrorScreen } from './ErrorScreen'

const errorCopy = {
  403: {
    title: 'No tenés acceso a esta página',
    description: 'Tu cuenta no tiene permiso para entrar a esta sección.',
  },
  404: {
    title: 'Esta página no está en el menú',
    description: 'Puede que la dirección haya cambiado o que el enlace ya no esté disponible.',
  },
}

export function RouteErrorPage({ status, role }: { status: 403 | 404; role?: UserRole }) {
  return <ErrorScreen status={status} {...errorCopy[status]}>
    <Link className="button button-primary" replace to={role ? roleHome(role) : '/'}>
      <ArrowLeft aria-hidden="true" size={17} />
      {role === 'ADMIN' ? 'Volver a Administración' : role === 'USER' ? 'Volver al panel' : 'Volver al inicio'}
    </Link>
  </ErrorScreen>
}

export function UnexpectedErrorPage() {
  const error = useRouteError()
  if (isRouteErrorResponse(error) && (error.status === 403 || error.status === 404)) {
    return <RouteErrorPage status={error.status} />
  }

  return <ErrorScreen
    description="Tuvimos un problema al abrir esta página. Probá recargarla o volvé al inicio."
    status={500}
    title="Algo salió mal en la cocina"
  >
    <button className="button button-primary" onClick={() => window.location.reload()} type="button">
      <RefreshCw aria-hidden="true" size={17} />Recargar página
    </button>
    <Link className="button button-quiet" reloadDocument to="/">
      <ArrowLeft aria-hidden="true" size={17} />Volver al inicio
    </Link>
  </ErrorScreen>
}
