import { useState, useEffect } from 'react'
import { ArrowLeft } from 'lucide-react'
import { Link } from 'react-router-dom'
import { getAdminData } from '../features/admin/data/localAdminStore'
import { CategoriesTab } from '../features/admin/ui/CategoriesTab'
import { UnitsTab } from '../features/admin/ui/UnitsTab'
import { IngredientsTab } from '../features/admin/ui/IngredientsTab'
import { RecipesTab } from '../features/admin/ui/RecipesTab'

export function AdminPage() {
  const [activeTab, setActiveTab] = useState('overview')

  // We can subscribe to storage events to force re-render if needed
  useEffect(() => {
    const handleStorage = () => setActiveTab((prev) => prev) // Just a trigger
    window.addEventListener('storage', handleStorage)
    return () => window.removeEventListener('storage', handleStorage)
  }, [])

  return (
    <div className="page feature-page">
      <header className="page-heading">
        <div>
          <Link className="back-link" to="/panel"><ArrowLeft size={16} /> Panel</Link>
          <p className="eyebrow">GESTIÓN DE CONTENIDO</p>
          <h1>Administración local</h1>
          <p className="page-lead">Prototipo de administración (modo local).</p>
        </div>
      </header>

      <div className="tabs" role="tablist">
        <button
          aria-selected={activeTab === 'overview'}
          className={activeTab === 'overview' ? 'active' : ''}
          onClick={() => setActiveTab('overview')}
          role="tab"
          type="button"
        >
          Resumen
        </button>
        <button
          aria-selected={activeTab === 'categories'}
          className={activeTab === 'categories' ? 'active' : ''}
          onClick={() => setActiveTab('categories')}
          role="tab"
          type="button"
        >
          Categorías
        </button>
        <button
          aria-selected={activeTab === 'units'}
          className={activeTab === 'units' ? 'active' : ''}
          onClick={() => setActiveTab('units')}
          role="tab"
          type="button"
        >
          Unidades
        </button>
        <button
          aria-selected={activeTab === 'ingredients'}
          className={activeTab === 'ingredients' ? 'active' : ''}
          onClick={() => setActiveTab('ingredients')}
          role="tab"
          type="button"
        >
          Ingredientes
        </button>
        <button
          aria-selected={activeTab === 'recipes'}
          className={activeTab === 'recipes' ? 'active' : ''}
          onClick={() => setActiveTab('recipes')}
          role="tab"
          type="button"
        >
          Recetas Oficiales
        </button>
      </div>

      <section className="pane">
        {activeTab === 'overview' && <OverviewTab />}
        {activeTab === 'categories' && <CategoriesTab />}
        {activeTab === 'units' && <UnitsTab />}
        {activeTab === 'ingredients' && <IngredientsTab />}
        {activeTab === 'recipes' && <RecipesTab />}
      </section>
    </div>
  )
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

