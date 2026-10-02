import { useState } from 'react'
import { Plus, Pencil, RotateCcw, Trash2, X } from 'lucide-react'
import { getAdminData } from '../data/localAdminStore'
import { hasAdminReferences } from '../data/adminReferences'
import { createCategory, updateCategory, deleteCategory, restoreCategory } from '../data/categoriesStore'
import { countAdminUsage } from '../domain/adminUsage'
import { getKnownRecipes } from '../../recipes/data/availableRecipes'

export function CategoriesTab() {
  const data = getAdminData()
  const [categories, setCategories] = useState(data.categories)
  const [editor, setEditor] = useState<{ id?: string; name: string } | null>(null)
  const [error, setError] = useState('')
  const [search, setSearch] = useState('')
  const [statusFilter, setStatusFilter] = useState<'all' | 'active' | 'inactive'>('all')
  const [success, setSuccess] = useState('')

  const reload = () => setCategories(getAdminData().categories)

  const handleSave = (e: React.FormEvent) => {
    e.preventDefault()
    if (!editor) return
    try {
      if (editor.id) {
        updateCategory(editor.id, editor.name.trim())
      } else {
        createCategory(editor.name.trim())
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
  const visibleCategories = categories.filter((category) => category.name.toLocaleLowerCase('es').includes(search.trim().toLocaleLowerCase('es'))
    && (statusFilter === 'all' || (statusFilter === 'inactive') === category.isDeleted))

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
        <div><h2>Categorías de ingredientes</h2><p className="panel-intro">{visibleCategories.length} de {categories.length} categorías</p></div>
        <button className="button button-primary" onClick={() => { setEditor({ name: '' }); setError('') }} type="button">
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
              {c.isDeleted && <small className="error">Inactiva (Baja lógica)</small>}
            </div>
            <div className="record-actions">
              {!c.isDeleted ? (
                <>
                  <button aria-label={`Editar categoría ${c.name}`} className="pantry-icon-button" onClick={() => setEditor({ id: c.id, name: c.name })} type="button">
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
        {visibleCategories.length === 0 && <p className="empty">No hay categorías que coincidan con los filtros.</p>}
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
