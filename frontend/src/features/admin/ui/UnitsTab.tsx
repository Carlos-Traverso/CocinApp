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

export function UnitsTab() {
  const { notify } = useNotifications()
  const { data: snapshot, knownRecipes, loading, error, setError, reload } = useAdminCatalog()
  const data = snapshot ?? { categories: [], units: [], ingredients: [], recipes: [] }
  const units = data.units
  const [editor, setEditor] = useState<{
    id?: string
    name: string
    abbreviation: string
    dimension: string
    baseUnitId: string
    equivalenceMultiplier: string
    active: boolean
  } | null>(null)
  const [pending, setPending] = useState(false)
  const [search, setSearch] = useState('')
  const [dimensionFilter, setDimensionFilter] = useState('')
  const [statusFilter, setStatusFilter] = useState<'all' | 'active' | 'inactive'>('all')
  const debouncedSearch = useDebouncedSearch(search)

  const handleSave = async (e: React.FormEvent) => {
    e.preventDefault()
    if (!editor) return
    const invalidField = e.currentTarget.querySelector<HTMLElement>(':invalid')
    if (invalidField || !editor.name.trim() || !editor.abbreviation.trim()) {
      const invalidText = !editor.name.trim() ? 'Ingresá un nombre válido para la unidad.' : !editor.abbreviation.trim() ? 'Ingresá una abreviatura válida para la unidad.' : 'Revisá los campos obligatorios y sus valores.'
      setError(invalidText)
      ;(invalidField ?? e.currentTarget.querySelector<HTMLElement>('input'))?.focus()
      return
    }
    try {
      setPending(true)
      setError('')
      const multiplier = editor.baseUnitId ? parseFloat(editor.equivalenceMultiplier) : undefined
      if (editor.baseUnitId && (!multiplier || multiplier <= 0)) {
        setError('Debe especificar un multiplicador válido mayor a 0.')
        e.currentTarget.querySelector<HTMLElement>('input[type="number"]')?.focus()
        return
      }

      if (editor.id) {
        await adminRepository.updateUnit(editor.id, editor.name.trim(), editor.abbreviation.trim(), editor.dimension, editor.baseUnitId || undefined, multiplier, editor.active)
      } else {
        await adminRepository.createUnit(editor.name.trim(), editor.abbreviation.trim(), editor.dimension, editor.baseUnitId || undefined, multiplier, editor.active)
      }
      setEditor(null)
      setError('')
      void notify({ type: 'success', title: editor.id ? 'Unidad actualizada' : 'Unidad creada', message: editor.id ? 'Unidad actualizada.' : 'Unidad creada.' })
      await reload()
    } catch (err: any) {
      void notify({ type: 'error', title: 'No se pudo guardar la unidad', message: err.message })
    } finally {
      setPending(false)
    }
  }

  const usage = countAdminUsage(data, knownRecipes)
  const visibleUnits = units.filter((unit) => debouncedSearch.status !== 'waiting' && normalizePantryName(`${unit.name} ${unit.abbreviation}`).includes(normalizePantryName(debouncedSearch.query))
    && (!dimensionFilter || unit.dimension === dimensionFilter)
    && (statusFilter === 'all' || (statusFilter === 'active') === (unit.active && !unit.isDeleted)))

  const handleDelete = async (id: string, name: string) => {
    if (!await notify({ type: 'warning', title: 'Eliminar unidad', message: `¿Eliminar la unidad "${name}"? Si tiene referencias, se conservará como baja lógica.`, confirmLabel: 'Eliminar', cancelLabel: 'Cancelar' })) return
    await runDelete(() => adminRepository.deleteUnit(id), 'No se pudo eliminar la unidad.')
  }

  const runMutation = async (action: () => Promise<unknown>, fallback: string) => {
    setPending(true); setError('')
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
    setPending(true); setError('')
    let result: DeleteResult
    try {
      result = await action()
    } catch (cause) {
      void notify({ type: 'error', title: 'No se pudo eliminar la unidad', message: cause instanceof Error ? cause.message : fallback })
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
      void notify({ type: 'error', title: 'No se encontró la unidad', message: reloadFailed ? 'La unidad ya no existe y tampoco se pudo actualizar el catálogo.' : 'La unidad ya no existe. El catálogo se actualizó.' })
    } else if (reloadFailed) {
      void notify({ type: 'error', title: 'No se pudo actualizar el catálogo', message: 'La acción de eliminación se completó, pero no se pudo actualizar la lista. Volvé a cargar la pantalla.' })
    }
  }

  return (
    <div className="panel">
      <div className="section-header">
        <div><h2>Unidades de medida</h2><p className="panel-intro"><SearchFeedback resultCount={visibleUnits.length} status={debouncedSearch.status} /> · {units.length} unidades totales</p></div>
        <button className="button button-primary" disabled={loading || pending} onClick={() => { setEditor({ name: '', abbreviation: '', dimension: 'masa', baseUnitId: '', equivalenceMultiplier: '', active: true }); setError('') }} type="button">
          <Plus size={16} /> Nueva unidad
        </button>
      </div>

      <div className="admin-catalog-filters"><label className="field admin-filter-search"><span>Buscar unidad</span><input onChange={(event) => setSearch(event.currentTarget.value)} type="search" value={search} /></label><label className="field"><span>Dimensión</span><select onChange={(event) => setDimensionFilter(event.currentTarget.value)} value={dimensionFilter}><option value="">Todas</option><option value="masa">Masa</option><option value="volumen">Volumen</option><option value="conteo">Conteo</option></select></label><label className="field"><span>Estado</span><select onChange={(event) => setStatusFilter(event.currentTarget.value as typeof statusFilter)} value={statusFilter}><option value="all">Todas</option><option value="active">Activas</option><option value="inactive">Inactivas</option></select></label></div>

      {loading ? <p role="status">Cargando catálogo…</p> : <div className="records">
        {visibleUnits.map((u) => {
          const base = units.find(x => x.id === u.baseUnitId)
          return (
            <article className="record" key={u.id}>
              <div className="record-main">
                <strong>{u.name} ({u.abbreviation})</strong>
                <small>Dimensión: {u.dimension} {base ? `· Equivale a ${u.equivalenceMultiplier} ${base.abbreviation}` : '· Unidad base'} · {usage.units[u.id] ?? 0} usos</small>
                <span className={`admin-entity-status ${u.active && !u.isDeleted ? 'active' : 'inactive'}`}>{u.active && !u.isDeleted ? 'Activo' : 'Inactivo'}</span>
                {u.isDeleted && <small className="error">Baja lógica por referencias existentes</small>}
              </div>
              <div className="record-actions">
                {!u.isDeleted ? (
                  <>
                    <button aria-label={`Editar unidad ${u.name}`} className="pantry-icon-button" disabled={pending} onClick={() => setEditor({ id: u.id, name: u.name, abbreviation: u.abbreviation, dimension: u.dimension, baseUnitId: u.baseUnitId || '', equivalenceMultiplier: String(u.equivalenceMultiplier || ''), active: u.active })} type="button">
                      <Pencil size={17} />
                    </button>
                    <button aria-label={`Eliminar unidad ${u.name}`} className="pantry-icon-button" disabled={pending} onClick={() => void handleDelete(u.id, u.name)} type="button">
                      <Trash2 size={17} />
                    </button>
                  </>
                ) : <button className="button button-quiet" disabled={pending} onClick={() => void runMutation(() => adminRepository.restoreUnit(u.id), 'No se pudo reactivar la unidad.')} type="button"><RotateCcw size={15} /> Reactivar</button>}
              </div>
            </article>
          )
        })}
        {debouncedSearch.status !== 'waiting' && visibleUnits.length === 0 && <p className="empty">No hay unidades que coincidan con los filtros.</p>}
      </div>}

      {editor && (
        <dialog aria-labelledby="unit-editor-title" className="shopping-editor surface" onCancel={(event) => { event.preventDefault(); setEditor(null) }} ref={(node) => { if (node && !node.open) node.showModal() }}>
          <div className="shopping-editor-heading">
            <h2 id="unit-editor-title">{editor.id ? 'Editar unidad' : 'Nueva unidad'}</h2>
            <button aria-label="Cerrar editor de unidad" className="pantry-icon-button" onClick={() => setEditor(null)} type="button"><X size={19} /></button>
          </div>
          <form noValidate onSubmit={handleSave}>
            <div className="shopping-form-grid">
              <label className="field">
                <span>Nombre</span>
                <input required maxLength={50} value={editor.name} onChange={(e) => setEditor({ ...editor, name: e.target.value })} placeholder="Ej.: Kilogramo" />
              </label>
              <label className="field">
                <span>Abreviatura</span>
                <input required maxLength={10} value={editor.abbreviation} onChange={(e) => setEditor({ ...editor, abbreviation: e.target.value })} placeholder="Ej.: kg" />
              </label>
            </div>
            <label className="field">
              <span>Dimensión física</span>
              <select required value={editor.dimension} onChange={(e) => setEditor({ ...editor, dimension: e.target.value, baseUnitId: '', equivalenceMultiplier: '' })}>
                <option value="masa">Masa</option>
                <option value="volumen">Volumen</option>
                <option value="conteo">Conteo</option>
              </select>
            </label>
            <label className="field">
              <span>Unidad base (Opcional)</span>
              <select value={editor.baseUnitId} onChange={(e) => setEditor({ ...editor, baseUnitId: e.target.value })}>
                <option value="">(Esta es una unidad base)</option>
                {units.filter(u => u.dimension === editor.dimension && u.id !== editor.id && !u.isDeleted && (u.active || u.id === editor.baseUnitId)).map(u => (
                  <option key={u.id} value={u.id}>{u.name} ({u.abbreviation})</option>
                ))}
              </select>
            </label>
            {editor.baseUnitId && (
              <label className="field">
                <span>Equivale a (multiplicador)</span>
                <input required type="number" step="any" min="0.000001" value={editor.equivalenceMultiplier} onChange={(e) => setEditor({ ...editor, equivalenceMultiplier: e.target.value })} placeholder={`Ej.: 1000`} />
              </label>
            )}
            <label className="field"><span>Estado</span><select onChange={(event) => setEditor({ ...editor, active: event.currentTarget.value === 'active' })} value={editor.active ? 'active' : 'inactive'}><option value="active">Activo · disponible para usar</option><option value="inactive">Inactivo · no disponible para nuevos usos</option></select></label>
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
