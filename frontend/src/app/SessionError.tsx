import { ArrowLeft, RefreshCw } from 'lucide-react'
import { Link } from 'react-router-dom'
import { ErrorScreen } from './ErrorScreen'

interface SessionErrorProps {
  message: string
  retry: () => void
  retrying?: boolean
}

export function SessionError({ message, retry, retrying = false }: SessionErrorProps) {
  return <ErrorScreen
    busy={retrying}
    description="Podés volver a intentarlo o regresar al inicio para ingresar nuevamente."
    notice={message}
    title="No pudimos comprobar tu sesión"
  >
    <button className="button button-primary" disabled={retrying} onClick={retry} type="button">
      <RefreshCw size={17} aria-hidden="true" className={retrying ? 'spin' : undefined} />
      {retrying ? 'Reintentando…' : 'Reintentar'}
    </button>
    <Link className="button button-quiet" replace state={{ showSignIn: true }} to="/">
      <ArrowLeft size={17} aria-hidden="true" />Volver al inicio
    </Link>
  </ErrorScreen>
}
