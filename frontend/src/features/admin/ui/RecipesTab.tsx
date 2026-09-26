import { useState, type FormEvent } from 'react'
import { ArrowDown, ArrowUp, Pencil, Plus, Trash2, X } from 'lucide-react'
import { getAdminData } from '../data/localAdminStore'
import { hasAdminReferences } from '../data/adminReferences'
import { createRecipe, deleteRecipe, updateRecipe } from '../data/recipesStore'
import type { AdminRecipe } from '../domain/adminModels'

const emptyRecipe = (): Partial<AdminRecipe> => ({
  title: '', author: 'CocinAPP', description: '', category: 'Almuerzo', minutes: 30,
  portions: 2, difficulty: 'Fácil', calories: 0, mealShift: 'Almuerzo', dietaryTags: [],
  ingredients: [], steps: [''], stepMeta: [{}], status: 'draft', symbol: 'R', color: 'green',
})

export function RecipesTab() {
  const [recipes, setRecipes] = useState(() => getAdminData().recipes)
  const [editor, setEditor] = useState<Partial<AdminRecipe> | null>(null)
  const [error, setError] = useState('')
  const [search, setSearch] = useState('')
  const data = getAdminData()
  const availableIngredients = data.ingredients.filter((ingredient) => !ingredient.isDeleted)
  const availableUnits = data.units.filter((unit) => !unit.isDeleted)
  const reload = () => setRecipes(getAdminData().recipes)

  function submit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault()
    if (!editor) return
    try {
      const payload: Omit<AdminRecipe, 'id' | 'isDeleted'> = {
        title: editor.title ?? '', author: editor.author?.trim() || 'CocinAPP',
        description: editor.description?.trim() ?? '', category: editor.mealShift ?? 'Almuerzo',
        minutes: editor.minutes ?? 0, portions: editor.portions ?? 0,
        difficulty: editor.difficulty ?? 'Fácil', calories: editor.calories ?? 0,
        mealShift: editor.mealShift ?? '', dietaryTags: editor.dietaryTags ?? [],
        ingredients: editor.ingredients ?? [], steps: editor.steps ?? [], stepMeta: editor.stepMeta ?? [],
        status: editor.status ?? 'draft', symbol: editor.title?.trim().slice(0, 1).toLocaleUpperCase('es') || 'R',
        color: editor.color ?? 'green',
      }
      if (editor.id) updateRecipe(editor.id, payload)
      else createRecipe(payload)
      setEditor(null)
      setError('')
      reload()
    } catch (cause) {
      setError(cause instanceof Error ? cause.message : 'No se pudo guardar la receta.')
    }
  }

  function remove(recipe: AdminRecipe) {
    const referenced = hasAdminReferences('recipe', recipe.id)
    const message = referenced
      ? `La receta “${recipe.title}” tiene favoritos, planes o historial. Se marcará como inactiva y esos datos se conservarán.`
      : `¿Eliminar “${recipe.title}” permanentemente?`
    if (window.confirm(message)) {
      deleteRecipe(recipe.id)
      reload()
    }
  }

  function moveItem<T>(items: T[], index: number, offset: -1 | 1): T[] {
    const target = index + offset
    if (target < 0 || target >= items.length) return items
    const next = [...items]
    ;[next[index], next[target]] = [next[target], next[index]]
    return next
  }

  function updateIngredient(index: number, changes: Partial<AdminRecipe['ingredients'][number]>) {
    if (!editor) return
    const ingredients = [...(editor.ingredients ?? [])]
    ingredients[index] = { ...ingredients[index], ...changes }
    setEditor({ ...editor, ingredients })
  }

  function updateStepMeta(index: number, changes: NonNullable<AdminRecipe['stepMeta']>[number]) {
    if (!editor) return
    const stepMeta = (editor.steps ?? []).map((_, stepIndex) => ({ ...editor.stepMeta?.[stepIndex] }))
    stepMeta[index] = { ...stepMeta[index], ...changes }
    setEditor({ ...editor, stepMeta })
  }

  function moveRecipeStep(index: number, offset: -1 | 1) {
    if (!editor) return
    const stepMeta = (editor.steps ?? []).map((_, stepIndex) => editor.stepMeta?.[stepIndex] ?? {})
    setEditor({ ...editor, steps: moveItem(editor.steps ?? [], index, offset), stepMeta: moveItem(stepMeta, index, offset) })
  }

  function removeRecipeStep(index: number) {
    if (!editor) return
    setEditor({ ...editor, steps: (editor.steps ?? []).filter((_, stepIndex) => stepIndex !== index), stepMeta: (editor.steps ?? []).map((_, stepIndex) => editor.stepMeta?.[stepIndex] ?? {}).filter((_, stepIndex) => stepIndex !== index) })
  }

  const visibleRecipes = recipes.filter((recipe) => recipe.title.toLocaleLowerCase('es').includes(search.trim().toLocaleLowerCase('es')))

  return <div className="panel">
    <div className="section-header"><h2>Recetas oficiales</h2><button className="button button-primary" onClick={() => { setEditor(emptyRecipe()); setError('') }} type="button"><Plus size={16} /> Nueva receta</button></div>
    <label className="field admin-search"><span>Buscar receta</span><input onChange={(event) => setSearch(event.currentTarget.value)} type="search" value={search} /></label>
    <div className="records">
      {visibleRecipes.map((recipe) => <article className="record" key={recipe.id}>
        <div className="record-main"><strong>{recipe.title}</strong><small>{recipe.mealShift || recipe.category} · {recipe.status === 'published' ? 'Publicada' : 'Borrador'}</small>{recipe.isDeleted && <small className="error">Inactiva</small>}</div>
        <div className="record-actions">{!recipe.isDeleted && <><button aria-label={`Editar receta ${recipe.title}`} className="pantry-icon-button" onClick={() => { setEditor({ ...recipe, dietaryTags: [...recipe.dietaryTags], ingredients: recipe.ingredients.map((item) => ({ ...item })), steps: [...recipe.steps], stepMeta: recipe.stepMeta?.map((item) => ({ ...item })) ?? [] }); setError('') }} type="button"><Pencil size={17} /></button><button aria-label={`Eliminar receta ${recipe.title}`} className="pantry-icon-button" onClick={() => remove(recipe)} type="button"><Trash2 size={17} /></button></>}</div>
      </article>)}
      {visibleRecipes.length === 0 && <p className="empty">No hay recetas que coincidan con la búsqueda.</p>}
    </div>

    {editor && <dialog aria-labelledby="admin-recipe-title" className="shopping-editor surface admin-recipe-dialog" onCancel={(event) => { event.preventDefault(); setEditor(null) }} ref={(node) => { if (node && !node.open) node.showModal() }}>
      <div className="shopping-editor-heading"><h2 id="admin-recipe-title">{editor.id ? 'Editar receta' : 'Nueva receta oficial'}</h2><button aria-label="Cerrar formulario" className="pantry-icon-button" onClick={() => setEditor(null)} type="button"><X size={19} /></button></div>
      <form onSubmit={submit}>
        <div className="shopping-form-grid">
          <label className="field"><span>Título</span><input autoFocus maxLength={90} onChange={(event) => setEditor({ ...editor, title: event.currentTarget.value })} required value={editor.title ?? ''} /></label>
          <label className="field"><span>Porciones</span><input min="1" onChange={(event) => setEditor({ ...editor, portions: event.currentTarget.valueAsNumber })} required type="number" value={editor.portions ?? ''} /></label>
          <label className="field"><span>Tiempo de preparación (minutos)</span><input min="1" onChange={(event) => setEditor({ ...editor, minutes: event.currentTarget.valueAsNumber })} required type="number" value={editor.minutes ?? ''} /></label>
          <label className="field"><span>Dificultad</span><select onChange={(event) => setEditor({ ...editor, difficulty: event.currentTarget.value as AdminRecipe['difficulty'] })} value={editor.difficulty ?? 'Fácil'}><option>Fácil</option><option>Intermedia</option><option>Avanzada</option></select></label>
          <label className="field"><span>Calorías de referencia por porción</span><input min="0" step="any" onChange={(event) => setEditor({ ...editor, calories: event.currentTarget.valueAsNumber })} required type="number" value={editor.calories ?? ''} /></label>
          <label className="field"><span>Turno de comida</span><select onChange={(event) => setEditor({ ...editor, mealShift: event.currentTarget.value, category: event.currentTarget.value })} value={editor.mealShift ?? 'Almuerzo'}><option>Desayuno</option><option>Almuerzo</option><option>Merienda</option><option>Cena</option></select></label>
        </div>
        <label className="field"><span>Descripción</span><textarea maxLength={280} onChange={(event) => setEditor({ ...editor, description: event.currentTarget.value })} value={editor.description ?? ''} /></label>
        <label className="field"><span>Etiquetas dietéticas (separadas por coma)</span><input onChange={(event) => setEditor({ ...editor, dietaryTags: event.currentTarget.value.split(',').map((tag) => tag.trim()).filter(Boolean) })} placeholder="Vegana, Sin TACC, Vegetariana" value={(editor.dietaryTags ?? []).join(', ')} /></label>
        <label className="field"><span>Disponibilidad en el catálogo</span><select onChange={(event) => setEditor({ ...editor, status: event.currentTarget.value as AdminRecipe['status'] })} value={editor.status ?? 'draft'}><option value="draft">Borrador: no visible para usuarios</option><option value="published">Publicada</option></select></label>

        <section className="admin-recipe-section" aria-labelledby="admin-ingredients-title"><div className="section-header"><h3 id="admin-ingredients-title">Ingredientes</h3><button className="button button-quiet" onClick={() => setEditor({ ...editor, ingredients: [...(editor.ingredients ?? []), { ingredientId: '', quantity: 1, unitId: '' }] })} type="button"><Plus size={15} /> Agregar ingrediente</button></div>
          {(editor.ingredients ?? []).map((entry, index) => {
            const ingredient = availableIngredients.find((item) => item.id === entry.ingredientId)
            const baseUnit = availableUnits.find((unit) => unit.id === ingredient?.baseUnitId)
            const compatibleUnits = baseUnit ? availableUnits.filter((unit) => unit.dimension === baseUnit.dimension) : []
            return <div className="admin-recipe-row" key={`${index}-${entry.ingredientId}`}>
              <label className="field"><span>Ingrediente {index + 1}</span><select onChange={(event) => { const selected = availableIngredients.find((item) => item.id === event.currentTarget.value); updateIngredient(index, { ingredientId: event.currentTarget.value, unitId: selected?.baseUnitId ?? '' }) }} required value={entry.ingredientId}><option value="">Seleccioná ingrediente</option>{availableIngredients.map((item) => <option key={item.id} value={item.id}>{item.name}</option>)}</select></label>
              <label className="field"><span>Cantidad</span><input min="0.000001" onChange={(event) => updateIngredient(index, { quantity: event.currentTarget.valueAsNumber })} required step="any" type="number" value={entry.quantity ?? ''} /></label>
              <label className="field"><span>Unidad</span><select onChange={(event) => updateIngredient(index, { unitId: event.currentTarget.value })} required value={entry.unitId}><option value="">Unidad compatible</option>{compatibleUnits.map((unit) => <option key={unit.id} value={unit.id}>{unit.name} ({unit.abbreviation})</option>)}</select></label>
              <div className="admin-recipe-row-actions"><button aria-label={`Mover ingrediente ${index + 1} arriba`} className="pantry-icon-button" disabled={index === 0} onClick={() => setEditor({ ...editor, ingredients: moveItem(editor.ingredients ?? [], index, -1) })} type="button"><ArrowUp size={17} /></button><button aria-label={`Mover ingrediente ${index + 1} abajo`} className="pantry-icon-button" disabled={index === (editor.ingredients?.length ?? 0) - 1} onClick={() => setEditor({ ...editor, ingredients: moveItem(editor.ingredients ?? [], index, 1) })} type="button"><ArrowDown size={17} /></button><button aria-label={`Quitar ingrediente ${index + 1}`} className="pantry-icon-button" onClick={() => setEditor({ ...editor, ingredients: (editor.ingredients ?? []).filter((_, itemIndex) => itemIndex !== index) })} type="button"><X size={17} /></button></div>
            </div>
          })}
          {availableIngredients.length === 0 && <p className="field-help">Primero creá ingredientes activos con categoría y unidad base.</p>}
        </section>

        <section className="admin-recipe-section" aria-labelledby="admin-steps-title"><div className="section-header"><h3 id="admin-steps-title">Instrucciones ordenadas</h3><button className="button button-quiet" onClick={() => setEditor({ ...editor, steps: [...(editor.steps ?? []), ''], stepMeta: [...(editor.steps ?? []).map((_, index) => editor.stepMeta?.[index] ?? {}), {}] })} type="button"><Plus size={15} /> Agregar paso</button></div>
          {(editor.steps ?? []).map((step, index) => <div className="admin-step-editor" key={index}>
            <div className="admin-step-row"><label className="field"><span>Paso {index + 1}</span><textarea onChange={(event) => { const steps = [...(editor.steps ?? [])]; steps[index] = event.currentTarget.value; setEditor({ ...editor, steps }) }} required value={step} /></label><div className="admin-recipe-row-actions"><button aria-label={`Mover paso ${index + 1} arriba`} className="pantry-icon-button" disabled={index === 0} onClick={() => moveRecipeStep(index, -1)} type="button"><ArrowUp size={17} /></button><button aria-label={`Mover paso ${index + 1} abajo`} className="pantry-icon-button" disabled={index === (editor.steps?.length ?? 0) - 1} onClick={() => moveRecipeStep(index, 1)} type="button"><ArrowDown size={17} /></button><button aria-label={`Quitar paso ${index + 1}`} className="pantry-icon-button" onClick={() => removeRecipeStep(index)} type="button"><X size={17} /></button></div></div>
            <div className="shopping-form-grid"><label className="field"><span>Temporizador del paso {index + 1} (minutos, opcional)</span><input min="1" max="240" onChange={(event) => updateStepMeta(index, { minutes: event.currentTarget.value ? event.currentTarget.valueAsNumber : undefined })} type="number" value={editor.stepMeta?.[index]?.minutes ?? ''} /></label><label className="field"><span>Consejo del paso {index + 1} (opcional)</span><input maxLength={240} onChange={(event) => updateStepMeta(index, { tip: event.currentTarget.value })} value={editor.stepMeta?.[index]?.tip ?? ''} /></label></div>
          </div>)}
        </section>

        {error && <p className="form-message error" role="alert">{error}</p>}
        <div className="pantry-dialog-actions"><button className="button button-quiet" onClick={() => setEditor(null)} type="button">Cancelar</button><button className="button button-primary" type="submit">Guardar receta</button></div>
      </form>
    </dialog>}
  </div>
}
