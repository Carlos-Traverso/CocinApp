import { useState } from 'react'
import { Plus, Pencil, RotateCcw, Trash2, X } from 'lucide-react'
import { normalizePantryName } from '../../pantry/domain/pantry'
import { SearchFeedback } from '../../../shared/search/SearchFeedback'
import { useDebouncedSearch } from '../../../shared/search/useDebouncedSearch'
import { adminRepository } from '../data/AdminRepository'
import type { DeleteResult } from '../data/AdminRepository'
import { countAdminUsage } from '../domain/adminUsage'
import { useAdminCatalog } from './useAdminCatalog'
import { useNotifications } from '../../../shared/notifications/NotificationProvider'

export function CategoriesTab() {
  const { notify } = useNotifications()
  const { data: snapshot, knownRecipes, loading, error, setError, reload } = useAdminCatalog()
  const data = snapshot ?? { categories: [], units: [], ingredients: [], recipes: [] }
  const categories = data.categories
  const [editor, setEditor] = useState<{ id?: string; name: string; active: boolean | null } | null>(null)
  const [search, setSearch] = useState('')
  const [statusFilter, setStatusFilter] = useState<'all' | 'active' | 'inactive'>('all')
  const debouncedSearch = useDebouncedSearch(search)

  const [pending, setPending] = useState(false)

  const handleSave = async (e: React.FormEvent) => {
    e.preventDefault()
    if (!editor) return
    const invalidField = e.currentTarget.querySelector<HTMLElement>(':invalid')
    if (invalidField || !editor.name.trim() || editor.active === null) {
      setError(!editor.name.trim() ? 'Ingresá un nombre válido para la categoría.' : 'Seleccioná un estado para la categoría.')
      ;(invalidField ?? e.currentTarget.querySelector<HTMLElement>('input'))?.focus()
      return
    }
    const active = editor.active
    try {
      setPending(true)
      setError('')
      if (editor.id) {
        await adminRepository.updateCategory(editor.id, editor.name.trim(), active)
      } else {
        await adminRepository.createCategory(editor.name.trim(), active)
      }
      setEditor(null)
      setError('')
      void notify({ type: 'success', title: editor.id ? 'Categoría actualizada' : 'Categoría creada', message: editor.id ? 'Categoría actualizada.' : 'Categoría creada.' })
      await reload()
    } catch (err: any) {
      void notify({ type: 'error', title: 'No se pudo guardar la categoría', message: err.message })
    } finally {
      setPending(false)
    }
  }

  const usage = countAdminUsage(data, knownRecipes)
  const visibleCategories = categories.filter((category) => debouncedSearch.status !== 'waiting' && normalizePantryName(category.name).includes(normalizePantryName(debouncedSearch.query))
    && (statusFilter === 'all' || (statusFilter === 'active') === (category.active && !category.isDeleted)))

  const handleDelete = async (id: string, name: string) => {
    if (!await notify({ type: 'warning', title: 'Eliminar categoría', message: `¿Eliminar la categoría "${name}"? Si tiene referencias, se conservará como baja lógica.`, confirmLabel: 'Eliminar', cancelLabel: 'Cancelar' })) return
    await runDelete(() => adminRepository.deleteCategory(id), 'No se pudo eliminar la categoría.')
  }

  const runMutation = async (action: () => Promise<unknown>, fallback: string) => {
    setPending(true)
    setError('')
    try {
      await action()
    } catch (cause) {
      void notify({ type: 'error', title: 'No se pudieron guardar los cambios', message: cause instanceof Error ? cause.message : fallback })
      setPending(false)
      return
    }

    try {
      await reload()
      void notify({ type: 'success', title: 'Cambios guardados', message: 'Cambios guardados.' })
    } catch {
      void notify({ type: 'error', title: 'Cambios guardados, lista desactualizada', message: 'La acción se completó, pero no se pudo actualizar el catálogo. Volvé a cargar la pantalla.' })
    } finally {
      setPending(false)
    }
  }

  const runDelete = async (action: () => Promise<DeleteResult>, fallback: string) => {
    setPending(true)
    setError('')
    let result: DeleteResult
    try {
      result = await action()
    } catch (cause) {
      void notify({ type: 'error', title: 'No se pudo eliminar la categoría', message: cause instanceof Error ? cause.message : fallback })
      setPending(false)
      return
    }

    let reloadFailed = false
    try {
      await reload()
    } catch {
      reloadFailed = true
    } finally {
      setPending(false)
    }

    if (result === 'not-found') {
      void notify({ type: 'error', title: 'No se encontró la categoría', message: reloadFailed ? 'La categoría ya no existe y tampoco se pudo actualizar el catálogo.' : 'La categoría ya no existe. El catálogo se actualizó.' })
    } else if (reloadFailed) {
      void notify({ type: 'error', title: 'No se pudo actualizar el catálogo', message: 'La acción de eliminación se completó, pero no se pudo actualizar la lista. Volvé a cargar la pantalla.' })
    }
  }

  return (
    <div className="panel">
      <div className="section-header">
        <div><h2>Categorías de ingredientes</h2><p className="panel-intro"><SearchFeedback resultCount={visibleCategories.length} status={debouncedSearch.status} /> · {categories.length} categorías totales</p></div>
        <button className="button button-primary" disabled={loading || pending} onClick={() => { setEditor({ name: '', active: null }); setError('') }} type="button">
          <Plus size={16} /> Nueva categoría
        </button>
      </div>

      <div className="admin-catalog-filters"><label className="field admin-filter-search"><span>Buscar categoría</span><input onChange={(event) => setSearch(event.currentTarget.value)} type="search" value={search} /></label><label className="field"><span>Estado</span><select onChange={(event) => setStatusFilter(event.currentTarget.value as typeof statusFilter)} value={statusFilter}><option value="all">Todas</option><option value="active">Activas</option><option value="inactive">Inactivas</option></select></label></div>

      {loading ? <p role="status">Cargando catálogo…</p> : <div className="records">
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
                  <button aria-label={`Editar categoría ${c.name}`} className="pantry-icon-button" disabled={pending} onClick={() => setEditor({ id: c.id, name: c.name, active: c.active })} type="button">
                    <Pencil size={17} />
                  </button>
                  <button aria-label={`Eliminar categoría ${c.name}`} className="pantry-icon-button" disabled={pending} onClick={() => void handleDelete(c.id, c.name)} type="button">
                    <Trash2 size={17} />
                  </button>
                </>
              ) : <button className="button button-quiet" disabled={pending} onClick={() => void runMutation(() => adminRepository.restoreCategory(c.id), 'No se pudo reactivar la categoría.')} type="button"><RotateCcw size={15} /> Reactivar</button>}
            </div>
          </article>
        ))}
        {debouncedSearch.status !== 'waiting' && visibleCategories.length === 0 && <p className="empty">No hay categorías que coincidan con los filtros.</p>}
      </div>}

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
