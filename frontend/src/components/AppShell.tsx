import { useState } from 'react'
import {
  CalendarDays,
  CookingPot,
  Heart,
  History,
  LayoutDashboard,
  LogOut,
  Refrigerator,
  ShoppingCart,
  UserRound,
} from 'lucide-react'
import { NavLink, Outlet } from 'react-router-dom'
import { BrandLogo } from './BrandLogo'
import { appNavigation } from './navigation'
import { ScrollToTopButton } from './ScrollToTopButton'
import { authRepository } from '../features/auth/data/AuthRepository'
import { useNotifications } from '../shared/notifications/NotificationProvider'

const navigationIcons = {
  recipes: CookingPot,
  panel: LayoutDashboard,
  pantry: Refrigerator,
  planner: CalendarDays,
  shopping: ShoppingCart,
  favorites: Heart,
  history: History,
  profile: UserRound,
}

export function AppShell() {
  const [loggingOut, setLoggingOut] = useState(false)
  const { notify } = useNotifications()

  async function logout() {
    setLoggingOut(true)
    try { await authRepository.logout() }
    catch { await notify({ type: 'error', title: 'No se pudo cerrar la sesión', message: 'Intentá de nuevo.' }) }
    finally { setLoggingOut(false) }
  }

  return (
    <div className="app-shell">
      <aside className="sidebar">
        <NavLink className="wordmark" to="/panel" aria-label="CocinAPP, inicio">
          <BrandLogo />
        </NavLink>
        <p className="sidebar-label">TU COCINA</p>
        <nav className="primary-nav" aria-label="Navegación principal">
          {appNavigation.map(({ id, to, label, mobileLabel, mobile, ...linkProps }) => {
            const Icon = navigationIcons[id]
            return (
            <NavLink
              key={to}
              to={to}
              end={'end' in linkProps ? linkProps.end : undefined}
              className={({ isActive }) => `nav-link${mobile ? '' : ' nav-link-desktop-only'}${isActive ? ' active' : ''}`}
            >
              <Icon size={19} strokeWidth={1.8} aria-hidden="true" />
              <span className="nav-label-desktop">{label}</span><span className="nav-label-mobile">{mobileLabel}</span>
            </NavLink>
            )
          })}
        </nav>
        <button className="app-sidebar-logout" disabled={loggingOut} onClick={() => void logout()} type="button">
          <LogOut size={18} strokeWidth={1.8} aria-hidden="true" />
          <span>{loggingOut ? 'Cerrando…' : 'Cerrar sesión'}</span>
        </button>
      </aside>
      <main className="main-content"><NavLink aria-label="CocinAPP, inicio" className="mobile-brand" to="/panel"><BrandLogo /></NavLink><Outlet /></main>
      <ScrollToTopButton />
    </div>
  )
}
