import { ArrowLeft } from 'lucide-react'
import { Link, useParams } from 'react-router-dom'

export function FeaturePage() {
  const { section = '' } = useParams()
  if (section !== 'admin') {
    return <div className="page"><Link className="back-link" to="/panel"><ArrowLeft size={16} /> Volver al panel</Link><h1>Esta sección no existe</h1></div>
  }

  return (
    <div className="page feature-page">
      <header className="page-heading">
        <div>
          <Link className="back-link" to="/panel"><ArrowLeft size={16} /> Panel</Link>
          <p className="eyebrow">GESTIÓN</p>
          <h1>Administración</h1>
          <p className="page-lead">Esta sección se incorporará en una fase posterior.</p>
        </div>
      </header>
      <section className="feature-content">
        <p>Mientras tanto, podés seguir usando las herramientas locales de CocinAPP.</p>
        <Link className="text-link" to="/panel">Volver al panel →</Link>
      </section>
    </div>
  )
}
