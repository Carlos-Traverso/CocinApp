import { useState } from 'react'
import { Plus, Pencil, RotateCcw, Trash2, X } from 'lucide-react'
import { getAdminData } from '../data/localAdminStore'
import { hasAdminReferences } from '../data/adminReferences'
import { normalizePantryName } from '../../pantry/domain/pantry'
import { SearchFeedback } from '../../../shared/search/SearchFeedback'
import { useDebouncedSearch } from '../../../shared/search/useDebouncedSearch'
import { createCategory, updateCategory, deleteCategory, restoreCategory } from '../data/categoriesStore'
import { countAdminUsage } from '../domain/adminUsage'
import { getKnownRecipes } from '../../recipes/data/availableRecipes'

export function CategoriesTab() {
  const data = getAdminData()
  const [categories, setCategories] = useState(data.categories)
  const [editor, setEditor] = useState<{ id?: string; name: string; active: boolean } | null>(null)
  const [error, setError] = useState('')
  const [search, setSearch] = useState('')
  const [statusFilter, setStatusFilter] = useState<'all' | 'active' | 'inactive'>('all')
  const debouncedSearch = useDebouncedSearch(search)
  const [success, setSuccess] = useState('')

  const reload = () => setCategories(getAdminData().categories)

  const handleSave = (e: React.FormEvent) => {
    e.preventDefault()
    if (!editor) return
    try {
      if (editor.id) {
        updateCategory(editor.id, editor.name.trim(), editor.active)
      } else {
        createCategory(editor.name.trim(), editor.active)
      }
      setEditor(null)
      setError('')
      setSuccess(editor.id ? 'Categoría actualizada.' : 'Categoría creada.')
      reload()
    } catch (err: any) {
      setError(err.message)
    }
  }

  const usage = countAdminUsage(data, getKnownRecipes())
  const visibleCategories = categories.filter((category) => debouncedSearch.status !== 'waiting' && normalizePantryName(category.name).includes(normalizePantryName(debouncedSearch.query))
    && (statusFilter === 'all' || (statusFilter === 'active') === (category.active && !category.isDeleted)))

  const handleDelete = (id: string, name: string) => {
    const isReferenced = hasAdminReferences('category', id, name)
    const msg = isReferenced
      ? `La categoría "${name}" está en uso. Se realizará una baja lógica y no estará disponible para nuevos registros.`
      : `¿Eliminar la categoría "${name}" permanentemente?`
    if (window.confirm(msg)) {
      deleteCategory(id)
      reload()
    }
  }

  return (
    <div className="panel">
      <div className="section-header">
        <div><h2>Categorías de ingredientes</h2><p className="panel-intro"><SearchFeedback resultCount={visibleCategories.length} status={debouncedSearch.status} /> · {categories.length} categorías totales</p></div>
        <button className="button button-primary" onClick={() => { setEditor({ name: '', active: true }); setError('') }} type="button">
          <Plus size={16} /> Nueva categoría
        </button>
      </div>

      {success && <p className="form-message success" role="status">{success}</p>}
      <div className="admin-catalog-filters"><label className="field admin-filter-search"><span>Buscar categoría</span><input onChange={(event) => setSearch(event.currentTarget.value)} type="search" value={search} /></label><label className="field"><span>Estado</span><select onChange={(event) => setStatusFilter(event.currentTarget.value as typeof statusFilter)} value={statusFilter}><option value="all">Todas</option><option value="active">Activas</option><option value="inactive">Inactivas</option></select></label></div>

      <div className="records">
        {visibleCategories.map((c) => (
          <article className="record" key={c.id}>
            <div className="record-main">
              <strong>{c.name}</strong>
              <small>{data.ingredients.filter((ingredient) => ingredient.categoryId === c.id).length} ingredientes · {usage.categories[c.id] ?? 0} recetas asociadas</small>
              <span className={`admin-entity-status ${c.active && !c.isDeleted ? 'active' : 'inactive'}`}>{c.active && !c.isDeleted ? 'Activo' : 'Inactivo'}</span>
              {c.isDeleted && <small className="error">Baja lógica por referencias existentes</small>}
            </div>
            <div className="record-actions">
              {!c.isDeleted ? (
                <>
                  <button aria-label={`Editar categoría ${c.name}`} className="pantry-icon-button" onClick={() => setEditor({ id: c.id, name: c.name, active: c.active })} type="button">
                    <Pencil size={17} />
                  </button>
                  <button aria-label={`Eliminar categoría ${c.name}`} className="pantry-icon-button" onClick={() => handleDelete(c.id, c.name)} type="button">
                    <Trash2 size={17} />
                  </button>
                </>
              ) : <button className="button button-quiet" onClick={() => { restoreCategory(c.id); reload(); setSuccess('Categoría reactivada.') }} type="button"><RotateCcw size={15} /> Reactivar</button>}
            </div>
          </article>
        ))}
        {debouncedSearch.status !== 'waiting' && visibleCategories.length === 0 && <p className="empty">No hay categorías que coincidan con los filtros.</p>}
      </div>

      {editor && (
        <dialog aria-labelledby="category-editor-title" className="shopping-editor surface" onCancel={(event) => { event.preventDefault(); setEditor(null) }} ref={(node) => { if (node && !node.open) node.showModal() }}>
          <div className="shopping-editor-heading">
            <h2 id="category-editor-title">{editor.id ? 'Editar categoría' : 'Nueva categoría'}</h2>
            <button aria-label="Cerrar editor de categoría" className="pantry-icon-button" onClick={() => setEditor(null)} type="button"><X size={19} /></button>
          </div>
          <form onSubmit={handleSave}>
            <label className="field">
              <span>Nombre</span>
              <input
                required
                maxLength={50}
                value={editor.name}
                onChange={(e) => setEditor({ ...editor, name: e.target.value })}
              />
            </label>
            <label className="field"><span>Estado</span><select onChange={(event) => setEditor({ ...editor, active: event.currentTarget.value === 'active' })} value={editor.active ? 'active' : 'inactive'}><option value="active">Activo · disponible para usar</option><option value="inactive">Inactivo · no disponible para nuevos usos</option></select></label>
            {error && <p className="form-message error" role="alert">{error}</p>}
            <div className="pantry-dialog-actions">
              <button className="button button-quiet" type="button" onClick={() => setEditor(null)}>Cancelar</button>
              <button className="button button-primary" type="submit">Guardar</button>
            </div>
          </form>
        </dialog>
      )}
    </div>
  )
}
