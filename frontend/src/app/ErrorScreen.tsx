import { AlertTriangle, LockKeyhole, SearchX, ServerOff } from 'lucide-react'
import { useId, type ReactNode } from 'react'
import { BrandLogo } from '../components/BrandLogo'
import './ErrorScreen.css'

const errorIcons = {
  403: LockKeyhole,
  404: SearchX,
  500: ServerOff,
}

interface ErrorScreenProps {
  title: string
  description: string
  children: ReactNode
  status?: keyof typeof errorIcons
  notice?: string
  busy?: boolean
  embedded?: boolean
}

export function ErrorScreen({
  title,
  description,
  children,
  status,
  notice,
  busy,
  embedded = false,
}: ErrorScreenProps) {
  const titleId = useId()
  const Icon = status ? errorIcons[status] : AlertTriangle
  const Container = embedded ? 'section' : 'main'

  return (
    <Container aria-busy={busy} aria-labelledby={titleId} className={embedded ? 'error-page error-page-embedded' : 'error-page'}>
      <div className="error-card">
        <BrandLogo className="error-logo" />
        <div className="error-visual">
          <div className="error-symbol" aria-hidden="true"><Icon size={32} strokeWidth={1.6} /></div>
          {status && <p className="error-status"><span>Error</span> {status}</p>}
        </div>
        <div className="error-content">
          <h1 id={titleId}>{title}</h1>
          <p className="error-description">{description}</p>
          {notice && <p className="error-notice" role="alert">{notice}</p>}
          <div className="error-actions">{children}</div>
        </div>
      </div>
    </Container>
  )
}
