import { useState, type FormEvent } from 'react'
import { Heart, CalendarDays, Pencil, Plus, Refrigerator, Search, Trash2, X } from 'lucide-react'
import { Link } from 'react-router-dom'
import { readPantryItems } from '../features/pantry/data/localPantryStore'
import { formatPantryAmount, type PantryCategory, type PantryUnit } from '../features/pantry/domain/pantry'
import { getActiveCategories, getActiveUnits } from '../features/admin/data/localAdminStore'
import { readMealPlan } from '../features/planner/data/localMealPlanStore'
import { weekDates } from '../features/planner/domain/planner'
import { readFavoriteIds } from '../features/recipes/data/localFavoritesStore'
import { appendShoppingSuggestions, readShoppingItems, writeShoppingItems } from '../features/shopping/data/localShoppingStore'
import { filterShoppingItems, shoppingKey, suggestForRecipes, suggestPantryRestock, type ShoppingItem, type ShoppingStatusFilter, type ShoppingSuggestion } from '../features/shopping/domain/shopping'
import { getAvailableRecipes } from '../features/recipes/data/availableRecipes'

const sourceLabels = { manual: 'Manual', recipe: 'Receta', plan: 'Plan', favorites: 'Favoritos', pantry: 'Despensa' }

function emptyItem(): ShoppingItem {
  return { id: crypto.randomUUID(), name: '', category: 'Otros', quantity: 1, unit: 'u', note: '', checked: false, sources: ['manual'] }
}

export function ShoppingPage() {
  const catalogRecipes = getAvailableRecipes()
  const [items, setItems] = useState<ShoppingItem[]>(readShoppingItems)
  const [draft, setDraft] = useState<ShoppingItem | null>(null)
  const [search, setSearch] = useState('')
  const [category, setCategory] = useState<PantryCategory | ''>('')
  const [status, setStatus] = useState<ShoppingStatusFilter>('all')
  const [notice, setNotice] = useState('')
  const [error, setError] = useState('')

  const categories = [...new Set([...getActiveCategories(), ...items.map((item) => item.category)])]
  const visible = filterShoppingItems(items, { search, category, status })
    .sort((a, b) => categories.indexOf(a.category) - categories.indexOf(b.category) || a.name.localeCompare(b.name, 'es'))
  const groups = categories.map((name) => ({ name, items: visible.filter((item) => item.category === name) })).filter((group) => group.items.length > 0)
  const checkedCount = items.filter((item) => item.checked).length

  function persist(next: ShoppingItem[], message: string): boolean {
    try { writeShoppingItems(next); setItems(next); setNotice(message); setError(''); return true }
    catch { setError('No se pudieron guardar los cambios en este navegador.'); return false }
  }

  function importSuggestions(suggestions: ShoppingSuggestion[], label: string) {
    if (suggestions.length === 0) { setNotice(`No hay faltantes para ${label}.`); return }
    try {
      const next = appendShoppingSuggestions(suggestions)
      setItems(next)
      setNotice(`${suggestions.length} ${suggestions.length === 1 ? 'artículo sugerido' : 'artículos sugeridos'} desde ${label}.`)
      setError('')
    } catch { setError('No se pudo guardar la lista en este navegador.') }
  }

  function importFavorites() {
    const ids = readFavoriteIds()
    const selected = catalogRecipes.filter((recipe) => ids.includes(recipe.id))
    importSuggestions(suggestForRecipes(selected, readPantryItems(), 'favorites'), 'favoritos')
  }

  function importPlan() {
    const dates = new Set(weekDates())
    const recipes = readMealPlan().filter((entry) => dates.has(entry.date))
      .map((entry) => catalogRecipes.find((recipe) => recipe.id === entry.recipeId))
      .filter((recipe): recipe is (typeof catalogRecipes)[number] => Boolean(recipe))
    importSuggestions(suggestForRecipes(recipes, readPantryItems(), 'plan'), 'el plan de esta semana')
  }

  function saveDraft(event: FormEvent<HTMLFormElement>) {
    event.preventDefault()
    if (!draft) return
    const candidate = { ...draft, name: draft.name.trim().replace(/\s+/g, ' '), note: draft.note.trim() }
    if (!candidate.name || !Number.isFinite(candidate.quantity) || candidate.quantity <= 0 || candidate.quantity > 1_000_000) {
      setError('Ingresá un nombre y una cantidad mayor que cero.'); return
    }
    if (items.some((item) => item.id !== candidate.id && shoppingKey(item.name, item.unit) === shoppingKey(candidate.name, candidate.unit))) {
      setError('Ese artículo con la misma unidad ya está en la lista. Editalo para cambiar su cantidad.'); return
    }
    const editing = items.some((item) => item.id === candidate.id)
    const next = editing ? items.map((item) => item.id === candidate.id ? candidate : item) : [...items, candidate]
    if (persist(next, editing ? 'Artículo actualizado.' : 'Artículo añadido.')) setDraft(null)
  }

  function remove(item: ShoppingItem) {
    if (!window.confirm(`¿Eliminar ${item.name} de la lista?`)) return
    persist(items.filter((entry) => entry.id !== item.id), 'Artículo eliminado.')
  }

  return <div className="page shopping-page">
    <header className="page-heading"><div><p className="eyebrow">ORGANIZÁ TUS COMPRAS</p><h1>Lista de compras</h1><p className="page-lead">Agregá artículos o calculá lo que falta para cocinar.</p></div><button className="button button-primary" onClick={() => { setDraft(emptyItem()); setError('') }} type="button"><Plus size={17} /> Añadir artículo</button></header>

    <section aria-label="Añadir sugerencias" className="shopping-imports"><button className="button button-quiet" onClick={importPlan} type="button"><CalendarDays size={17} /> Desde el plan semanal</button><button className="button button-quiet" onClick={importFavorites} type="button"><Heart size={17} /> Desde favoritos</button><button className="button button-quiet" onClick={() => importSuggestions(suggestPantryRestock(readPantryItems()), 'la despensa')} type="button"><Refrigerator size={17} /> Reponer despensa</button></section>

    <section aria-label="Filtros de compras" className="shopping-controls"><label className="field"><span>Buscar artículo</span><span className="pantry-search-input"><Search aria-hidden="true" size={17} /><input onChange={(event) => setSearch(event.currentTarget.value)} placeholder="Ej.: arroz" type="search" value={search} /></span></label><label className="field"><span>Estado</span><select onChange={(event) => setStatus(event.currentTarget.value as ShoppingStatusFilter)} value={status}><option value="all">Todos</option><option value="pending">Pendientes</option><option value="checked">Comprados</option></select></label></section>
    <div aria-label="Filtrar por categoría" className="shopping-category-filters" role="group"><button aria-pressed={category === ''} className="shopping-category-chip" onClick={() => setCategory('')} type="button">Todas</button>{categories.map((option) => <button aria-pressed={category === option} className="shopping-category-chip" key={option} onClick={() => setCategory(option)} type="button">{option}</button>)}</div>
    <div className="pantry-results"><span aria-live="polite">{visible.length} visibles · {checkedCount} de {items.length} comprados</span><button onClick={() => { setSearch(''); setCategory(''); setStatus('all') }} type="button">Limpiar filtros</button></div>
    {notice && <p className="form-message pantry-notice" role="status">{notice}</p>}{error && <p className="form-message error" role="alert">{error}</p>}

    {visible.length === 0 ? <section className="pantry-empty"><h2>{items.length ? 'Sin resultados' : 'Tu lista está vacía'}</h2><p>{items.length ? 'Probá otros filtros.' : 'Añadí un artículo o generá sugerencias desde el plan, favoritos o despensa.'}</p></section> : <section aria-label="Artículos de compras" className="shopping-list">{groups.map((group) => <div className="shopping-group" key={group.name}><h2>{group.name}</h2>{group.items.map((item) => <article className={`shopping-row${item.checked ? ' checked' : ''}`} key={item.id}><label className="shopping-check"><input aria-label={`${item.checked ? 'Marcar pendiente' : 'Marcar comprado'}: ${item.name}`} checked={item.checked} onChange={(event) => persist(items.map((entry) => entry.id === item.id ? { ...entry, checked: event.currentTarget.checked } : entry), event.currentTarget.checked ? 'Marcado como comprado.' : 'Marcado como pendiente.')} type="checkbox" /></label><div className="shopping-copy"><strong>{item.name}</strong><span>{formatPantryAmount(item.quantity, item.unit)} · {item.sources.map((source) => sourceLabels[source]).join(', ')}</span>{item.note && <small>{item.note}</small>}</div><div className="shopping-actions"><button aria-label={`Editar ${item.name}`} className="pantry-icon-button" onClick={() => { setDraft({ ...item }); setError('') }} type="button"><Pencil size={17} /></button><button aria-label={`Eliminar ${item.name}`} className="pantry-icon-button" onClick={() => remove(item)} type="button"><Trash2 size={17} /></button></div></article>)}</div>)}</section>}

    <p className="pantry-footnote">La lista se guarda en este navegador. <Link className="text-link" to="/pantry">Ver despensa →</Link></p>
    {draft && <dialog aria-labelledby="shopping-editor-title" className="shopping-editor surface" onCancel={() => { setDraft(null); setError('') }} ref={(node) => { if (node && !node.open) { node.showModal(); node.querySelector<HTMLInputElement>('input')?.focus() } }}><div className="shopping-editor-heading"><h2 id="shopping-editor-title">{items.some((item) => item.id === draft.id) ? 'Editar artículo' : 'Añadir artículo'}</h2><button aria-label="Cerrar formulario" className="pantry-icon-button" onClick={() => { setDraft(null); setError('') }} type="button"><X size={19} /></button></div><form onSubmit={saveDraft}><label className="field"><span>Artículo</span><input maxLength={70} onChange={(event) => setDraft({ ...draft, name: event.currentTarget.value })} required value={draft.name} /></label><div className="shopping-form-grid"><label className="field"><span>Cantidad</span><input min="0.01" max="1000000" onChange={(event) => setDraft({ ...draft, quantity: event.currentTarget.valueAsNumber })} required step="any" type="number" value={Number.isNaN(draft.quantity) ? '' : draft.quantity} /></label><label className="field"><span>Unidad</span><select onChange={(event) => setDraft({ ...draft, unit: event.currentTarget.value as PantryUnit })} value={draft.unit}>{getActiveUnits().map((unit) => <option key={unit}>{unit}</option>)}</select></label></div><label className="field"><span>Categoría</span><select onChange={(event) => setDraft({ ...draft, category: event.currentTarget.value as PantryCategory })} value={draft.category}>{getActiveCategories().map((option) => <option key={option}>{option}</option>)}</select></label><label className="field"><span>Notas (opcional)</span><input maxLength={200} onChange={(event) => setDraft({ ...draft, note: event.currentTarget.value })} placeholder="Ej.: marca, tamaño" value={draft.note} /></label>{error && <p className="form-message error" role="alert">{error}</p>}<div className="pantry-dialog-actions"><button className="button button-quiet" onClick={() => { setDraft(null); setError('') }} type="button">Cancelar</button><button className="button button-primary" type="submit">Guardar artículo</button></div></form></dialog>}
  </div>
}

