import { ArrowLeft, RefreshCw } from 'lucide-react'
import { Link, useOutletContext } from 'react-router-dom'
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

export function RouteErrorPage({ status }: { status: 403 | 404 }) {
  const role = useOutletContext<UserRole>()
  return <ErrorScreen status={status} {...errorCopy[status]}>
    <Link className="button button-primary" replace to={roleHome(role)}>
      <ArrowLeft aria-hidden="true" size={17} />
      {role === 'ADMIN' ? 'Volver a Administración' : 'Volver al panel'}
    </Link>
  </ErrorScreen>
}

export function UnexpectedErrorPage() {
  return <ErrorScreen
    description="Podés recargar la página para intentarlo de nuevo o regresar al inicio."
    title="Algo salió mal en CocinAPP"
  >
    <button className="button button-primary" onClick={() => window.location.reload()} type="button">
      <RefreshCw aria-hidden="true" size={17} />Recargar página
    </button>
    <Link className="button button-quiet" reloadDocument to="/">
      <ArrowLeft aria-hidden="true" size={17} />Volver al inicio
    </Link>
  </ErrorScreen>
}
