import { useEffect, useRef, useState, type FormEvent } from 'react'
import { CheckCheck, Heart, CalendarDays, LoaderCircle, Pencil, Plus, Refrigerator, Search, Trash2, X, Share2, Copy, MessageCircle } from 'lucide-react'
import { Link } from 'react-router-dom'
import { formatPantryAmount, type PantryCategory, type PantryUnit } from '../features/pantry/domain/pantry'
import { weekDates } from '../features/planner/domain/planner'
import { mockShoppingRepository } from '../features/shopping/data/MockShoppingRepository'
import { createShoppingShareText, filterShoppingItems, isShoppingItemTransferable, shoppingKey, type ShoppingItem, type ShoppingStatusFilter, type ShoppingSuggestion } from '../features/shopping/domain/shopping'
import type { AdminStorageData } from '../features/admin/data/localAdminStore'
import { SearchFeedback } from '../shared/search/SearchFeedback'
import { useDebouncedSearch } from '../shared/search/useDebouncedSearch'
import { compatibleUnitAbbreviations } from '../shared/domain/units'
import { useNotifications } from '../shared/notifications/NotificationProvider'
import { IngredientPicker } from '../features/shopping/ui/IngredientPicker'
import './ShoppingPage.css'

const sourceLabels = { manual: 'Manual', recipe: 'Receta', plan: 'Plan', favorites: 'Favoritos', pantry: 'Despensa' }

function emptyItem(): ShoppingItem {
  return { id: crypto.randomUUID(), name: '', category: 'Otros', quantity: 1, unit: 'u', note: '', checked: false, transferredToPantry: false, transferredAt: null, sources: ['manual'], ingredientId: null }
}

export function ShoppingPage() {
  const { notify } = useNotifications()
  const [items, setItems] = useState<ShoppingItem[]>([])
  const [catalog, setCatalog] = useState<AdminStorageData>({ categories: [], units: [], ingredients: [], recipes: [] })
  const [loading, setLoading] = useState(true)
  const [draft, setDraft] = useState<ShoppingItem | null>(null)
  const [search, setSearch] = useState('')
  const [category, setCategory] = useState<PantryCategory | ''>('')
  const [status, setStatus] = useState<ShoppingStatusFilter>('all')
  const [error, setError] = useState('')
  const [working, setWorking] = useState('')
  const workingRef = useRef(false)
  const debouncedSearch = useDebouncedSearch(search)
  const validCatalogItems = catalog.ingredients.filter((entry) => entry.active && !entry.isDeleted)
  const activeUnits = catalog.units.filter((entry) => entry.active && !entry.isDeleted)
  const draftIngredient = draft?.ingredientId ? validCatalogItems.find((entry) => entry.id === draft.ingredientId) : undefined
  const draftBaseUnit = activeUnits.find((unit) => unit.id === draftIngredient?.baseUnitId)
  const allowedDraftUnits = draftIngredient && draftBaseUnit ? compatibleUnitAbbreviations(draftBaseUnit.abbreviation, activeUnits) : activeUnits.map((unit) => unit.abbreviation)
  useEffect(() => { let active = true; mockShoppingRepository.load().then((loaded) => { if (active) { setItems(loaded.items); setCatalog(loaded.catalog) } }).catch(() => { if (active) void notify({ type: 'error', title: 'No se pudo cargar la lista', message: 'Intentá volver a cargar la página.' }) }).finally(() => { if (active) setLoading(false) }); return () => { active = false } }, [notify])

  const categories = [...new Set([...catalog.categories.filter((entry) => entry.active && !entry.isDeleted).map((entry) => entry.name), ...items.map((item) => item.category)])]
  const visible = debouncedSearch.status === 'waiting' ? [] : filterShoppingItems(items, { search: debouncedSearch.query, category, status })
    .sort((a, b) => categories.indexOf(a.category) - categories.indexOf(b.category) || a.name.localeCompare(b.name, 'es'))
  const groups = categories.map((name) => ({ name, items: visible.filter((item) => item.category === name) })).filter((group) => group.items.length > 0)
  const checkedCount = items.filter((item) => item.checked).length
  const pendingCount = items.filter((item) => !item.checked && !item.transferredToPantry).length
  const transferableCount = items.filter((item) => isShoppingItemTransferable(item, catalog)).length
  const shareText = createShoppingShareText(items, catalog.units)

  async function runExclusive<T>(action: string, operation: () => Promise<T>): Promise<{ acquired: boolean; result?: T }> {
    if (workingRef.current) return { acquired: false }
    workingRef.current = true
    setWorking(action)
    try { return { acquired: true, result: await operation() } }
    finally { workingRef.current = false; setWorking('') }
  }

  async function persist(next: ShoppingItem[], message: string): Promise<boolean> {
    try {
      const saved = await runExclusive('save', async () => { await mockShoppingRepository.save(next); setItems(next); void notify({ type: 'success', title: 'Lista actualizada', message }); return true })
      if (!saved.acquired) { void notify({ type: 'warning', title: 'Operación en curso', message: 'Esperá a que termine la operación actual para volver a intentar.' }); return false }
      return saved.acquired && saved.result === true
    }
    catch { void notify({ type: 'error', title: 'No se pudieron guardar los cambios', message: 'Intentá nuevamente.' }); return false }
  }

  async function importSuggestions(loadSuggestions: () => Promise<ShoppingSuggestion[]>, label: string) {
    try {
      const outcome = await runExclusive('suggestions', async () => {
        const suggestions = await loadSuggestions()
        if (suggestions.length === 0) { void notify({ type: 'info', title: 'Sin faltantes', message: `No hay faltantes para ${label}.` }); return }
        const next = await mockShoppingRepository.append(suggestions)
        setItems(next)
        void notify({ type: 'success', title: 'Sugerencias añadidas', message: `${suggestions.length} ${suggestions.length === 1 ? 'artículo sugerido' : 'artículos sugeridos'} desde ${label}.` })
      })
      if (!outcome.acquired) void notify({ type: 'warning', title: 'Operación en curso', message: 'Esperá a que termine la operación actual para volver a intentar.' })
    } catch { void notify({ type: 'error', title: 'No se pudieron cargar las sugerencias', message: `No se pudieron cargar o guardar las sugerencias desde ${label}. Intentá nuevamente.` }) }
  }

  async function importFavorites() {
    await importSuggestions(() => mockShoppingRepository.suggestionsFromFavorites(), 'favoritos')
  }

  async function importPlan() {
    await importSuggestions(() => mockShoppingRepository.suggestionsFromWeek(weekDates()), 'el plan de esta semana')
  }

  async function saveDraft(event: FormEvent<HTMLFormElement>) {
    event.preventDefault()
    if (!draft) return
    const invalidField = event.currentTarget.querySelector<HTMLElement>(':invalid')
    if (invalidField) {
      setError('Revisá los campos obligatorios y sus valores.')
      invalidField.focus()
      return
    }
    const original = items.find((item) => item.id === draft.id)
    const candidate = original?.transferredToPantry
      ? { ...original, note: draft.note.trim() }
      : { ...draft, name: draft.name.trim().replace(/\s+/g, ' '), note: draft.note.trim() }
    if (!candidate.name || !Number.isFinite(candidate.quantity) || candidate.quantity <= 0 || candidate.quantity > 1_000_000) {
      setError('Ingresá un nombre y una cantidad mayor que cero.'); return
    }
    if (candidate.ingredientId && !validCatalogItems.some((item) => item.id === candidate.ingredientId)) { setError('Elegí un ingrediente activo del catálogo o quitá la asociación.'); return }
    if (candidate.ingredientId) {
      const ingredient = validCatalogItems.find((item) => item.id === candidate.ingredientId)!
      const baseUnit = catalog.units.find((unit) => unit.id === ingredient.baseUnitId)
      if (!baseUnit || !compatibleUnitAbbreviations(baseUnit.abbreviation, activeUnits).includes(candidate.unit)) { setError('La unidad no es compatible con el ingrediente elegido.'); return }
    }
    if (items.some((item) => item.id !== candidate.id && shoppingKey(item.name, item.unit, catalog.units) === shoppingKey(candidate.name, candidate.unit, catalog.units))) {
      setError('Ese artículo con la misma unidad ya está en la lista. Editalo para cambiar su cantidad.'); return
    }
    const editing = items.some((item) => item.id === candidate.id)
    const next = editing ? items.map((item) => item.id === candidate.id ? candidate : item) : [...items, candidate]
    if (await persist(next, editing ? 'Artículo actualizado.' : 'Artículo añadido.')) setDraft(null)
  }

  async function remove(item: ShoppingItem) {
    const confirmed = await notify({ type: 'warning', title: 'Eliminar artículo', message: `¿Eliminar ${item.name} de la lista?`, confirmLabel: 'Eliminar', cancelLabel: 'Cancelar' })
    if (!confirmed) return
    void persist(items.filter((entry) => entry.id !== item.id), 'Artículo eliminado.')
  }

  async function togglePurchased(item: ShoppingItem, checked: boolean) {
    try {
      const outcome = await runExclusive('purchase', async () => {
        const next = await mockShoppingRepository.setPurchased(item.id, checked)
        setItems(next)
      })
      if (!outcome.acquired) void notify({ type: 'warning', title: 'Operación en curso', message: 'Esperá a que termine la operación actual para volver a intentar.' })
    } catch { void notify({ type: 'error', title: 'No se pudo actualizar la compra', message: 'Intentá nuevamente.' }) }
  }

  async function markAll() {
    try {
      const outcome = await runExclusive('mark-all', async () => { setItems(await mockShoppingRepository.markAllPurchased()); void notify({ type: 'success', title: 'Compras actualizadas', message: `${pendingCount} ${pendingCount === 1 ? 'producto marcado como comprado' : 'productos marcados como comprados'}.` }) })
      if (!outcome.acquired) void notify({ type: 'warning', title: 'Operación en curso', message: 'Esperá a que termine la operación actual para volver a intentar.' })
    }
    catch { void notify({ type: 'error', title: 'No se pudieron marcar las compras', message: 'Intentá nuevamente.' }) }
  }

  async function transferAll() {
    if (transferableCount > 1 && !await notify({ type: 'warning', title: 'Enviar productos a la despensa', message: `Se enviarán ${transferableCount} productos a la despensa y se quitarán de la lista de compras. ¿Continuar?`, confirmLabel: 'Continuar', cancelLabel: 'Cancelar' })) return
    try {
      const outcome = await runExclusive('transfer', async () => {
        const result = await mockShoppingRepository.transferPurchased()
        setItems(result.items)
        void notify({ type: result.transferredCount ? 'success' : 'info', title: result.transferredCount ? 'Transferencia completada' : 'Sin productos transferibles', message: result.transferredCount ? `${result.transferredCount} ${result.transferredCount === 1 ? 'producto transferido' : 'productos transferidos'} a la despensa.` : 'Marcá artículos como comprados y verificá que tengan una unidad y categoría válidas.' })
      })
      if (!outcome.acquired) void notify({ type: 'warning', title: 'Operación en curso', message: 'Esperá a que termine la operación actual para volver a intentar.' })
    } catch { void notify({ type: 'error', title: 'La transferencia no se completó', message: 'Podés reintentar sin duplicar productos.' }) }
  }

  const mutating = working !== ''

  return <div className="page shopping-page">
    <header className="page-heading"><div><p className="eyebrow">ORGANIZÁ TUS COMPRAS</p><h1>Lista de compras</h1><p className="page-lead">Agregá artículos o calculá lo que falta para cocinar.</p></div><button className="button button-primary" disabled={loading || mutating} onClick={() => { setDraft(emptyItem()); setError('') }} type="button"><Plus size={17} /> Añadir artículo</button></header>

    <section aria-label="Añadir sugerencias" className="shopping-imports"><button className="button button-quiet" disabled={loading || mutating} onClick={importPlan} type="button"><CalendarDays size={17} /> Desde el plan semanal</button><button className="button button-quiet" disabled={loading || mutating} onClick={importFavorites} type="button"><Heart size={17} /> Desde favoritos</button><button className="button button-quiet" disabled={loading || mutating} onClick={() => void importSuggestions(() => mockShoppingRepository.suggestionsForRestock(), 'la despensa')} type="button"><Refrigerator size={17} /> Reponer despensa</button></section>

    <section aria-label="Acciones de compras" className="shopping-imports shopping-primary-actions"><button className="button button-quiet" disabled={pendingCount === 0 || mutating} onClick={markAll} type="button"><CheckCheck size={17} /> Marcar todas como compradas</button><button className="button button-primary" disabled={transferableCount === 0 || mutating} onClick={transferAll} type="button">{working === 'transfer' ? <LoaderCircle className="spin" size={17} /> : <Refrigerator size={17} />} {working === 'transfer' ? 'Enviando…' : `Enviar ${transferableCount} ${transferableCount === 1 ? 'producto' : 'productos'} a despensa`}</button></section>

    <section aria-label="Filtros de compras" className="shopping-controls"><label className="field"><span>Buscar artículo</span><span className="pantry-search-input"><Search aria-hidden="true" size={17} /><input onChange={(event) => setSearch(event.currentTarget.value)} placeholder="Ej.: arroz" type="search" value={search} /></span></label><label className="field"><span>Estado</span><select onChange={(event) => setStatus(event.currentTarget.value as ShoppingStatusFilter)} value={status}><option value="all">Todos</option><option value="pending">Pendientes</option><option value="checked">Comprados</option></select></label></section>
    <div aria-label="Filtrar por categoría" className="shopping-category-filters" role="group"><button aria-pressed={category === ''} className="shopping-category-chip" onClick={() => setCategory('')} type="button">Todas</button>{categories.map((option) => <button aria-pressed={category === option} className="shopping-category-chip" key={option} onClick={() => setCategory(option)} type="button">{option}</button>)}</div>
    <div className="pantry-results"><span><SearchFeedback resultCount={visible.length} status={debouncedSearch.status} />{debouncedSearch.status === 'empty' && ` · ${visible.length} visibles · ${checkedCount} de ${items.length} comprados`}</span><button onClick={() => { setSearch(''); setCategory(''); setStatus('all') }} type="button">Limpiar filtros</button></div>
    <section aria-label="Compartir lista" className="shopping-imports shopping-share-actions"><button className="button button-quiet shopping-share-button" onClick={async () => { try { await navigator.clipboard.writeText(shareText); void notify({ type: 'success', title: 'Lista copiada', message: 'Lista copiada al portapapeles.' }) } catch { void notify({ type: 'error', title: 'No se pudo copiar', message: 'No se pudo copiar automáticamente. Revisá los permisos del portapapeles e intentá nuevamente.' }) } }} type="button"><Copy aria-hidden="true" size={16} /> Copiar al portapapeles</button><button className="button button-quiet shopping-share-button" onClick={async () => { if (!navigator.share) { void notify({ type: 'info', title: 'Compartir no disponible', message: 'Compartir no está disponible en este dispositivo. Usá «Copiar al portapapeles» para pegar la lista donde quieras.' }); return } try { await navigator.share({ title: 'Lista de compras CocinAPP', text: shareText }); void notify({ type: 'success', title: 'Lista compartida', message: 'Lista compartida.' }) } catch (cause) { if (cause instanceof Error && cause.name === 'AbortError') return; void notify({ type: 'error', title: 'No se pudo compartir', message: 'Podés usar «Copiar al portapapeles» para compartir la lista manualmente.' }) } }} type="button"><Share2 aria-hidden="true" size={16} /> Compartir</button><a aria-label="Compartir lista por WhatsApp" className="button button-quiet shopping-share-button" href={`https://wa.me/?text=${encodeURIComponent(shareText)}`} rel="noreferrer" target="_blank"><MessageCircle aria-hidden="true" size={16} /> WhatsApp</a></section>
    {working === 'suggestions' && <p className="form-message" role="status">Calculando y guardando sugerencias…</p>}{working === 'save' && <p className="form-message" role="status">Guardando cambios…</p>}{working === 'purchase' && <p className="form-message" role="status">Actualizando compra…</p>}{working === 'mark-all' && <p className="form-message" role="status">Marcando compras…</p>}

    {loading && <p role="status">Cargando lista de compras…</p>}{!loading && debouncedSearch.status !== 'waiting' && (visible.length === 0 ? <section className="pantry-empty"><h2>{items.length ? 'Sin resultados' : 'Tu lista está vacía'}</h2><p>{items.length ? 'Probá otros filtros.' : 'Añadí un artículo o generá sugerencias desde el plan, favoritos o despensa.'}</p></section> : <section aria-label="Artículos de compras" className="shopping-list">{groups.map((group) => <div className="shopping-group" key={group.name}><h2>{group.name}</h2>{group.items.map((item) => <article className={`shopping-row${item.checked ? ' checked' : ''}`} key={item.id}><label className="shopping-check"><input aria-label={`${item.checked ? 'Marcar pendiente' : 'Marcar comprado'}: ${item.name}`} checked={item.checked} disabled={mutating} onChange={(event) => void togglePurchased(item, event.currentTarget.checked)} type="checkbox" /></label><div className="shopping-copy"><strong>{item.name}</strong><span>{formatPantryAmount(item.quantity, item.unit)} · {item.sources.map((source) => sourceLabels[source]).join(', ')}</span><small className="shopping-state">{item.ingredientId ? 'Ingrediente de catálogo' : 'Artículo propio'} · {item.transferredToPantry ? '✓ En despensa' : item.checked ? '✓ Comprado' : '○ Pendiente'}</small>{item.note && <small>{item.note}</small>}</div><div className="shopping-actions"><button aria-label={`Editar ${item.name}`} className="pantry-icon-button" disabled={mutating} onClick={() => { setDraft({ ...item }); setError('') }} type="button"><Pencil size={17} /></button><button aria-label={`Eliminar ${item.name}`} className="pantry-icon-button" disabled={mutating} onClick={() => remove(item)} type="button"><Trash2 size={17} /></button></div></article>)}</div>)}</section>)}

    <p className="pantry-footnote">La lista se guarda en este navegador. <Link className="text-link" to="/pantry">Ver despensa →</Link></p>
    {draft && <dialog aria-labelledby="shopping-editor-title" className="shopping-editor surface" onCancel={(event) => { if (workingRef.current) { event.preventDefault(); return } setDraft(null); setError('') }} ref={(node) => { if (node && !node.open) { node.showModal(); node.querySelector<HTMLInputElement>('input:not(:disabled)')?.focus() } }}><div className="shopping-editor-heading"><h2 id="shopping-editor-title">{items.some((item) => item.id === draft.id) ? 'Editar artículo' : 'Añadir artículo'}</h2><button aria-label="Cerrar formulario" className="pantry-icon-button" disabled={mutating} onClick={() => { setDraft(null); setError('') }} type="button"><X size={19} /></button></div><form noValidate onSubmit={saveDraft}>{draft.transferredToPantry && <p className="shopping-transfer-note">Este producto ya se sumó a tu despensa. Para corregir nombre, cantidad, unidad o categoría, <Link className="text-link" to="/pantry">editá el stock en Despensa</Link>.</p>}<label className="field"><span>Artículo</span><input disabled={mutating || draft.transferredToPantry} maxLength={70} onChange={(event) => setDraft({ ...draft, name: event.currentTarget.value, ingredientId: null })} required value={draft.name} /></label><IngredientPicker key={draft.id} ingredients={validCatalogItems} value={draft.ingredientId ?? ''} disabled={mutating || draft.transferredToPantry} onChange={(ingredient) => { const baseUnit = catalog.units.find((unit) => unit.id === ingredient?.baseUnitId); const categoryName = catalog.categories.find((entry) => entry.id === ingredient?.categoryId)?.name; setDraft({ ...draft, ingredientId: ingredient?.id ?? null, name: ingredient?.name ?? draft.name, unit: baseUnit?.abbreviation ?? draft.unit, category: categoryName ?? draft.category }) }} /><div className="shopping-form-grid"><label className="field"><span>Cantidad</span><input disabled={mutating || draft.transferredToPantry} min="0.01" max="1000000" onChange={(event) => setDraft({ ...draft, quantity: event.currentTarget.valueAsNumber })} required step="any" type="number" value={Number.isNaN(draft.quantity) ? '' : draft.quantity} /></label><label className="field"><span>Unidad</span><select disabled={mutating || draft.transferredToPantry} onChange={(event) => setDraft({ ...draft, unit: event.currentTarget.value as PantryUnit })} value={draft.unit}>{activeUnits.filter((unit) => allowedDraftUnits.includes(unit.abbreviation)).map((unit) => <option key={unit.id} value={unit.abbreviation}>{unit.abbreviation}</option>)}</select></label></div><label className="field"><span>Categoría</span><select disabled={mutating || draft.transferredToPantry} onChange={(event) => setDraft({ ...draft, category: event.currentTarget.value as PantryCategory })} value={draft.category}>{catalog.categories.filter((option) => option.active && !option.isDeleted).map((option) => <option key={option.id} value={option.name}>{option.name}</option>)}</select></label><label className="field"><span>Notas (opcional)</span><input disabled={mutating} maxLength={200} onChange={(event) => setDraft({ ...draft, note: event.currentTarget.value })} placeholder="Ej.: marca, tamaño" value={draft.note} /></label>{error && <p className="form-message error" role="alert">{error}</p>}<div className="pantry-dialog-actions"><button className="button button-quiet" disabled={mutating} onClick={() => { setDraft(null); setError('') }} type="button">Cancelar</button><button className="button button-primary" disabled={mutating} type="submit">Guardar artículo</button></div></form></dialog>}
  </div>
}

