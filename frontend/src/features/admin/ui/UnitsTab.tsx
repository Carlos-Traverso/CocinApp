import { useState } from 'react'
import { Plus, Pencil, Trash2, X } from 'lucide-react'
import { getAdminData } from '../data/localAdminStore'
import { createUnit, updateUnit, deleteUnit } from '../data/unitsStore'
import { readPantryItems } from '../../pantry/data/localPantryStore'

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

  const reload = () => setUnits(getAdminData().units)

  const checkReferences = (id: string, abbr: string) => {
    const adminData = getAdminData()
    const usedInIngredients = adminData.ingredients.some((i) => i.baseUnitId === id)
    const usedInRecipes = adminData.recipes.some((r) => r.ingredients.some((ing) => ing.unitId === id))
    const usedInPantry = readPantryItems().some((i) => i.unit === abbr)
    return usedInIngredients || usedInRecipes || usedInPantry
  }

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
      reload()
    } catch (err: any) {
      setError(err.message)
    }
  }

  const handleDelete = (id: string, name: string, abbr: string) => {
    const hasRefs = checkReferences(id, abbr)
    const msg = hasRefs 
      ? `La unidad "${name}" está en uso. Se realizará una baja lógica.`
      : `¿Eliminar la unidad "${name}" permanentemente?`
    if (window.confirm(msg)) {
      deleteUnit(id, hasRefs)
      reload()
    }
  }

  return (
    <div className="panel">
      <div className="section-header">
        <h2>Administrar Unidades</h2>
        <button className="button" onClick={() => { setEditor({ name: '', abbreviation: '', dimension: 'masa', baseUnitId: '', equivalenceMultiplier: '' }); setError('') }}>
          <Plus size={16} /> Nueva unidad
        </button>
      </div>

      <div className="records">
        {units.map((u) => {
          const base = units.find(x => x.id === u.baseUnitId)
          return (
            <article className="record" key={u.id}>
              <div className="record-main">
                <strong>{u.name} ({u.abbreviation})</strong>
                <small>Dimensión: {u.dimension} {base ? `| Equivale a ${u.equivalenceMultiplier} ${base.abbreviation}` : '| Unidad base'}</small>
                {u.isDeleted && <small className="error">Inactiva (Baja lógica)</small>}
              </div>
              <div className="record-actions">
                {!u.isDeleted && (
                  <>
                    <button className="pantry-icon-button" onClick={() => setEditor({ id: u.id, name: u.name, abbreviation: u.abbreviation, dimension: u.dimension, baseUnitId: u.baseUnitId || '', equivalenceMultiplier: String(u.equivalenceMultiplier || '') })}>
                      <Pencil size={17} />
                    </button>
                    <button className="pantry-icon-button" onClick={() => handleDelete(u.id, u.name, u.abbreviation)}>
                      <Trash2 size={17} />
                    </button>
                  </>
                )}
              </div>
            </article>
          )
        })}
        {units.length === 0 && <p className="empty">No hay unidades administradas.</p>}
      </div>

      {editor && (
        <dialog open className="shopping-editor surface">
          <div className="shopping-editor-heading">
            <h2>{editor.id ? 'Editar unidad' : 'Nueva unidad'}</h2>
            <button className="pantry-icon-button" onClick={() => setEditor(null)}><X size={19} /></button>
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
                <option value="unidad">Unidad (Count)</option>
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
            {error && <p className="form-message error">{error}</p>}
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
