import { ArrowLeft } from 'lucide-react'
import { Link } from 'react-router-dom'
import { BrandLogo } from '../components/BrandLogo'

export function NotFoundPage({ homePath = '/recipes', homeLabel = 'Volver a recetas' }: { homePath?: string; homeLabel?: string }) {
  return <div className="not-found-page"><div className="not-found-symbol"><BrandLogo alt="CocinAPP" variant="complete" /></div><p className="eyebrow">ERROR 404</p><h1>Esta página no está en el menú.</h1><p>Puede que la dirección haya cambiado o que el enlace ya no esté disponible.</p><Link className="button button-primary" to={homePath}><ArrowLeft aria-hidden="true" size={17} /> {homeLabel}</Link></div>
}
