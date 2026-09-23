import {
  CalendarDays,
  CookingPot,
  Heart,
  History,
  LayoutDashboard,
  Refrigerator,
  ShieldCheck,
  ShoppingCart,
  UserRound,
} from 'lucide-react'
import { NavLink, Outlet } from 'react-router-dom'

const navigation = [
  { to: '/panel', label: 'Panel', mobileLabel: 'Panel', Icon: LayoutDashboard, end: true },
  { to: '/recipes', label: 'Recetas', mobileLabel: 'Recetas', Icon: CookingPot },
  { to: '/pantry', label: 'Despensa', mobileLabel: 'Despensa', Icon: Refrigerator },
  { to: '/planner', label: 'Planificador', mobileLabel: 'Plan', Icon: CalendarDays },
  { to: '/shopping', label: 'Compras', mobileLabel: 'Compras', Icon: ShoppingCart },
  { to: '/favorites', label: 'Favoritos', mobileLabel: 'Favoritos', Icon: Heart },
  { to: '/history', label: 'Historial', mobileLabel: 'Historial', Icon: History },
  { to: '/profile', label: 'Perfil', mobileLabel: 'Perfil', Icon: UserRound },
  { to: '/admin', label: 'Administración', mobileLabel: 'Admin', Icon: ShieldCheck },
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
          {navigation.map(({ to, label, mobileLabel, Icon, end }) => (
            <NavLink
              key={to}
              to={to}
              end={end}
              className={({ isActive }) => `nav-link${isActive ? ' active' : ''}`}
            >
              <Icon size={19} strokeWidth={1.8} aria-hidden="true" />
              <span className="nav-label-desktop">{label}</span><span className="nav-label-mobile">{mobileLabel}</span>
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
