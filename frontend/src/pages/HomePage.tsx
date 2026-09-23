import { ArrowRight, CalendarDays, CookingPot, Refrigerator, ShoppingCart } from 'lucide-react'
import { Link } from 'react-router-dom'

const actions = [
  { to: '/pantry', label: 'Revisar despensa', detail: 'Ingredientes y vencimientos', Icon: Refrigerator, tone: 'mint' },
  { to: '/planner', label: 'Armar mi semana', detail: 'Organizá las próximas comidas', Icon: CalendarDays, tone: 'sun' },
  { to: '/shopping', label: 'Lista de compras', detail: 'Lo que te falta para cocinar', Icon: ShoppingCart, tone: 'rose' },
]

export function HomePage() {
  return (
    <div className="page home-page">
      <header className="page-heading">
        <div>
          <p className="eyebrow">MI ESPACIO</p>
          <h1>Tu cocina, en orden.</h1>
          <p className="page-lead">Ideas para cocinar rico y aprovechar mejor lo que ya tenés.</p>
        </div>
        <Link className="button button-primary" to="/recipes">
          <CookingPot size={18} aria-hidden="true" /> Explorar recetas
        </Link>
      </header>

      <section className="welcome-band" aria-label="Recetas y planificación">
        <div className="welcome-icon"><CookingPot size={22} aria-hidden="true" /></div>
        <div>
          <p className="eyebrow">RECETAS Y PLANIFICACIÓN</p>
          <h2>Prepará tu próxima comida</h2>
          <p>Explorá recetas con tu despensa y organizá los almuerzos y cenas de la semana.</p>
        </div>
        <Link className="button button-dark" to="/recipes">Explorar recetas <ArrowRight size={17} aria-hidden="true" /></Link>
      </section>

      <section className="section-block" aria-labelledby="shortcuts-heading">
        <div className="section-heading">
          <div><p className="eyebrow">PARA HOY</p><h2 id="shortcuts-heading">¿Por dónde empezamos?</h2></div>
        </div>
        <div className="action-list">
          {actions.map(({ to, label, detail, Icon, tone }) => (
            <Link className="action-row" to={to} key={to}>
              <span className={`action-icon ${tone}`}><Icon size={20} aria-hidden="true" /></span>
              <span className="action-copy"><strong>{label}</strong><small>{detail}</small></span>
              <ArrowRight size={18} className="action-arrow" aria-hidden="true" />
            </Link>
          ))}
        </div>
      </section>
    </div>
  )
}
