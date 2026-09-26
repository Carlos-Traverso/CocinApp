import { useState } from 'react'
import { Plus, Pencil, Trash2, X } from 'lucide-react'
import { getAdminData } from '../data/localAdminStore'
import { hasAdminReferences } from '../data/adminReferences'
import { createIngredient, updateIngredient, deleteIngredient } from '../data/ingredientsStore'

export function IngredientsTab() {
  const data = getAdminData()
  const [ingredients, setIngredients] = useState(data.ingredients)
  const categories = data.categories.filter(c => !c.isDeleted)
  const units = data.units.filter(u => !u.isDeleted)

  const [editor, setEditor] = useState<{
    id?: string
    name: string
    categoryId: string
    baseUnitId: string
  } | null>(null)
  const [error, setError] = useState('')
  const [search, setSearch] = useState('')

  const reload = () => setIngredients(getAdminData().ingredients)

  const handleSave = (e: React.FormEvent) => {
    e.preventDefault()
    if (!editor) return
    try {
      if (!editor.categoryId || !editor.baseUnitId) {
        throw new Error('Debe seleccionar categoría y unidad base.')
      }
      if (editor.id) {
        updateIngredient(editor.id, editor.name.trim(), editor.categoryId, editor.baseUnitId)
      } else {
        createIngredient(editor.name.trim(), editor.categoryId, editor.baseUnitId)
      }
      setEditor(null)
      setError('')
      reload()
    } catch (err: any) {
      setError(err.message)
    }
  }

  const handleDelete = (id: string, name: string) => {
    const hasRefs = hasAdminReferences('ingredient', id, name)
    const msg = hasRefs 
      ? `El ingrediente "${name}" está en uso. Se realizará una baja lógica.`
      : `¿Eliminar el ingrediente "${name}" permanentemente?`
    if (window.confirm(msg)) {
      deleteIngredient(id)
      reload()
    }
  }

  return (
    <div className="panel">
      <div className="section-header">
        <h2>Administrar Ingredientes</h2>
        <button className="button" onClick={() => { setEditor({ name: '', categoryId: categories[0]?.id || '', baseUnitId: units[0]?.id || '' }); setError('') }}>
          <Plus size={16} /> Nuevo ingrediente
        </button>
      </div>

      <label className="field admin-search"><span>Buscar ingrediente</span><input onChange={(event) => setSearch(event.currentTarget.value)} type="search" value={search} /></label>

      <div className="records">
        {ingredients.filter((ingredient) => ingredient.name.toLocaleLowerCase('es').includes(search.trim().toLocaleLowerCase('es'))).map((i) => {
          const cat = data.categories.find(c => c.id === i.categoryId)
          const unit = data.units.find(u => u.id === i.baseUnitId)
          return (
            <article className="record" key={i.id}>
              <div className="record-main">
                <strong>{i.name}</strong>
                <small>{cat?.name || 'Categoría desconocida'} | Unidad base: {unit?.abbreviation || 'Desconocida'}</small>
                {i.isDeleted && <small className="error">Inactivo (Baja lógica)</small>}
              </div>
              <div className="record-actions">
                {!i.isDeleted && (
                  <>
                    <button aria-label={`Editar ingrediente ${i.name}`} className="pantry-icon-button" onClick={() => setEditor({ id: i.id, name: i.name, categoryId: i.categoryId, baseUnitId: i.baseUnitId })} type="button">
                      <Pencil size={17} />
                    </button>
                    <button aria-label={`Eliminar ingrediente ${i.name}`} className="pantry-icon-button" onClick={() => handleDelete(i.id, i.name)} type="button">
                      <Trash2 size={17} />
                    </button>
                  </>
                )}
              </div>
            </article>
          )
        })}
        {ingredients.length === 0 && <p className="empty">No hay ingredientes administrados.</p>}
      </div>

      {editor && (
        <dialog aria-labelledby="ingredient-editor-title" className="shopping-editor surface" onCancel={(event) => { event.preventDefault(); setEditor(null) }} ref={(node) => { if (node && !node.open) node.showModal() }}>
          <div className="shopping-editor-heading">
            <h2 id="ingredient-editor-title">{editor.id ? 'Editar ingrediente' : 'Nuevo ingrediente'}</h2>
            <button aria-label="Cerrar editor de ingrediente" className="pantry-icon-button" onClick={() => setEditor(null)} type="button"><X size={19} /></button>
          </div>
          <form onSubmit={handleSave}>
            <label className="field">
              <span>Nombre</span>
              <input required maxLength={70} value={editor.name} onChange={(e) => setEditor({ ...editor, name: e.target.value })} placeholder="Ej.: Tomate perita" />
            </label>
            <label className="field">
              <span>Categoría</span>
              <select required value={editor.categoryId} onChange={(e) => setEditor({ ...editor, categoryId: e.target.value })}>
                <option value="" disabled>Seleccione...</option>
                {categories.map(c => <option key={c.id} value={c.id}>{c.name}</option>)}
              </select>
            </label>
            <label className="field">
              <span>Unidad base</span>
              <select required value={editor.baseUnitId} onChange={(e) => setEditor({ ...editor, baseUnitId: e.target.value })}>
                <option value="" disabled>Seleccione...</option>
                {units.map(u => <option key={u.id} value={u.id}>{u.name} ({u.abbreviation}) - {u.dimension}</option>)}
              </select>
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
