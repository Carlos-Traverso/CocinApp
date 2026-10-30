import { BrandLogo } from './BrandLogo'
import './LoadingScreen.css'

type LoadingScreenProps = {
  message?: string
  variant?: 'page' | 'fullscreen' | 'section'
}

export function LoadingScreen({ message = 'Cargando tu cocina…', variant = 'page' }: LoadingScreenProps) {
  return <div className={`loading-screen loading-screen-${variant}`} role="status" aria-live="polite" aria-atomic="true">
    <div className="loading-screen-content">
      <div className="loading-screen-emblem" aria-hidden="true">
        <img src="/assets/branding/cocinapp-marca.png" alt="" width="72" height="72" />
      </div>
      <div aria-hidden="true"><BrandLogo className="loading-screen-brand" /></div>
      <p className="loading-screen-message">{message}</p>
      <div className="loading-screen-dots" aria-hidden="true"><span /><span /><span /></div>
    </div>
  </div>
}
