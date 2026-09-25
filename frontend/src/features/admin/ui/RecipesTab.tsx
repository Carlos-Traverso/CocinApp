import { useState } from 'react'
import { Plus, Pencil, Trash2, X } from 'lucide-react'
import { getAdminData } from '../data/localAdminStore'
import { createRecipe, updateRecipe, deleteRecipe } from '../data/recipesStore'
import type { AdminRecipe } from '../domain/adminModels'

export function RecipesTab() {
  const data = getAdminData()
  const [recipes, setRecipes] = useState(data.recipes)
  const [editor, setEditor] = useState<Partial<AdminRecipe> | null>(null)
  const [error, setError] = useState('')

  const reload = () => setRecipes(getAdminData().recipes)

  const checkReferences = (id: string) => {
    // Read from planner, favorites, history (simplified)
    const favorites = localStorage.getItem('cocinapp.favorites.v1')
    const planner = localStorage.getItem('cocinapp.planner.v1')
    const history = localStorage.getItem('cocinapp.history.v1')
    return (favorites && favorites.includes(id)) || (planner && planner.includes(id)) || (history && history.includes(id))
  }

  const handleSave = (e: React.FormEvent) => {
    e.preventDefault()
    if (!editor) return
    try {
      if (!editor.title || !editor.author || !editor.description) {
        throw new Error('Debe completar título, autor y descripción.')
      }
      
      const payload: Omit<AdminRecipe, 'id' | 'isDeleted'> = {
        title: editor.title.trim(),
        author: editor.author.trim(),
        description: editor.description.trim(),
        category: editor.category || 'Almuerzo',
        minutes: editor.minutes || 30,
        portions: editor.portions || 2,
        difficulty: editor.difficulty || 'Fácil',
        calories: editor.calories || 0,
        mealShift: editor.mealShift || 'Almuerzo',
        dietaryTags: editor.dietaryTags || [],
        ingredients: editor.ingredients || [],
        steps: editor.steps || [],
        status: editor.status || 'published',
        symbol: editor.symbol || editor.title.charAt(0).toUpperCase(),
        color: editor.color || 'green',
      }

      if (editor.id) {
        updateRecipe(editor.id, payload)
      } else {
        createRecipe(payload)
      }
      setEditor(null)
      setError('')
      reload()
    } catch (err: any) {
      setError(err.message)
    }
  }

  const handleDelete = (id: string, name: string) => {
    const hasRefs = checkReferences(id)
    const msg = hasRefs 
      ? `La receta "${name}" tiene historial o planes. Se realizará una baja lógica.`
      : `¿Eliminar la receta "${name}" permanentemente?`
    if (window.confirm(msg)) {
      deleteRecipe(id, !!hasRefs)
      reload()
    }
  }

  return (
    <div className="panel">
      <div className="section-header">
        <h2>Administrar Recetas Oficiales</h2>
        <button className="button" onClick={() => { setEditor({}); setError('') }}>
          <Plus size={16} /> Nueva receta
        </button>
      </div>

      <div className="records">
        {recipes.map((r) => (
          <article className="record" key={r.id}>
            <div className="record-main">
              <strong>{r.title}</strong>
              <small>{r.author} | {r.category} | {r.status}</small>
              {r.isDeleted && <small className="error">Inactiva (Baja lógica)</small>}
            </div>
            <div className="record-actions">
              {!r.isDeleted && (
                <>
                  <button className="pantry-icon-button" onClick={() => setEditor({ ...r })}>
                    <Pencil size={17} />
                  </button>
                  <button className="pantry-icon-button" onClick={() => handleDelete(r.id, r.title)}>
                    <Trash2 size={17} />
                  </button>
                </>
              )}
            </div>
          </article>
        ))}
        {recipes.length === 0 && <p className="empty">No hay recetas administradas localmente.</p>}
      </div>

      {editor && (
        <dialog open className="shopping-editor surface" style={{ width: '90vw', maxWidth: '600px' }}>
          <div className="shopping-editor-heading">
            <h2>{editor.id ? 'Editar receta' : 'Nueva receta'}</h2>
            <button className="pantry-icon-button" onClick={() => setEditor(null)}><X size={19} /></button>
          </div>
          <form onSubmit={handleSave}>
            <div className="shopping-form-grid">
              <label className="field">
                <span>Título</span>
                <input required maxLength={90} value={editor.title || ''} onChange={(e) => setEditor({ ...editor, title: e.target.value })} />
              </label>
              <label className="field">
                <span>Autor</span>
                <input required maxLength={70} value={editor.author || ''} onChange={(e) => setEditor({ ...editor, author: e.target.value })} />
              </label>
            </div>
            <label className="field">
              <span>Descripción</span>
              <textarea required maxLength={280} value={editor.description || ''} onChange={(e) => setEditor({ ...editor, description: e.target.value })} />
            </label>
            
            <div className="shopping-form-grid">
              <label className="field">
                <span>Minutos</span>
                <input required type="number" min="1" value={editor.minutes || ''} onChange={(e) => setEditor({ ...editor, minutes: parseInt(e.target.value) })} />
              </label>
              <label className="field">
                <span>Porciones</span>
                <input required type="number" min="1" value={editor.portions || ''} onChange={(e) => setEditor({ ...editor, portions: parseInt(e.target.value) })} />
              </label>
              <label className="field">
                <span>Dificultad</span>
                <select value={editor.difficulty || 'Fácil'} onChange={(e) => setEditor({ ...editor, difficulty: e.target.value as any })}>
                  <option value="Fácil">Fácil</option>
                  <option value="Intermedia">Intermedia</option>
                  <option value="Avanzada">Avanzada</option>
                </select>
              </label>
            </div>

            {error && <p className="form-message error">{error}</p>}
            <div className="pantry-dialog-actions" style={{ marginTop: '20px' }}>
              <button className="button button-quiet" type="button" onClick={() => setEditor(null)}>Cancelar</button>
              <button className="button button-primary" type="submit">Guardar</button>
            </div>
          </form>
        </dialog>
      )}
    </div>
  )
}
