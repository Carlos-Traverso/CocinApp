import { LoadingScreen } from '../../../components/LoadingScreen'
import { useState } from 'react'
import { Plus, Pencil, RotateCcw, Trash2, X } from 'lucide-react'
import { normalizePantryName } from '../../pantry/domain/pantry'
import { SearchFeedback } from '../../../shared/search/SearchFeedback'
import { useDebouncedSearch } from '../../../shared/search/useDebouncedSearch'
import { adminRepository } from '../data/AdminRepository'
import { countAdminUsage } from '../domain/adminUsage'
import { useAdminCatalog } from './useAdminCatalog'

export function CategoriesTab() {
  const { data: snapshot, knownRecipes, loading, pending, error, setError, reload, save, remove } = useAdminCatalog()
  const data = snapshot ?? { categories: [], units: [], ingredients: [], recipes: [] }
  const categories = data.categories
  const [editor, setEditor] = useState<{ id?: string; name: string; active: boolean | null } | null>(null)
  const [search, setSearch] = useState('')
  const [statusFilter, setStatusFilter] = useState<'all' | 'active' | 'inactive'>('all')
  const debouncedSearch = useDebouncedSearch(search)


  const handleSave = async (e: React.FormEvent) => {
    e.preventDefault()
    if (!editor) return
    const invalidField = e.currentTarget.querySelector<HTMLElement>(':invalid')
    if (invalidField || !editor.name.trim() || editor.active === null) {
      setError(!editor.name.trim() ? 'Ingresá un nombre válido para la categoría.' : 'Seleccioná un estado para la categoría.')
      ;(invalidField ?? e.currentTarget.querySelector<HTMLElement>('input'))?.focus()
      return
    }
    const args = [editor.name.trim(), editor.active] as const
    await save(() => editor.id
      ? adminRepository.updateCategory(editor.id, ...args)
      : adminRepository.createCategory(...args),
    'No se pudo guardar la categoría.', () => setEditor(null))
  }

  const usage = countAdminUsage(data, knownRecipes)
  const visibleCategories = categories.filter((category) => debouncedSearch.status !== 'waiting' && normalizePantryName(category.name).includes(normalizePantryName(debouncedSearch.query))
    && (statusFilter === 'all' || (statusFilter === 'active') === (category.active && !category.isDeleted)))

  return (
    <div className="panel">
      <div className="section-header">
        <div><h2>Categorías de ingredientes</h2><p className="panel-intro"><SearchFeedback resultCount={visibleCategories.length} status={debouncedSearch.status} /> · {categories.length} categorías totales</p></div>
        <button className="button button-primary" disabled={loading || pending} onClick={() => { setEditor({ name: '', active: null }); setError('') }} type="button">
          <Plus size={16} /> Nueva categoría
        </button>
      </div>

      <div className="admin-catalog-filters"><label className="field admin-filter-search"><span>Buscar categoría</span><input onChange={(event) => setSearch(event.currentTarget.value)} type="search" value={search} /></label><label className="field"><span>Estado</span><select onChange={(event) => setStatusFilter(event.currentTarget.value as typeof statusFilter)} value={statusFilter}><option value="all">Todas</option><option value="active">Activas</option><option value="inactive">Inactivas</option></select></label></div>

      {loading ? <LoadingScreen message="Cargando catálogo…" variant="section" /> : <div className="records">
        {visibleCategories.map((c) => (
          <article className="record" key={c.id}>
            <div className="record-main">
              <strong>{c.name}</strong>
              <small>{data.ingredients.filter((ingredient) => ingredient.categoryId === c.id).length} ingredientes · {usage.categories[c.id] ?? 0} recetas asociadas</small>
              <span className={`admin-entity-status ${c.active && !c.isDeleted ? 'active' : 'inactive'}`}>{c.active && !c.isDeleted ? 'Activo' : 'Inactivo'}</span>
              {c.isDeleted && <small className="error">Archivada</small>}
            </div>
            <div className="record-actions">
              {!c.isDeleted ? (
                <>
                  <button aria-label={`Editar categoría ${c.name}`} className="pantry-icon-button" disabled={pending} onClick={() => setEditor({ id: c.id, name: c.name, active: c.active })} type="button">
                    <Pencil size={17} />
                  </button>
                  <button aria-label={`Eliminar categoría ${c.name}`} className="pantry-icon-button" disabled={pending} onClick={() => void remove('categoría', c.name, () => adminRepository.deleteCategory(c.id))} type="button">
                    <Trash2 size={17} />
                  </button>
                </>
              ) : <button className="button button-quiet" disabled={pending} onClick={() => void save(() => adminRepository.restoreCategory(c.id), 'No se pudo reactivar la categoría.')} type="button"><RotateCcw size={15} /> Reactivar</button>}
            </div>
          </article>
        ))}
        {debouncedSearch.status !== 'waiting' && visibleCategories.length === 0 && <p className="empty">No hay categorías que coincidan con los filtros.</p>}
      </div>}
      {error && !editor && <p className="form-message error" role="alert">{error} <button className="button button-quiet" disabled={pending} onClick={() => void reload().catch(() => undefined)} type="button">Volver a cargar</button></p>}

      {editor && (
        <dialog aria-labelledby="category-editor-title" className="shopping-editor surface" onCancel={(event) => { event.preventDefault(); setEditor(null) }} ref={(node) => { if (node && !node.open) node.showModal() }}>
          <div className="shopping-editor-heading">
            <h2 id="category-editor-title">{editor.id ? 'Editar categoría' : 'Nueva categoría'}</h2>
            <button aria-label="Cerrar editor de categoría" className="pantry-icon-button" onClick={() => setEditor(null)} type="button"><X size={19} /></button>
          </div>
          <form noValidate onSubmit={handleSave}>
            <label className="field">
              <span>Nombre</span>
              <input
                required
                maxLength={50}
                value={editor.name}
                onChange={(e) => setEditor({ ...editor, name: e.target.value })}
              />
            </label>
            <label className="field"><span>Estado</span><select required onChange={(event) => setEditor({ ...editor, active: event.currentTarget.value ? event.currentTarget.value === 'active' : null })} value={editor.active === null ? '' : editor.active ? 'active' : 'inactive'}><option value="">Seleccionar…</option><option value="active">Activo · disponible para usar</option><option value="inactive">Inactivo · no disponible para nuevos usos</option></select></label>
            {error && <p className="form-message error" role="alert">{error}</p>}
            <div className="pantry-dialog-actions">
              <button className="button button-quiet" type="button" onClick={() => setEditor(null)}>Cancelar</button>
              <button className="button button-primary" disabled={pending} type="submit">{pending ? 'Guardando…' : 'Guardar'}</button>
            </div>
          </form>
        </dialog>
      )}
    </div>
  )
}
