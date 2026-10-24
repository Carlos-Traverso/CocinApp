import { AlertTriangle, ArrowLeft, RefreshCw } from 'lucide-react'
import { Link } from 'react-router-dom'
import { BrandLogo } from '../components/BrandLogo'
import './SessionError.css'

interface SessionErrorProps {
  message: string
  retry: () => void
  retrying?: boolean
}

export function SessionError({ message, retry, retrying = false }: SessionErrorProps) {
  return <main className="session-error-page">
    <section className="session-error-card" aria-labelledby="session-error-title" aria-busy={retrying}>
      <BrandLogo className="session-error-logo" />
      <div className="session-error-symbol" aria-hidden="true"><AlertTriangle size={32} strokeWidth={1.7} /></div>
      <p className="eyebrow">UN MOMENTO EN TU COCINA</p>
      <h1 id="session-error-title">No pudimos iniciar tu sesión</h1>
      <p className="session-error-description">Podés volver a intentarlo o regresar al inicio para ingresar nuevamente.</p>
      <div className="session-error-notice" role="alert">
        <span className="session-error-notice-dot" aria-hidden="true" />
        <p>{message}</p>
      </div>
      <div className="session-error-actions">
        <button className="button button-primary" disabled={retrying} onClick={retry} type="button">
          <RefreshCw size={17} aria-hidden="true" className={retrying ? 'spin' : undefined} />
          {retrying ? 'Reintentando…' : 'Reintentar'}
        </button>
        <Link className="button session-error-home" replace state={{ showSignIn: true }} to="/">
          <ArrowLeft size={17} aria-hidden="true" />Volver a Inicio
        </Link>
      </div>
    </section>
  </main>
}
