import { LayoutDashboard, LogOut, ShieldCheck } from 'lucide-react'
import { NavLink, Outlet, useNavigate } from 'react-router-dom'
import { endSession, useAuth } from '../features/auth/data/localAuthStore'

export function AdminShell() {
  const session = useAuth()
  const navigate = useNavigate()
  function logout() {
    endSession()
    navigate('/', { replace: true })
  }

  return <div className="app-shell admin-shell">
    <aside className="sidebar admin-sidebar">
      <NavLink className="wordmark" to="/admin" aria-label="CocinAPP, administración">Cocin<span>APP</span></NavLink>
      <p className="sidebar-label">ADMINISTRACIÓN</p>
      <nav aria-label="Navegación de administración" className="primary-nav">
        <NavLink className={({ isActive }) => `nav-link${isActive ? ' active' : ''}`} end to="/admin"><LayoutDashboard size={19} aria-hidden="true" /><span>Resumen y catálogos</span></NavLink>
      </nav>
      <div className="sidebar-foot admin-identity">
        <span className="avatar" aria-hidden="true"><ShieldCheck size={18} /></span>
        <span><strong>{session?.name || 'Administrador'}</strong><small>Cuenta local de demostración</small></span>
      </div>
      <button className="sidebar-logout" onClick={logout} type="button"><LogOut size={18} aria-hidden="true" /><span>Cerrar sesión</span></button>
    </aside>
    <main className="main-content"><Outlet /></main>
  </div>
}
