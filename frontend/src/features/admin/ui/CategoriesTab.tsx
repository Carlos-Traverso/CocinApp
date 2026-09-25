import { useState } from 'react'
import { Plus, Pencil, Trash2, X } from 'lucide-react'
import { getAdminData } from '../data/localAdminStore'
import { hasAdminReferences } from '../data/adminReferences'
import { createCategory, updateCategory, deleteCategory } from '../data/categoriesStore'

export function CategoriesTab() {
  const data = getAdminData()
  const [categories, setCategories] = useState(data.categories)
  const [editor, setEditor] = useState<{ id?: string; name: string } | null>(null)
  const [error, setError] = useState('')
  const [search, setSearch] = useState('')

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
      reload()
    } catch (err: any) {
      setError(err.message)
    }
  }

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
        <h2>Administrar Categorías</h2>
        <button className="button" onClick={() => { setEditor({ name: '' }); setError('') }}>
          <Plus size={16} /> Nueva categoría
        </button>
      </div>

      <label className="field admin-search"><span>Buscar categoría</span><input onChange={(event) => setSearch(event.currentTarget.value)} type="search" value={search} /></label>

      <div className="records">
        {categories.filter((category) => category.name.toLocaleLowerCase('es').includes(search.trim().toLocaleLowerCase('es'))).map((c) => (
          <article className="record" key={c.id}>
            <div className="record-main">
              <strong>{c.name}</strong>
              {c.isDeleted && <small className="error">Inactiva (Baja lógica)</small>}
            </div>
            <div className="record-actions">
              {!c.isDeleted && (
                <>
                  <button aria-label={`Editar categoría ${c.name}`} className="pantry-icon-button" onClick={() => setEditor({ id: c.id, name: c.name })} type="button">
                    <Pencil size={17} />
                  </button>
                  <button aria-label={`Eliminar categoría ${c.name}`} className="pantry-icon-button" onClick={() => handleDelete(c.id, c.name)} type="button">
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
        <dialog aria-labelledby="category-editor-title" className="shopping-editor surface" onCancel={(event) => { event.preventDefault(); setEditor(null) }} ref={(node) => { if (node && !node.open) node.showModal() }}>
          <div className="shopping-editor-heading">
            <h2 id="category-editor-title">{editor.id ? 'Editar categoría' : 'Nueva categoría'}</h2>
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
