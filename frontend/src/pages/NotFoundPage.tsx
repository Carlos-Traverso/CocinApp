import { ArrowLeft, Compass } from 'lucide-react'
import { Link } from 'react-router-dom'

export function NotFoundPage({ homePath = '/recipes', homeLabel = 'Volver a recetas' }: { homePath?: string; homeLabel?: string }) {
  return <div className="not-found-page"><div aria-hidden="true" className="not-found-symbol"><Compass size={44} strokeWidth={1.5} /></div><p className="eyebrow">ERROR 404</p><h1>Esta página no está en el menú.</h1><p>Puede que la dirección haya cambiado o que el enlace ya no esté disponible.</p><Link className="button button-primary" to={homePath}><ArrowLeft aria-hidden="true" size={17} /> {homeLabel}</Link></div>
}
