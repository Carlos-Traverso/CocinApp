import { useEffect, useRef, useState } from 'react'
import {
  CalendarDays,
  CookingPot,
  Heart,
  History,
  LayoutDashboard,
  LogOut,
  Ellipsis,
  Refrigerator,
  ShoppingCart,
  UserRound,
} from 'lucide-react'
import { NavLink, Outlet, useLocation } from 'react-router-dom'
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

const mobilePrimary = ['panel', 'recipes', 'planner', 'shopping']

function NavigationLink({ item, label = item.label, onClick }: { item: typeof appNavigation[number]; label?: string; onClick?: () => void }) {
  const { id, to } = item
  const Icon = navigationIcons[id]
  return (
    <NavLink className="nav-link" end={'end' in item ? item.end : undefined} onClick={onClick} to={to}>
      <Icon size={19} strokeWidth={1.8} aria-hidden="true" />
      <span>{label}</span>
    </NavLink>
  )
}

const mobileMain = appNavigation.filter(({ id, mobile }) => mobile && mobilePrimary.includes(id))
const mobileMore = appNavigation.filter(({ id, mobile }) => mobile && !mobilePrimary.includes(id))

function MobileNavigation({ loggingOut, onLogout }: { loggingOut: boolean; onLogout: () => void }) {
  const location = useLocation()
  const [openAt, setOpenAt] = useState<string>()
  const trigger = useRef<HTMLButtonElement>(null)
  const expanded = openAt === location.key
  const active = mobileMore.some(({ to }) => location.pathname === to)

  function close() {
    setOpenAt(undefined)
    trigger.current?.focus()
  }

  useEffect(() => {
    if (!expanded) return
    function handleEscape(event: KeyboardEvent) {
      if (event.key === 'Escape') close()
    }
    window.addEventListener('keydown', handleEscape)
    return () => window.removeEventListener('keydown', handleEscape)
  }, [expanded])

  return (
    <nav className="mobile-navigation" aria-label="Navegación principal" onBlur={(event) => {
      if (event.relatedTarget && !event.currentTarget.contains(event.relatedTarget)) setOpenAt(undefined)
    }}>
      {mobileMain.map((item) => <NavigationLink item={item} key={item.id} label={item.mobileLabel} onClick={() => setOpenAt(undefined)} />)}
      <button aria-controls="mobile-more" aria-expanded={expanded} className={`nav-link mobile-more-toggle${active || expanded ? ' active' : ''}`} onClick={() => setOpenAt(expanded ? undefined : location.key)} ref={trigger} type="button">
        <Ellipsis size={20} aria-hidden="true" /> Más
      </button>
      {expanded && <button aria-hidden="true" className="mobile-more-backdrop" onClick={close} tabIndex={-1} type="button" />}
      <div className="mobile-more-links" hidden={!expanded} id="mobile-more">
        {mobileMore.map((item) => <NavigationLink item={item} key={item.id} onClick={close} />)}
        <button className="nav-link mobile-more-logout" disabled={loggingOut} onClick={onLogout} type="button">
          <LogOut size={18} aria-hidden="true" /> {loggingOut ? 'Cerrando…' : 'Cerrar sesión'}
        </button>
      </div>
    </nav>
  )
}

export function AppShell() {
  const { pathname } = useLocation()
  const [, section, recipeId] = pathname.toLowerCase().split('/')
  const background = section === 'recipes' && recipeId ? 'recipe-detail' : section
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
      <aside className="sidebar app-sidebar">
        <div className="app-sidebar-header">
          <NavLink className="wordmark" to="/panel" aria-label="CocinAPP, inicio">
            <BrandLogo />
          </NavLink>
          <p className="app-sidebar-tagline">Tu cocina, más organizada</p>
        </div>
        <p className="sidebar-label">TU COCINA</p>
        <nav className="primary-nav" aria-label="Navegación principal">
          {appNavigation.map((item) => item.id === 'profile'
            ? <div className="app-sidebar-profile" key={item.id}><NavigationLink item={item} /></div>
            : <NavigationLink item={item} key={item.id} />)}
        </nav>
        <MobileNavigation loggingOut={loggingOut} onLogout={() => void logout()} />
        <button className="app-sidebar-logout" disabled={loggingOut} onClick={() => void logout()} type="button">
          <LogOut size={18} strokeWidth={1.8} aria-hidden="true" />
          <span>{loggingOut ? 'Cerrando…' : 'Cerrar sesión'}</span>
        </button>
      </aside>
      <main className="main-content" data-page-background={background}><NavLink aria-label="CocinAPP, inicio" className="mobile-brand" to="/panel"><BrandLogo /></NavLink><Outlet /></main>
      <ScrollToTopButton />
    </div>
  )
}
