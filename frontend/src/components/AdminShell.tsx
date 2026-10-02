import { BookOpen, Boxes, FolderTree, LayoutDashboard, LogOut, Menu, Ruler, ShieldCheck, X } from 'lucide-react'
import { useEffect, useRef, useState } from 'react'
import { NavLink, Outlet, useLocation, useNavigate } from 'react-router-dom'
import { endSession, useAuth } from '../features/auth/data/localAuthStore'
import { adminNavigation, getAdminNavigationItem, type AdminNavigationKey } from '../features/admin/ui/adminNavigation'
import { BrandLogo } from './BrandLogo'

const icons = {
  dashboard: LayoutDashboard,
  recipes: BookOpen,
  ingredients: Boxes,
  categories: FolderTree,
  units: Ruler,
} satisfies Record<AdminNavigationKey, typeof LayoutDashboard>

export function AdminShell() {
  const session = useAuth()
  const navigate = useNavigate()
  const location = useLocation()
  const [drawerOpen, setDrawerOpen] = useState(false)
  const menuButtonRef = useRef<HTMLButtonElement>(null)
  const firstLinkRef = useRef<HTMLAnchorElement>(null)
  const currentSection = getAdminNavigationItem(location.pathname)

  useEffect(() => {
    if (!drawerOpen) return
    firstLinkRef.current?.focus()
    function closeOnEscape(event: KeyboardEvent) {
      if (event.key === 'Escape') {
        setDrawerOpen(false)
        menuButtonRef.current?.focus()
      }
    }
    document.addEventListener('keydown', closeOnEscape)
    return () => document.removeEventListener('keydown', closeOnEscape)
  }, [drawerOpen])

  function logout() {
    endSession()
    navigate('/', { replace: true })
  }

  return <div className={`app-shell admin-shell${drawerOpen ? ' drawer-open' : ''}`}>
    <button aria-label="Cerrar menú de administración" className="admin-drawer-overlay" onClick={() => setDrawerOpen(false)} type="button" />
    <aside aria-label="Administración" className="sidebar admin-sidebar" id="admin-navigation">
      <div className="admin-sidebar-head">
        <NavLink className="wordmark" ref={firstLinkRef} to="/admin" aria-label="CocinAPP, administración"><BrandLogo /></NavLink>
        <button aria-label="Cerrar menú" className="admin-drawer-close" onClick={() => setDrawerOpen(false)} type="button"><X aria-hidden="true" size={20} /></button>
      </div>
      <p className="sidebar-label">ADMINISTRACIÓN</p>
      <nav aria-label="Navegación de administración" className="primary-nav">
        {adminNavigation.map((item) => {
          const Icon = icons[item.key]
          return <NavLink className={({ isActive }) => `nav-link${isActive ? ' active' : ''}`} end={item.end} key={item.path} onClick={() => setDrawerOpen(false)} to={item.path}>
            <Icon size={19} aria-hidden="true" /><span>{item.label}</span>
          </NavLink>
        })}
      </nav>
      <div className="sidebar-foot admin-identity">
        <span className="avatar" aria-hidden="true"><ShieldCheck size={18} /></span>
        <span><strong>{session?.name || 'Administrador'}</strong><small>{session?.email || 'Cuenta local de demostración'}</small></span>
      </div>
      <button className="sidebar-logout" onClick={logout} type="button"><LogOut size={18} aria-hidden="true" /><span>Cerrar sesión</span></button>
    </aside>
    <main className="main-content admin-main-content">
      <header className="admin-topbar">
        <button aria-controls="admin-navigation" aria-expanded={drawerOpen} aria-label="Abrir menú de administración" className="admin-menu-button" onClick={() => setDrawerOpen(true)} ref={menuButtonRef} type="button"><Menu aria-hidden="true" size={21} /></button>
        <nav aria-label="Migas de pan" className="admin-breadcrumb"><NavLink to="/admin">Administración</NavLink><span aria-hidden="true">/</span><strong>{currentSection?.label ?? 'Página'}</strong></nav>
      </header>
      <Outlet />
    </main>
  </div>
}
