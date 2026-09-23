import {
  CalendarDays,
  CookingPot,
  Heart,
  LayoutDashboard,
  Refrigerator,
  ShieldCheck,
  ShoppingCart,
  UserRound,
} from 'lucide-react'
import { NavLink, Outlet } from 'react-router-dom'

const navigation = [
  { to: '/panel', label: 'Panel', Icon: LayoutDashboard, end: true },
  { to: '/recipes', label: 'Recetas', Icon: CookingPot },
  { to: '/pantry', label: 'Despensa', Icon: Refrigerator },
  { to: '/planner', label: 'Planificador', Icon: CalendarDays },
  { to: '/shopping', label: 'Compras', Icon: ShoppingCart },
  { to: '/favorites', label: 'Favoritos', Icon: Heart },
  { to: '/profile', label: 'Perfil', Icon: UserRound },
  { to: '/admin', label: 'Administración', Icon: ShieldCheck },
]

export function AppShell() {
  return (
    <div className="app-shell">
      <aside className="sidebar">
        <NavLink className="wordmark" to="/panel" aria-label="CocinAPP, panel">
          Cocin<span>APP</span>
        </NavLink>
        <p className="sidebar-label">TU COCINA</p>
        <nav className="primary-nav" aria-label="Navegación principal">
          {navigation.map(({ to, label, Icon, end }) => (
            <NavLink
              key={to}
              to={to}
              end={end}
              className={({ isActive }) => `nav-link${isActive ? ' active' : ''}`}
            >
              <Icon size={19} strokeWidth={1.8} aria-hidden="true" />
              <span>{label}</span>
            </NavLink>
          ))}
        </nav>
        <NavLink className="sidebar-foot" to="/profile">
          <span className="avatar" aria-hidden="true">C</span>
          <span><strong>Mi cocina</strong><small>Espacio personal</small></span>
        </NavLink>
      </aside>
      <main className="main-content"><Outlet /></main>
    </div>
  )
}
