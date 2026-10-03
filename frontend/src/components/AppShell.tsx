import {
  CalendarDays,
  CookingPot,
  Heart,
  History,
  LayoutDashboard,
  Refrigerator,
  ShoppingCart,
  UserRound,
} from 'lucide-react'
import { NavLink, Outlet } from 'react-router-dom'
import { useAuth } from '../features/auth/data/localAuthStore'
import { BrandLogo } from './BrandLogo'
import { appNavigation } from './navigation'
import { ScrollToTopButton } from './ScrollToTopButton'

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
  const session = useAuth()

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
      <NavLink className="sidebar-foot" to="/profile">
          <span className="avatar" aria-hidden="true">{session?.name?.charAt(0) || 'C'}</span>
          <span><strong>{session?.name || 'Mi cocina'}</strong><small>Espacio personal</small></span>
        </NavLink>
      </aside>
      <main className="main-content"><NavLink aria-label="CocinAPP, inicio" className="mobile-brand" to="/panel"><BrandLogo /></NavLink><Outlet /></main>
      <ScrollToTopButton />
    </div>
  )
}
