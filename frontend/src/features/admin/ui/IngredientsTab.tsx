import { LoadingScreen } from '../../../components/LoadingScreen'
import { useState } from 'react'
import { Plus, Pencil, RotateCcw, Trash2, X } from 'lucide-react'
import { normalizePantryName } from '../../pantry/domain/pantry'
import { SearchFeedback } from '../../../shared/search/SearchFeedback'
import { useDebouncedSearch } from '../../../shared/search/useDebouncedSearch'
import { adminRepository } from '../data/AdminRepository'
import { countAdminUsage } from '../domain/adminUsage'
import { useAdminCatalog } from './useAdminCatalog'

export function IngredientsTab() {
  const { data: snapshot, knownRecipes, loading, pending, error, setError, reload, save, remove } = useAdminCatalog()
  const data = snapshot ?? { categories: [], units: [], ingredients: [], recipes: [] }
  const ingredients = data.ingredients
  const [editor, setEditor] = useState<{
    id?: string
    name: string
    categoryId: string
    baseUnitId: string
    active: boolean | null
  } | null>(null)
  const [search, setSearch] = useState('')
  const [categoryFilter, setCategoryFilter] = useState('')
  const [statusFilter, setStatusFilter] = useState<'all' | 'active' | 'inactive'>('all')
  const debouncedSearch = useDebouncedSearch(search)
  const categories = data.categories.filter((category) => category.active && !category.isDeleted || category.id === editor?.categoryId)
  const units = data.units.filter((unit) => (unit.active && !unit.isDeleted && !unit.baseUnitId) || unit.id === editor?.baseUnitId)

  const handleSave = async (e: React.FormEvent) => {
    e.preventDefault()
    if (!editor) return
    const invalidField = e.currentTarget.querySelector<HTMLElement>(':invalid')
    if (invalidField || !editor.name.trim() || editor.active === null) {
      setError(!editor.name.trim() ? 'Ingresá un nombre válido para el ingrediente.' : editor.active === null ? 'Seleccioná un estado para el ingrediente.' : 'Revisá los campos obligatorios y sus valores.')
      ;(invalidField ?? e.currentTarget.querySelector<HTMLElement>('input'))?.focus()
      return
    }
    if (!editor.categoryId || !editor.baseUnitId) {
      setError('Seleccioná una categoría y una unidad base.')
      e.currentTarget.querySelector<HTMLElement>('select:invalid')?.focus()
      return
    }
    const args = [editor.name.trim(), editor.categoryId, editor.baseUnitId, editor.active] as const
    await save(() => editor.id
      ? adminRepository.updateIngredient(editor.id, ...args)
      : adminRepository.createIngredient(...args),
    'No se pudo guardar el ingrediente.', () => setEditor(null))
  }

  const usage = countAdminUsage(data, knownRecipes)
  const visibleIngredients = ingredients.filter((ingredient) => {
    if (debouncedSearch.status === 'waiting' || !normalizePantryName(ingredient.name).includes(normalizePantryName(debouncedSearch.query))) return false
    if (categoryFilter && ingredient.categoryId !== categoryFilter) return false
    if (statusFilter === 'active' && (!ingredient.active || ingredient.isDeleted)) return false
    if (statusFilter === 'inactive' && ingredient.active && !ingredient.isDeleted) return false
    return true
  })

  return (
    <div className="panel">
      <div className="section-header">
        <div><h2>Catálogo de ingredientes</h2><p className="panel-intro"><SearchFeedback resultCount={visibleIngredients.length} status={debouncedSearch.status} /> · {ingredients.length} ingredientes totales</p></div>
        <button className="button button-primary" disabled={loading || pending} onClick={() => { setEditor({ name: '', categoryId: '', baseUnitId: '', active: null }); setError('') }} type="button">
          <Plus size={16} /> Nuevo ingrediente
        </button>
      </div>

      <div className="admin-catalog-filters"><label className="field admin-filter-search"><span>Buscar ingrediente</span><input onChange={(event) => setSearch(event.currentTarget.value)} type="search" value={search} /></label><label className="field"><span>Categoría</span><select onChange={(event) => setCategoryFilter(event.currentTarget.value)} value={categoryFilter}><option value="">Todas</option>{categories.map((category) => <option key={category.id} value={category.id}>{category.name}</option>)}</select></label><label className="field"><span>Estado</span><select onChange={(event) => setStatusFilter(event.currentTarget.value as typeof statusFilter)} value={statusFilter}><option value="all">Todos</option><option value="active">Activos</option><option value="inactive">Inactivos</option></select></label></div>

      {loading ? <LoadingScreen message="Cargando catálogo…" variant="section" /> : <div className="records">
        {visibleIngredients.map((i) => {
          const cat = data.categories.find(c => c.id === i.categoryId)
          const unit = data.units.find(u => u.id === i.baseUnitId)
          return (
            <article className="record" key={i.id}>
              <div className="record-main">
                <strong>{i.name}</strong>
                <small>{cat?.name || 'Categoría desconocida'} · Unidad base: {unit?.abbreviation || 'Desconocida'} · {usage.ingredients[i.id] ?? 0} recetas</small>
                <span className={`admin-entity-status ${i.active && !i.isDeleted ? 'active' : 'inactive'}`}>{i.active && !i.isDeleted ? 'Activo' : 'Inactivo'}</span>
                {i.isDeleted && <small className="error">Archivado</small>}
              </div>
              <div className="record-actions">
                {!i.isDeleted ? (
                  <>
                    <button aria-label={`Editar ingrediente ${i.name}`} className="pantry-icon-button" disabled={pending} onClick={() => setEditor({ id: i.id, name: i.name, categoryId: i.categoryId, baseUnitId: i.baseUnitId, active: i.active })} type="button">
                      <Pencil size={17} />
                    </button>
                    <button aria-label={`Eliminar ingrediente ${i.name}`} className="pantry-icon-button" disabled={pending} onClick={() => void remove('ingrediente', i.name, () => adminRepository.deleteIngredient(i.id))} type="button">
                      <Trash2 size={17} />
                    </button>
                  </>
                ) : <button className="button button-quiet" disabled={pending} onClick={() => void save(() => adminRepository.restoreIngredient(i.id), 'No se pudo reactivar el ingrediente.')} type="button"><RotateCcw size={15} /> Reactivar</button>}
              </div>
            </article>
          )
        })}
        {debouncedSearch.status !== 'waiting' && visibleIngredients.length === 0 && <p className="empty">No hay ingredientes que coincidan con los filtros.</p>}
      </div>}
      {error && !editor && <p className="form-message error" role="alert">{error} <button className="button button-quiet" disabled={pending} onClick={() => void reload().catch(() => undefined)} type="button">Volver a cargar</button></p>}

      {editor && (
        <dialog aria-labelledby="ingredient-editor-title" className="shopping-editor surface" onCancel={(event) => { event.preventDefault(); setEditor(null) }} ref={(node) => { if (node && !node.open) node.showModal() }}>
          <div className="shopping-editor-heading">
            <h2 id="ingredient-editor-title">{editor.id ? 'Editar ingrediente' : 'Nuevo ingrediente'}</h2>
            <button aria-label="Cerrar editor de ingrediente" className="pantry-icon-button" onClick={() => setEditor(null)} type="button"><X size={19} /></button>
          </div>
          <form noValidate onSubmit={handleSave}>
            <label className="field">
              <span>Nombre</span>
              <input required maxLength={70} value={editor.name} onChange={(e) => setEditor({ ...editor, name: e.target.value })} placeholder="Ej.: Tomate perita" />
            </label>
            <label className="field"><span>Estado</span><select required onChange={(event) => setEditor({ ...editor, active: event.currentTarget.value ? event.currentTarget.value === 'active' : null })} value={editor.active === null ? '' : editor.active ? 'active' : 'inactive'}><option value="">Seleccionar…</option><option value="active">Activo · disponible para usar</option><option value="inactive">Inactivo · no disponible para nuevos usos</option></select></label>
            <label className="field">
              <span>Categoría</span>
              <select required value={editor.categoryId} onChange={(e) => setEditor({ ...editor, categoryId: e.target.value })}>
                <option value="">Seleccionar…</option>
                {categories.map(c => <option key={c.id} value={c.id}>{c.name}</option>)}
              </select>
            </label>
            <label className="field">
              <span>Unidad base</span>
              <select required value={editor.baseUnitId} onChange={(e) => setEditor({ ...editor, baseUnitId: e.target.value })}>
                <option value="">Seleccionar…</option>
                {units.map(u => <option key={u.id} value={u.id}>{u.name} ({u.abbreviation}) - {u.dimension}</option>)}
              </select>
            </label>
            
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
