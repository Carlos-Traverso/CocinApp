import { LoadingScreen } from '../../../components/LoadingScreen'
import { useState, type FormEvent } from 'react'
import { ArrowDown, ArrowUp, Copy, Eye, Pencil, Plus, Power, Star, Trash2, X } from 'lucide-react'
import { adminRepository } from '../data/AdminRepository'
import type { AdminRecipe } from '../domain/adminModels'
import { RecipeImage } from '../../recipes/ui/RecipeImage'
import { filterAdminRecipes, getManagedRecipes, type AdminRecipeFilters, type ManagedAdminRecipe } from '../domain/adminRecipeList'
import { SearchFeedback } from '../../../shared/search/SearchFeedback'
import { useDebouncedSearch } from '../../../shared/search/useDebouncedSearch'
import { useAdminCatalog } from './useAdminCatalog'
import { useNotifications } from '../../../shared/notifications/NotificationProvider'

const pageSize = 8

const recipeSymbols = ['🍲', '🥗', '🍝', '🍳', '🥞', '🥣', '🍗', '🥑'] as const
const recipeColors = [
  { value: 'green', label: 'Verde' },
  { value: 'gold', label: 'Dorado' },
  { value: 'pink', label: 'Rosa' },
  { value: 'blue', label: 'Azul' },
] as const satisfies readonly { value: AdminRecipe['color']; label: string }[]

const emptyRecipe = (): Partial<AdminRecipe> => ({
  title: '', author: 'CocinAPP', description: '', minutes: 30,
  portions: 2, calories: 0, dietaryTags: [],
  ingredients: [], steps: [''], stepMeta: [{}], featured: false,
  image: '', imageAlt: '',
})

export function RecipesTab() {
  const { notify } = useNotifications()
  const { data: snapshot, knownRecipes, loading, error, setError, reload } = useAdminCatalog()
  const data = snapshot ?? { categories: [], units: [], ingredients: [], recipes: [] }
  const [pending, setPending] = useState(false)
  const [editor, setEditor] = useState<Partial<AdminRecipe> | null>(null)
  const [search, setSearch] = useState('')
  const [category, setCategory] = useState('')
  const [status, setStatus] = useState<AdminRecipeFilters['status']>('all')
  const [difficulty, setDifficulty] = useState<AdminRecipeFilters['difficulty']>('all')
  const [maxMinutes, setMaxMinutes] = useState(0)
  const [featured, setFeatured] = useState<AdminRecipeFilters['featured']>('all')
  const [sort, setSort] = useState<AdminRecipeFilters['sort']>('title-asc')
  const [page, setPage] = useState(1)
  const [preview, setPreview] = useState<ManagedAdminRecipe | null>(null)
  const [editorBaseline, setEditorBaseline] = useState('')
  const debouncedSearch = useDebouncedSearch(search)
  const referencedIngredientIds = new Set(editor?.ingredients?.map((ingredient) => ingredient.ingredientId) ?? [])
  const availableIngredients = data.ingredients.filter((ingredient) => ingredient.active && !ingredient.isDeleted || referencedIngredientIds.has(ingredient.id))

  function cloneRecipe(recipe: AdminRecipe): Partial<AdminRecipe> {
    return { ...recipe, mealShifts: recipe.mealShifts ? [...recipe.mealShifts] : [recipe.mealShift], dietaryTags: [...recipe.dietaryTags], ingredients: recipe.ingredients.map((item) => ({ ...item })), steps: [...recipe.steps], stepMeta: recipe.stepMeta?.map((item) => ({ ...item, ingredientIds: item.ingredientIds ? [...item.ingredientIds] : undefined, utensils: item.utensils ? [...item.utensils] : undefined })) ?? [] }
  }

  async function openEditor(recipe?: ManagedAdminRecipe) {
    setPending(true)
    setError('')
    try {
      const record = recipe?.record ?? (recipe ? await adminRepository.createSeedRecipeOverride(recipe.recipe) : undefined)
      const next = recipe ? cloneRecipe(record!) : emptyRecipe()
      setEditor(next)
      setEditorBaseline(JSON.stringify(next))
    } catch (cause) {
      void notify({ type: 'error', title: 'No se pudo abrir la receta', message: cause instanceof Error ? cause.message : 'No se pudo abrir la receta.' })
    } finally {
      setPending(false)
    }
  }

  async function requestCloseEditor() {
    if (editor && JSON.stringify(editor) !== editorBaseline && !await notify({ type: 'warning', title: 'Descartar cambios', message: 'Hay cambios sin guardar. ¿Querés descartarlos?', confirmLabel: 'Descartar cambios', cancelLabel: 'Seguir editando' })) return
    setEditor(null)
    setError('')
  }

  async function submit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault()
    if (!editor) return
    const invalidField = event.currentTarget.querySelector<HTMLElement>(':invalid')
    if (invalidField) {
      setError('Revisá los campos obligatorios y sus valores antes de guardar la receta.')
      invalidField.focus()
      return
    }
    if (!editor.mealShifts?.length) {
      setError('Elegí al menos un turno de comida para la receta.')
      event.currentTarget.querySelector<HTMLElement>('.admin-meal-shifts')?.focus()
      return
    }
    if (!editor.difficulty || !editor.status || editor.active === undefined || !editor.color) {
      setError('Elegí una dificultad, disponibilidad, estado y color antes de guardar la receta.')
      return
    }
    const mealShifts = editor.mealShifts
    try {
      setPending(true)
      setError('')
      const payload: Omit<AdminRecipe, 'id' | 'isDeleted'> = {
        title: editor.title ?? '', author: editor.author?.trim() || 'CocinAPP',
        description: editor.description?.trim() ?? '', category: mealShifts[0],
        minutes: editor.minutes ?? 0, portions: editor.portions ?? 0,
        difficulty: editor.difficulty, calories: editor.calories ?? 0,
        mealShift: mealShifts[0], mealShifts, dietaryTags: editor.dietaryTags ?? [], featured: editor.featured ?? false,
        ingredients: editor.ingredients ?? [], steps: editor.steps ?? [], stepMeta: editor.stepMeta ?? [],
        status: editor.status, active: editor.active, symbol: editor.symbol?.trim() || editor.title?.trim().slice(0, 1).toLocaleUpperCase('es') || 'R',
        color: editor.color, image: editor.image?.trim() || undefined, imageAlt: editor.imageAlt?.trim() || undefined,
        preparationMinutes: editor.preparationMinutes, cookingMinutes: editor.cookingMinutes,
      }
      if (editor.id) await adminRepository.updateRecipe(editor.id, payload)
      else await adminRepository.createRecipe(payload)
      setEditor(null)
      setError('')
      void notify({ type: 'success', title: editor.id ? 'Receta actualizada' : 'Receta creada', message: editor.id ? 'La receta se actualizó correctamente.' : 'La receta se creó como parte del catálogo oficial.' })
      await reload()
    } catch (cause) {
      setError(cause instanceof Error ? cause.message : 'No se pudo guardar la receta.')
    } finally {
      setPending(false)
    }
  }

  async function remove(recipe: AdminRecipe) {
    if (!await notify({ type: 'warning', title: 'Eliminar receta', message: `¿Eliminar “${recipe.title}”? Si tiene referencias o forma parte del catálogo precargado, se conservará inactiva.`, confirmLabel: 'Eliminar', cancelLabel: 'Cancelar' })) return
    setPending(true)
    setError('')
    try {
      const result = await adminRepository.deleteRecipe(recipe.id)
      if (result === 'not-found') {
        void notify({ type: 'error', title: 'Receta no encontrada', message: 'No se aplicaron cambios. Actualizá el catálogo e intentá nuevamente.' })
        return
      }
      try {
        await reload()
      } catch {
        void notify({ type: 'error', title: 'No se pudo actualizar el catálogo', message: 'La acción sobre la receta se completó, pero la lista no pudo actualizarse. Recargá el catálogo para ver el estado actual.' })
      }
    } catch (cause) {
      void notify({ type: 'error', title: 'No se pudo eliminar la receta', message: cause instanceof Error ? cause.message : 'Ocurrió un error al eliminar la receta.' })
    } finally {
      setPending(false)
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

  const managedRecipes = getManagedRecipes(data, knownRecipes)
  const filteredRecipes = debouncedSearch.status === 'waiting' ? [] : filterAdminRecipes(managedRecipes, { search: debouncedSearch.query, category, status, difficulty, maxMinutes, featured, sort })
  const recipeCategories = [...new Set(managedRecipes.flatMap((recipe) => recipe.mealShifts ?? [recipe.category]))].sort((first, second) => first.localeCompare(second, 'es'))
  const pageCount = Math.max(1, Math.ceil(filteredRecipes.length / pageSize))
  const currentPage = Math.min(page, pageCount)
  const visibleRecipes = filteredRecipes.slice((currentPage - 1) * pageSize, currentPage * pageSize)

  async function quickAction(action: () => Promise<unknown>, message: string) {
    setPending(true); setError('')
    try { await action(); await reload(); void notify({ type: 'success', title: 'Cambios guardados', message }) }
    catch (cause) { void notify({ type: 'error', title: 'No se pudo guardar el cambio', message: cause instanceof Error ? cause.message : 'No se pudo guardar el cambio.' }) }
    finally { setPending(false) }
  }

  return <div className="panel">
    <div className="section-header"><div><h2>Recetas oficiales</h2><p className="panel-intro"><SearchFeedback resultCount={filteredRecipes.length} status={debouncedSearch.status} /> · {managedRecipes.length} recetas totales</p></div><button className="button button-primary" disabled={loading || pending} onClick={() => void openEditor()} type="button"><Plus size={16} /> Nueva receta</button></div>
    <div className="admin-filter-bar">
      <label className="field admin-filter-search"><span>Buscar</span><input onChange={(event) => { setSearch(event.currentTarget.value); setPage(1) }} placeholder="Título o categoría" type="search" value={search} /></label>
      <label className="field"><span>Categoría</span><select onChange={(event) => { setCategory(event.currentTarget.value); setPage(1) }} value={category}><option value="">Todas</option>{recipeCategories.map((item) => <option key={item}>{item}</option>)}</select></label>
      <label className="field"><span>Estado</span><select onChange={(event) => { setStatus(event.currentTarget.value as AdminRecipeFilters['status']); setPage(1) }} value={status}><option value="all">Todos</option><option value="active">Activas</option><option value="draft">Borradores</option><option value="inactive">Inactivas</option></select></label>
      <label className="field"><span>Dificultad</span><select onChange={(event) => { setDifficulty(event.currentTarget.value as AdminRecipeFilters['difficulty']); setPage(1) }} value={difficulty}><option value="all">Todas</option><option>Fácil</option><option>Intermedia</option><option>Avanzada</option></select></label>
      <label className="field"><span>Tiempo máximo</span><select onChange={(event) => { setMaxMinutes(Number(event.currentTarget.value)); setPage(1) }} value={maxMinutes}><option value="0">Cualquier tiempo</option><option value="30">Hasta 30 min</option><option value="60">Hasta 60 min</option><option value="90">Hasta 90 min</option></select></label>
      <label className="field"><span>Visibilidad</span><select onChange={(event) => { setFeatured(event.currentTarget.value as AdminRecipeFilters['featured']); setPage(1) }} value={featured}><option value="all">Todas</option><option value="featured">Solo destacadas</option></select></label>
      <label className="field"><span>Ordenar</span><select onChange={(event) => setSort(event.currentTarget.value as AdminRecipeFilters['sort'])} value={sort}><option value="title-asc">Título A–Z</option><option value="title-desc">Título Z–A</option><option value="newest">Más recientes</option><option value="oldest">Más antiguas</option></select></label>
    </div>
    {loading ? <LoadingScreen message="Cargando catálogo…" variant="section" /> : <div className="records">
      {visibleRecipes.map((recipe) => <article className="record admin-recipe-record" key={recipe.id}>
        <RecipeImage className="admin-recipe-record-art" recipe={recipe.recipe} />
        <div className="record-main"><span className="admin-record-title"><strong>{recipe.title}</strong>{recipe.featured && <Star aria-label="Destacada" fill="currentColor" size={14} />}</span><small>{(recipe.mealShifts ?? [recipe.category]).join(', ')} · {recipe.minutes} min · {recipe.difficulty}</small><span className={`admin-recipe-status ${recipe.status}`}>{recipe.status === 'published' ? recipe.source === 'initial' ? 'Inicial · Publicada' : 'Publicada' : recipe.status === 'draft' ? 'Borrador' : 'Inactiva'}</span><small>{recipe.modifiedAt ? `Modificada ${new Date(recipe.modifiedAt).toLocaleDateString('es-AR')}` : 'Receta inicial versionada'}</small></div>
        <div className="record-actions admin-record-actions"><button aria-label={`Ver receta ${recipe.title}`} className="pantry-icon-button" disabled={pending} onClick={() => setPreview(recipe)} title="Ver" type="button"><Eye size={17} /></button><button aria-label={`Editar receta ${recipe.title}`} className="pantry-icon-button" disabled={pending} onClick={() => void openEditor(recipe)} title="Editar" type="button"><Pencil size={17} /></button><button aria-label={`Duplicar receta ${recipe.title}`} className="pantry-icon-button" disabled={pending} onClick={() => quickAction(() => adminRepository.duplicateRecipe(recipe.id), 'Se creó una copia en borrador.')} title="Duplicar" type="button"><Copy size={17} /></button><button aria-label={recipe.active ? `Desactivar receta ${recipe.title}` : `Activar receta ${recipe.title}`} className="pantry-icon-button" disabled={pending} onClick={() => quickAction(() => adminRepository.setRecipeActive(recipe.id, !recipe.active), recipe.active ? 'La receta quedó inactiva.' : 'La receta volvió a estar disponible.')} title={recipe.active ? 'Desactivar' : 'Activar'} type="button"><Power size={17} /></button><button aria-label={recipe.featured ? `Quitar ${recipe.title} de destacadas` : `Destacar receta ${recipe.title}`} className={`pantry-icon-button${recipe.featured ? ' active' : ''}`} disabled={pending} onClick={() => quickAction(() => adminRepository.setRecipeFeatured(recipe.id, !recipe.featured), recipe.featured ? 'La receta dejó de estar destacada.' : 'La receta ahora está destacada.')} title="Destacar" type="button"><Star size={17} /></button>{recipe.record && !recipe.record.isDeleted && <button aria-label={`Eliminar receta ${recipe.title}`} className="pantry-icon-button" disabled={pending} onClick={() => void remove(recipe.record!)} title="Eliminar" type="button"><Trash2 size={17} /></button>}</div>
      </article>)}
      {debouncedSearch.status !== 'waiting' && visibleRecipes.length === 0 && <p className="empty">No hay recetas que coincidan con los filtros elegidos.</p>}
    </div>}

    {pageCount > 1 && <nav aria-label="Paginación de recetas" className="admin-pagination"><button className="button button-quiet" disabled={currentPage === 1} onClick={() => setPage(currentPage - 1)} type="button">Anterior</button><span>Página {currentPage} de {pageCount}</span><button className="button button-quiet" disabled={currentPage === pageCount} onClick={() => setPage(currentPage + 1)} type="button">Siguiente</button></nav>}

    {preview && <dialog aria-labelledby="admin-preview-title" className="pantry-dialog surface admin-preview-dialog" onCancel={() => setPreview(null)} ref={(node) => { if (node && !node.open) node.showModal() }}><div className="pantry-dialog-header"><div><p className="eyebrow">VISTA PREVIA</p><h2 id="admin-preview-title">{preview.title}</h2></div><button aria-label="Cerrar vista previa" className="pantry-icon-button" onClick={() => setPreview(null)} type="button"><X size={19} /></button></div><RecipeImage className="admin-preview-image" recipe={preview.recipe} /><p>{preview.recipe.description}</p><dl className="admin-preview-facts"><div><dt>Tiempo</dt><dd>{preview.minutes} min</dd></div><div><dt>Porciones</dt><dd>{preview.recipe.portions}</dd></div><div><dt>Dificultad</dt><dd>{preview.difficulty}</dd></div><div><dt>Estado</dt><dd>{preview.status === 'published' ? 'Publicada' : preview.status === 'draft' ? 'Borrador' : 'Inactiva'}</dd></div></dl><div className="pantry-dialog-actions"><button className="button button-quiet" onClick={() => setPreview(null)} type="button">Cerrar</button><button className="button button-primary" onClick={() => { const selected = preview; setPreview(null); openEditor(selected) }} type="button">Editar receta</button></div></dialog>}

    {editor && <dialog aria-labelledby="admin-recipe-title" className="shopping-editor surface admin-recipe-dialog" onCancel={(event) => { event.preventDefault(); requestCloseEditor() }} ref={(node) => { if (node && !node.open) node.showModal() }}>
      <div className="shopping-editor-heading"><h2 id="admin-recipe-title">{editor.id ? 'Editar receta' : 'Nueva receta oficial'}</h2><button aria-label="Cerrar formulario" className="pantry-icon-button" onClick={requestCloseEditor} type="button"><X size={19} /></button></div>
      <form noValidate onSubmit={submit}>
        <div className="shopping-form-grid">
          <label className="field"><span>Título</span><input autoFocus maxLength={90} onChange={(event) => setEditor({ ...editor, title: event.currentTarget.value })} required value={editor.title ?? ''} /></label>
          <label className="field"><span>Porciones</span><input min="1" onChange={(event) => setEditor({ ...editor, portions: event.currentTarget.valueAsNumber })} required type="number" value={editor.portions ?? ''} /></label>
          <label className="field"><span>Tiempo total (minutos)</span><input min="1" onChange={(event) => setEditor({ ...editor, minutes: event.currentTarget.valueAsNumber })} required type="number" value={editor.minutes ?? ''} /></label>
          <label className="field"><span>Preparación (minutos)</span><input min="0" onChange={(event) => setEditor({ ...editor, preparationMinutes: event.currentTarget.value ? event.currentTarget.valueAsNumber : undefined })} type="number" value={editor.preparationMinutes ?? ''} /></label>
          <label className="field"><span>Cocción (minutos)</span><input min="0" onChange={(event) => setEditor({ ...editor, cookingMinutes: event.currentTarget.value ? event.currentTarget.valueAsNumber : undefined })} type="number" value={editor.cookingMinutes ?? ''} /></label>
          <label className="field"><span>Dificultad</span><select onChange={(event) => setEditor({ ...editor, difficulty: event.currentTarget.value ? event.currentTarget.value as AdminRecipe['difficulty'] : undefined })} required value={editor.difficulty ?? ''}><option value="">Seleccionar…</option><option>Fácil</option><option>Intermedia</option><option>Avanzada</option></select></label>
          <label className="field"><span>Calorías de referencia por porción</span><input min="0" step="any" onChange={(event) => setEditor({ ...editor, calories: event.currentTarget.valueAsNumber })} required type="number" value={editor.calories ?? ''} /></label>
          <fieldset className="admin-meal-shifts" tabIndex={-1}><legend>Turnos de comida</legend><p className="field-help">Elegí uno o más turnos donde se puede encontrar esta receta.</p><div>{(['Desayuno', 'Almuerzo', 'Merienda', 'Cena'] as const).map((shift) => <label key={shift}><input checked={(editor.mealShifts ?? (editor.mealShift ? [editor.mealShift] : [])).includes(shift)} onChange={(event) => { const current = editor.mealShifts ?? (editor.mealShift ? [editor.mealShift] : []); const next = event.currentTarget.checked ? [...current, shift] : current.filter((item) => item !== shift); setEditor({ ...editor, mealShifts: next, mealShift: next[0], category: next[0] }) }} type="checkbox" />{shift}</label>)}</div></fieldset>
        </div>
        <label className="field"><span>Descripción</span><textarea maxLength={280} onChange={(event) => setEditor({ ...editor, description: event.currentTarget.value })} value={editor.description ?? ''} /></label>
        <div className="shopping-form-grid"><label className="field"><span>Ruta local de la imagen</span><input onChange={(event) => setEditor({ ...editor, image: event.currentTarget.value })} placeholder="/assets/recipes/mi-receta.webp" value={editor.image ?? ''} /><small className="field-help">Guardá el archivo en public/assets/recipes. Se aceptan AVIF, WebP, PNG y JPEG.</small></label><label className="field"><span>Texto alternativo</span><input maxLength={180} onChange={(event) => setEditor({ ...editor, imageAlt: event.currentTarget.value })} placeholder="Plato terminado de…" value={editor.imageAlt ?? ''} /></label></div>
        <section aria-labelledby="admin-recipe-visual-title" className="admin-recipe-visual-section">
          <div className={`admin-recipe-preview ${editor.color ?? 'green'}`}><RecipeImage className="admin-recipe-preview-art" recipe={{ name: editor.title?.trim() || 'Nombre de la receta', image: editor.image, imageAlt: editor.imageAlt, symbol: editor.symbol?.trim() || editor.title?.trim().slice(0, 1).toLocaleUpperCase('es') || 'R', color: editor.color ?? 'green' }} /><div><small>Vista previa en el catálogo</small><strong>{editor.title?.trim() || 'Nombre de la receta'}</strong><em>{(editor.mealShifts ?? (editor.mealShift ? [editor.mealShift] : [])).join(', ') || 'Sin turno seleccionado'} · {editor.minutes ?? 0} min</em></div></div>
          <div className="admin-recipe-visual-controls"><h3 id="admin-recipe-visual-title">Identidad visual</h3><p className="field-help">La fotografía se usa en el catálogo. El símbolo y el color quedan como respaldo si el archivo no está disponible.</p>
            <div aria-label="Símbolos sugeridos" className="admin-symbol-picker">{recipeSymbols.map((symbol) => <button aria-label={`Usar ${symbol} como símbolo`} aria-pressed={editor.symbol === symbol} key={symbol} onClick={() => setEditor({ ...editor, symbol })} type="button">{symbol}</button>)}</div>
            <fieldset className="admin-color-picker"><legend>Color de la tarjeta</legend>{recipeColors.map((color, index) => <label key={color.value}><input checked={editor.color === color.value} name="recipe-color" onChange={() => setEditor({ ...editor, color: color.value })} required={index === 0} type="radio" /><span className={color.value} aria-hidden="true" />{color.label}</label>)}</fieldset>
          </div>
        </section>
        <label className="field"><span>Etiquetas dietéticas (separadas por coma)</span><input onChange={(event) => setEditor({ ...editor, dietaryTags: event.currentTarget.value.split(',').map((tag) => tag.trim()).filter(Boolean) })} placeholder="Vegana, Sin TACC, Vegetariana" value={(editor.dietaryTags ?? []).join(', ')} /></label>
        <label className="field"><span>Disponibilidad en el catálogo</span><select onChange={(event) => setEditor({ ...editor, status: event.currentTarget.value ? event.currentTarget.value as AdminRecipe['status'] : undefined })} required value={editor.status ?? ''}><option value="">Seleccionar…</option><option value="draft">Borrador: no visible para usuarios</option><option value="published">Publicada</option></select></label>
        <label className="field"><span>Estado</span><select onChange={(event) => setEditor({ ...editor, active: event.currentTarget.value ? event.currentTarget.value === 'active' : undefined })} required value={editor.active === undefined ? '' : editor.active ? 'active' : 'inactive'}><option value="">Seleccionar…</option><option value="active">Activo · disponible para usuarios si está publicada</option><option value="inactive">Inactivo · no disponible para nuevas acciones</option></select></label>
        <label className="recipe-pantry-toggle"><input checked={editor.featured ?? false} onChange={(event) => setEditor({ ...editor, featured: event.currentTarget.checked })} type="checkbox" /> Destacar en Explorar recetas</label>

        <section className="admin-recipe-section" aria-labelledby="admin-ingredients-title"><div className="section-header"><h3 id="admin-ingredients-title">Ingredientes</h3><button className="button button-quiet" onClick={() => setEditor({ ...editor, ingredients: [...(editor.ingredients ?? []), { ingredientId: '', quantity: 1, unitId: '' }] })} type="button"><Plus size={15} /> Agregar ingrediente</button></div>
          {(editor.ingredients ?? []).map((entry, index) => {
            const ingredient = availableIngredients.find((item) => item.id === entry.ingredientId)
            const baseUnit = data.units.find((unit) => unit.id === ingredient?.baseUnitId && !unit.isDeleted)
            const compatibleUnits = baseUnit ? data.units.filter((unit) => !unit.isDeleted && unit.dimension === baseUnit.dimension && (unit.active || unit.id === entry.unitId)) : []
            return <div className="admin-recipe-row" key={`${index}-${entry.ingredientId}`}>
              <label className="field"><span>Ingrediente {index + 1}</span><select onChange={(event) => updateIngredient(index, { ingredientId: event.currentTarget.value, unitId: '' })} required value={entry.ingredientId}><option value="">Seleccionar…</option>{availableIngredients.map((item) => <option key={item.id} value={item.id}>{item.name}{item.active ? '' : ' (Inactivo)'}</option>)}</select></label>
              <label className="field"><span>Cantidad</span><input min="0.000001" onChange={(event) => updateIngredient(index, { quantity: event.currentTarget.valueAsNumber })} required step="any" type="number" value={entry.quantity ?? ''} /></label>
              <label className="field"><span>Unidad</span><select onChange={(event) => updateIngredient(index, { unitId: event.currentTarget.value })} required value={entry.unitId}><option value="">Seleccionar…</option>{compatibleUnits.map((unit) => <option key={unit.id} value={unit.id}>{unit.name} ({unit.abbreviation})</option>)}</select></label>
              <div className="admin-recipe-row-actions"><button aria-label={`Mover ingrediente ${index + 1} arriba`} className="pantry-icon-button" disabled={index === 0} onClick={() => setEditor({ ...editor, ingredients: moveItem(editor.ingredients ?? [], index, -1) })} type="button"><ArrowUp size={17} /></button><button aria-label={`Mover ingrediente ${index + 1} abajo`} className="pantry-icon-button" disabled={index === (editor.ingredients?.length ?? 0) - 1} onClick={() => setEditor({ ...editor, ingredients: moveItem(editor.ingredients ?? [], index, 1) })} type="button"><ArrowDown size={17} /></button><button aria-label={`Quitar ingrediente ${index + 1}`} className="pantry-icon-button" onClick={() => setEditor({ ...editor, ingredients: (editor.ingredients ?? []).filter((_, itemIndex) => itemIndex !== index) })} type="button"><X size={17} /></button></div>
            </div>
          })}
          {availableIngredients.length === 0 && <p className="field-help">Primero creá ingredientes activos con categoría y unidad base.</p>}
        </section>

        <section className="admin-recipe-section" aria-labelledby="admin-steps-title"><div className="section-header"><h3 id="admin-steps-title">Instrucciones ordenadas</h3><button className="button button-quiet" onClick={() => setEditor({ ...editor, steps: [...(editor.steps ?? []), ''], stepMeta: [...(editor.steps ?? []).map((_, index) => editor.stepMeta?.[index] ?? {}), {}] })} type="button"><Plus size={15} /> Agregar paso</button></div>
          {(editor.steps ?? []).map((step, index) => <div className="admin-step-editor" key={index}>
            <div className="admin-step-row"><label className="field"><span>Paso {index + 1}</span><textarea onChange={(event) => { const steps = [...(editor.steps ?? [])]; steps[index] = event.currentTarget.value; setEditor({ ...editor, steps }) }} required value={step} /></label><div className="admin-recipe-row-actions"><button aria-label={`Mover paso ${index + 1} arriba`} className="pantry-icon-button" disabled={index === 0} onClick={() => moveRecipeStep(index, -1)} type="button"><ArrowUp size={17} /></button><button aria-label={`Mover paso ${index + 1} abajo`} className="pantry-icon-button" disabled={index === (editor.steps?.length ?? 0) - 1} onClick={() => moveRecipeStep(index, 1)} type="button"><ArrowDown size={17} /></button><button aria-label={`Quitar paso ${index + 1}`} className="pantry-icon-button" onClick={() => removeRecipeStep(index)} type="button"><X size={17} /></button></div></div>
            <div className="shopping-form-grid">
              <label className="field"><span>Duración y temporizador (minutos)</span><input min="1" max="240" onChange={(event) => updateStepMeta(index, { durationMinutes: event.currentTarget.value ? event.currentTarget.valueAsNumber : undefined, minutes: undefined })} type="number" value={editor.stepMeta?.[index]?.durationMinutes ?? editor.stepMeta?.[index]?.minutes ?? ''} /></label>
              <label className="field"><span>Temperatura o tipo de cocción</span><input maxLength={80} onChange={(event) => updateStepMeta(index, { temperature: event.currentTarget.value })} placeholder="Ej.: 180 °C o fuego medio" value={editor.stepMeta?.[index]?.temperature ?? ''} /></label>
              <label className="field"><span>Ingredientes de este paso</span><select multiple onChange={(event) => updateStepMeta(index, { ingredientIds: Array.from(event.currentTarget.selectedOptions, (option) => option.value) })} value={editor.stepMeta?.[index]?.ingredientIds ?? []}>{(editor.ingredients ?? []).map((entry) => { const ingredient = availableIngredients.find((item) => item.id === entry.ingredientId); return ingredient ? <option key={entry.ingredientId} value={entry.ingredientId}>{ingredient.name} ({entry.quantity})</option> : null })}</select><small className="field-help">Podés seleccionar más de uno con Ctrl o Cmd.</small></label>
              <label className="field"><span>Utensilios (separados por coma)</span><input onChange={(event) => updateStepMeta(index, { utensils: event.currentTarget.value.split(',').map((item) => item.trim()).filter(Boolean) })} placeholder="Olla, cuchillo, tabla" value={(editor.stepMeta?.[index]?.utensils ?? []).join(', ')} /></label>
              <label className="field"><span>Consejo del paso</span><input maxLength={240} onChange={(event) => updateStepMeta(index, { tip: event.currentTarget.value })} value={editor.stepMeta?.[index]?.tip ?? ''} /></label>
              <label className="field"><span>Advertencia o error frecuente</span><input maxLength={240} onChange={(event) => updateStepMeta(index, { warning: event.currentTarget.value })} value={editor.stepMeta?.[index]?.warning ?? ''} /></label>
            </div>
            <label className="field"><span>Indicación especial del paso</span><textarea maxLength={400} onChange={(event) => updateStepMeta(index, { specialInstructions: event.currentTarget.value })} value={editor.stepMeta?.[index]?.specialInstructions ?? ''} /></label>
          </div>)}
        </section>

        {error && <p className="form-message error" role="alert">{error}</p>}
        <div className="pantry-dialog-actions"><button className="button button-quiet" onClick={requestCloseEditor} type="button">Cancelar</button><button className="button button-primary" disabled={pending} type="submit">{pending ? 'Guardando…' : 'Guardar receta'}</button></div>
      </form>
    </dialog>}
  </div>
}
