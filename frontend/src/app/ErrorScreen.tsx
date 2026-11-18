import { AlertTriangle, LockKeyhole, SearchX } from 'lucide-react'
import { useId, type ReactNode } from 'react'
import { BrandLogo } from '../components/BrandLogo'
import './ErrorScreen.css'

const errorIcons = {
  403: LockKeyhole,
  404: SearchX,
}

interface ErrorScreenProps {
  title: string
  description: string
  children: ReactNode
  status?: 403 | 404
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

  return <Container aria-busy={busy} aria-labelledby={titleId} className={embedded ? 'error-page error-page-embedded' : 'error-page'}>
    <div className="error-card">
      <BrandLogo className="error-logo" />
      <div className="error-symbol" aria-hidden="true"><Icon size={30} strokeWidth={1.7} /></div>
      {status && <p className="eyebrow">Error {status}</p>}
      <h1 id={titleId}>{title}</h1>
      <p className="error-description">{description}</p>
      {notice && <p className="error-notice" role="alert">{notice}</p>}
      <div className="error-actions">{children}</div>
    </div>
  </Container>
}
