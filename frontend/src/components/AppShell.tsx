import {
  CalendarDays,
  CookingPot,
  Heart,
  History,
  LayoutDashboard,
  Refrigerator,
  ShoppingCart,
  UserRound,
  ShieldCheck,
} from 'lucide-react'
import { NavLink, Outlet } from 'react-router-dom'
import { useAuth } from '../features/auth/data/localAuthStore'

export function AppShell() {
  const session = useAuth()
  
  const navigation = [
    { to: '/panel', label: 'Panel', mobileLabel: 'Panel', Icon: LayoutDashboard, end: true },
    { to: '/recipes', label: 'Recetas', mobileLabel: 'Recetas', Icon: CookingPot },
    { to: '/pantry', label: 'Despensa', mobileLabel: 'Despensa', Icon: Refrigerator },
    { to: '/planner', label: 'Planificación', mobileLabel: 'Plan', Icon: CalendarDays },
    { to: '/shopping', label: 'Lista de compras', mobileLabel: 'Compras', Icon: ShoppingCart },
    { to: '/favorites', label: 'Favoritos', mobileLabel: 'Favoritos', Icon: Heart },
    { to: '/history', label: 'Historial', mobileLabel: 'Historial', Icon: History },
    { to: '/profile', label: 'Perfil', mobileLabel: 'Perfil', Icon: UserRound },
  ]

  if (session?.role === 'ADMIN') {
    navigation.splice(1, 0, { to: '/admin', label: 'Administración', mobileLabel: 'Admin', Icon: ShieldCheck, end: false })
  }

  return (
    <div className="app-shell">
      <aside className="sidebar">
        <NavLink className="wordmark" to={session?.role === 'ADMIN' ? '/admin' : '/panel'} aria-label="CocinAPP, inicio">
          Cocin<span>APP</span>
        </NavLink>
        <p className="sidebar-label">{session?.role === 'ADMIN' ? 'GESTIÓN' : 'TU COCINA'}</p>
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
          <span className="avatar" aria-hidden="true">{session?.name?.charAt(0) || 'C'}</span>
          <span><strong>{session?.name || 'Mi cocina'}</strong><small>{session?.role === 'ADMIN' ? 'Administrador' : 'Espacio personal'}</small></span>
        </NavLink>
      </aside>
      <main className="main-content"><Outlet /></main>
    </div>
  )
}
