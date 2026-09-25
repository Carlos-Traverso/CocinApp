import { useState } from 'react'
import { Plus, Pencil, Trash2, X } from 'lucide-react'
import { getAdminData } from '../data/localAdminStore'
import { createCategory, updateCategory, deleteCategory } from '../data/categoriesStore'
import { readPantryItems } from '../../pantry/data/localPantryStore'

export function CategoriesTab() {
  const data = getAdminData()
  const [categories, setCategories] = useState(data.categories)
  const [editor, setEditor] = useState<{ id?: string; name: string } | null>(null)
  const [error, setError] = useState('')

  const reload = () => setCategories(getAdminData().categories)

  const checkReferences = (id: string, name: string) => {
    const adminData = getAdminData()
    const usedInIngredients = adminData.ingredients.some((i) => i.categoryId === id)
    const usedInPantry = readPantryItems().some((i) => i.category === name)
    return usedInIngredients || usedInPantry
  }

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
      reload()
    } catch (err: any) {
      setError(err.message)
    }
  }

  const handleDelete = (id: string, name: string) => {
    const hasRefs = checkReferences(id, name)
    const msg = hasRefs 
      ? `La categoría "${name}" está en uso. Se realizará una baja lógica y no estará disponible para nuevos registros.`
      : `¿Eliminar la categoría "${name}" permanentemente?`
    if (window.confirm(msg)) {
      deleteCategory(id, hasRefs)
      reload()
    }
  }

  return (
    <div className="panel">
      <div className="section-header">
        <h2>Administrar Categorías</h2>
        <button className="button" onClick={() => { setEditor({ name: '' }); setError('') }}>
          <Plus size={16} /> Nueva categoría
        </button>
      </div>

      <div className="records">
        {categories.map((c) => (
          <article className="record" key={c.id}>
            <div className="record-main">
              <strong>{c.name}</strong>
              {c.isDeleted && <small className="error">Inactiva (Baja lógica)</small>}
            </div>
            <div className="record-actions">
              {!c.isDeleted && (
                <>
                  <button className="pantry-icon-button" onClick={() => setEditor({ id: c.id, name: c.name })}>
                    <Pencil size={17} />
                  </button>
                  <button className="pantry-icon-button" onClick={() => handleDelete(c.id, c.name)}>
                    <Trash2 size={17} />
                  </button>
                </>
              )}
            </div>
          </article>
        ))}
        {categories.length === 0 && <p className="empty">No hay categorías administradas.</p>}
      </div>

      {editor && (
        <dialog open className="shopping-editor surface">
          <div className="shopping-editor-heading">
            <h2>{editor.id ? 'Editar categoría' : 'Nueva categoría'}</h2>
            <button className="pantry-icon-button" onClick={() => setEditor(null)}><X size={19} /></button>
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
