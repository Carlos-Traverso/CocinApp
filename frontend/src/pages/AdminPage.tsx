import type { ReactNode } from 'react'
import { AlertTriangle, ArrowRight, BookOpen, Boxes, CircleCheck, FolderTree, Ruler, Sparkles } from 'lucide-react'
import { Link } from 'react-router-dom'
import { getAdminData } from '../features/admin/data/localAdminStore'
import { createAdminDashboard } from '../features/admin/domain/adminDashboard'
import { CategoriesTab } from '../features/admin/ui/CategoriesTab'
import { UnitsTab } from '../features/admin/ui/UnitsTab'
import { IngredientsTab } from '../features/admin/ui/IngredientsTab'
import { RecipesTab } from '../features/admin/ui/RecipesTab'
import { getAvailableRecipes, getKnownRecipes } from '../features/recipes/data/availableRecipes'

export function AdminPage() {
  return (
    <div className="page feature-page">
      <header className="page-heading">
        <div>
          <p className="eyebrow">PANEL GENERAL</p>
          <h1>Dashboard</h1>
          <p className="page-lead">Estado general de los catálogos que alimentan CocinAPP.</p>
        </div>
      </header>
      <OverviewTab />
    </div>
  )
}

function AdminSection({ eyebrow, title, description, children }: { eyebrow: string; title: string; description: string; children: ReactNode }) {
  return <div className="page feature-page">
    <header className="page-heading"><div><p className="eyebrow">{eyebrow}</p><h1>{title}</h1><p className="page-lead">{description}</p></div></header>
    <section className="pane">{children}</section>
  </div>
}

export function AdminRecipesPage() {
  return <AdminSection eyebrow="CONTENIDO OFICIAL" title="Recetas" description="Creá, revisá y publicá las recetas disponibles para cocinar."><RecipesTab /></AdminSection>
}

export function AdminIngredientsPage() {
  return <AdminSection eyebrow="CATÁLOGO MAESTRO" title="Ingredientes" description="Administrá los ingredientes reutilizados por recetas y despensa."><IngredientsTab /></AdminSection>
}

export function AdminCategoriesPage() {
  return <AdminSection eyebrow="ORGANIZACIÓN" title="Categorías" description="Clasificá los ingredientes sin perder sus relaciones existentes."><CategoriesTab /></AdminSection>
}

export function AdminUnitsPage() {
  return <AdminSection eyebrow="CATÁLOGO MAESTRO" title="Unidades" description="Definí las unidades compatibles con cantidades e ingredientes."><UnitsTab /></AdminSection>
}

function OverviewTab() {
  const data = getAdminData()
  const dashboard = createAdminDashboard(data, getKnownRecipes(), getAvailableRecipes())
  const stats = [
    { label: 'Recetas totales', value: dashboard.metrics.total, icon: BookOpen },
    { label: 'Publicadas y activas', value: dashboard.metrics.active, icon: CircleCheck },
    { label: 'Borradores o inactivas', value: dashboard.metrics.inactive, icon: AlertTriangle },
    { label: 'Recetas destacadas', value: dashboard.metrics.featured, icon: Sparkles },
  ]

  return (
    <div className="admin-dashboard">
      <div className="stats">
        {stats.map((stat) => <article className="stat" key={stat.label}><stat.icon aria-hidden="true" size={19} /><small>{stat.label}</small><strong>{stat.value}</strong></article>)}
      </div>
      <div className="admin-dashboard-grid">
        <section className="admin-dashboard-panel">
          <div className="section-header"><div><p className="eyebrow">CATÁLOGOS</p><h2>Contenido disponible</h2></div></div>
          <div className="admin-catalog-links">
            <Link to="/admin/ingredients"><Boxes size={18} /><span><strong>{dashboard.catalog.ingredients}</strong> ingredientes activos</span><ArrowRight size={16} /></Link>
            <Link to="/admin/categories"><FolderTree size={18} /><span><strong>{dashboard.catalog.categories}</strong> categorías activas</span><ArrowRight size={16} /></Link>
            <Link to="/admin/units"><Ruler size={18} /><span><strong>{dashboard.catalog.units}</strong> unidades activas</span><ArrowRight size={16} /></Link>
          </div>
        </section>
        <section className="admin-dashboard-panel">
          <div className="section-header"><div><p className="eyebrow">CALIDAD</p><h2>Alertas de contenido</h2></div></div>
          <ul className="admin-alert-list">
            <li><span>Recetas sin imagen</span><strong>{dashboard.alerts.missingImage}</strong></li>
            <li><span>Recetas incompletas</span><strong>{dashboard.alerts.incomplete}</strong></li>
            <li><span>Borradores pendientes</span><strong>{dashboard.alerts.drafts}</strong></li>
          </ul>
          <Link className="button button-quiet" to="/admin/recipes">Revisar recetas <ArrowRight size={15} /></Link>
        </section>
      </div>
      <section className="admin-dashboard-panel">
        <div className="section-header"><div><p className="eyebrow">ACTIVIDAD</p><h2>Cambios recientes</h2></div></div>
        {dashboard.recent.length > 0 ? <div className="admin-recent-list">{dashboard.recent.map((recipe) => <div key={recipe.id}><span><strong>{recipe.title}</strong><small>{recipe.status === 'published' ? 'Publicada' : 'Borrador'}</small></span><time dateTime={recipe.updatedAt ?? recipe.createdAt}>{new Date(recipe.updatedAt ?? recipe.createdAt ?? '').toLocaleString('es-AR', { dateStyle: 'medium', timeStyle: 'short' })}</time></div>)}</div> : <p className="empty">Los cambios que realices en recetas aparecerán acá.</p>}
      </section>
    </div>
  )
}

