import { useState } from 'react'
import { Plus, Pencil, RotateCcw, Trash2, X } from 'lucide-react'
import { getAdminData } from '../data/localAdminStore'
import { hasAdminReferences } from '../data/adminReferences'
import { createUnit, updateUnit, deleteUnit, restoreUnit } from '../data/unitsStore'
import { countAdminUsage } from '../domain/adminUsage'
import { getKnownRecipes } from '../../recipes/data/availableRecipes'

export function UnitsTab() {
  const data = getAdminData()
  const [units, setUnits] = useState(data.units)
  const [editor, setEditor] = useState<{
    id?: string
    name: string
    abbreviation: string
    dimension: string
    baseUnitId: string
    equivalenceMultiplier: string
  } | null>(null)
  const [error, setError] = useState('')
  const [search, setSearch] = useState('')
  const [dimensionFilter, setDimensionFilter] = useState('')
  const [statusFilter, setStatusFilter] = useState<'all' | 'active' | 'inactive'>('all')
  const [success, setSuccess] = useState('')

  const reload = () => setUnits(getAdminData().units)

  const handleSave = (e: React.FormEvent) => {
    e.preventDefault()
    if (!editor) return
    try {
      const multiplier = editor.baseUnitId ? parseFloat(editor.equivalenceMultiplier) : undefined
      if (editor.baseUnitId && (!multiplier || multiplier <= 0)) {
        throw new Error('Debe especificar un multiplicador válido mayor a 0.')
      }

      if (editor.id) {
        updateUnit(editor.id, editor.name.trim(), editor.abbreviation.trim(), editor.dimension, editor.baseUnitId || undefined, multiplier)
      } else {
        createUnit(editor.name.trim(), editor.abbreviation.trim(), editor.dimension, editor.baseUnitId || undefined, multiplier)
      }
      setEditor(null)
      setError('')
      setSuccess(editor.id ? 'Unidad actualizada.' : 'Unidad creada.')
      reload()
    } catch (err: any) {
      setError(err.message)
    }
  }

  const usage = countAdminUsage(data, getKnownRecipes())
  const visibleUnits = units.filter((unit) => `${unit.name} ${unit.abbreviation}`.toLocaleLowerCase('es').includes(search.trim().toLocaleLowerCase('es'))
    && (!dimensionFilter || unit.dimension === dimensionFilter)
    && (statusFilter === 'all' || (statusFilter === 'inactive') === unit.isDeleted))

  const handleDelete = (id: string, name: string, abbreviation: string) => {
    const hasRefs = hasAdminReferences('unit', id, abbreviation)
    const msg = hasRefs 
      ? `La unidad "${name}" está en uso. Se realizará una baja lógica.`
      : `¿Eliminar la unidad "${name}" permanentemente?`
    if (window.confirm(msg)) {
      deleteUnit(id)
      reload()
    }
  }

  return (
    <div className="panel">
      <div className="section-header">
        <div><h2>Unidades de medida</h2><p className="panel-intro">{visibleUnits.length} de {units.length} unidades</p></div>
        <button className="button button-primary" onClick={() => { setEditor({ name: '', abbreviation: '', dimension: 'masa', baseUnitId: '', equivalenceMultiplier: '' }); setError('') }} type="button">
          <Plus size={16} /> Nueva unidad
        </button>
      </div>

      {success && <p className="form-message success" role="status">{success}</p>}
      <div className="admin-catalog-filters"><label className="field admin-filter-search"><span>Buscar unidad</span><input onChange={(event) => setSearch(event.currentTarget.value)} type="search" value={search} /></label><label className="field"><span>Dimensión</span><select onChange={(event) => setDimensionFilter(event.currentTarget.value)} value={dimensionFilter}><option value="">Todas</option><option value="masa">Masa</option><option value="volumen">Volumen</option><option value="conteo">Conteo</option></select></label><label className="field"><span>Estado</span><select onChange={(event) => setStatusFilter(event.currentTarget.value as typeof statusFilter)} value={statusFilter}><option value="all">Todas</option><option value="active">Activas</option><option value="inactive">Inactivas</option></select></label></div>

      <div className="records">
        {visibleUnits.map((u) => {
          const base = units.find(x => x.id === u.baseUnitId)
          return (
            <article className="record" key={u.id}>
              <div className="record-main">
                <strong>{u.name} ({u.abbreviation})</strong>
                <small>Dimensión: {u.dimension} {base ? `· Equivale a ${u.equivalenceMultiplier} ${base.abbreviation}` : '· Unidad base'} · {usage.units[u.id] ?? 0} usos</small>
                {u.isDeleted && <small className="error">Inactiva (Baja lógica)</small>}
              </div>
              <div className="record-actions">
                {!u.isDeleted ? (
                  <>
                    <button aria-label={`Editar unidad ${u.name}`} className="pantry-icon-button" onClick={() => setEditor({ id: u.id, name: u.name, abbreviation: u.abbreviation, dimension: u.dimension, baseUnitId: u.baseUnitId || '', equivalenceMultiplier: String(u.equivalenceMultiplier || '') })} type="button">
                      <Pencil size={17} />
                    </button>
                    <button aria-label={`Eliminar unidad ${u.name}`} className="pantry-icon-button" onClick={() => handleDelete(u.id, u.name, u.abbreviation)} type="button">
                      <Trash2 size={17} />
                    </button>
                  </>
                ) : <button className="button button-quiet" onClick={() => { restoreUnit(u.id); reload(); setSuccess('Unidad reactivada.') }} type="button"><RotateCcw size={15} /> Reactivar</button>}
              </div>
            </article>
          )
        })}
        {visibleUnits.length === 0 && <p className="empty">No hay unidades que coincidan con los filtros.</p>}
      </div>

      {editor && (
        <dialog aria-labelledby="unit-editor-title" className="shopping-editor surface" onCancel={(event) => { event.preventDefault(); setEditor(null) }} ref={(node) => { if (node && !node.open) node.showModal() }}>
          <div className="shopping-editor-heading">
            <h2 id="unit-editor-title">{editor.id ? 'Editar unidad' : 'Nueva unidad'}</h2>
            <button aria-label="Cerrar editor de unidad" className="pantry-icon-button" onClick={() => setEditor(null)} type="button"><X size={19} /></button>
          </div>
          <form onSubmit={handleSave}>
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
                {units.filter(u => u.dimension === editor.dimension && u.id !== editor.id && !u.isDeleted).map(u => (
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
