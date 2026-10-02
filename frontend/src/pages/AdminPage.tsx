import type { ReactNode } from 'react'
import { getAdminData } from '../features/admin/data/localAdminStore'
import { CategoriesTab } from '../features/admin/ui/CategoriesTab'
import { UnitsTab } from '../features/admin/ui/UnitsTab'
import { IngredientsTab } from '../features/admin/ui/IngredientsTab'
import { RecipesTab } from '../features/admin/ui/RecipesTab'

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
  const stats = [
    { label: 'Categorías activas', value: data.categories.filter((c) => !c.isDeleted).length },
    { label: 'Unidades activas', value: data.units.filter((u) => !u.isDeleted).length },
    { label: 'Ingredientes activos', value: data.ingredients.filter((i) => !i.isDeleted).length },
    { label: 'Recetas oficiales', value: data.recipes.filter((r) => !r.isDeleted).length },
  ]
  
  return (
    <div className="stats">
      {stats.map((s) => (
        <div className="stat" key={s.label}>
          <small>{s.label}</small>
          <strong>{s.value}</strong>
        </div>
      ))}
    </div>
  )
}

