import { AlertTriangle, CalendarClock, Check, ClipboardList, Pencil, Plus, Search, ShoppingCart, Trash2, X } from 'lucide-react'
import { type FormEvent, useEffect, useMemo, useRef, useState } from 'react'
import { useNavigate } from 'react-router-dom'
import { readPantryItems, writePantryItems } from '../features/pantry/data/localPantryStore'
import {
  countPantryAlerts, filterPantryItems, formatPantryAmount, getPantryStatus,
  hasDuplicateItem, pantryExpiryText,
  type PantryCategory, type PantryFilters, type PantryItem, type PantryStatus, type PantryUnit,
} from '../features/pantry/domain/pantry'
import { findActiveIngredient, getActiveCategories, getAdminData, getUnitsForIngredient } from '../features/admin/data/localAdminStore'
import { appendShoppingSuggestions } from '../features/shopping/data/localShoppingStore'
import { suggestPantryRestock } from '../features/shopping/domain/shopping'

type SortOrder = 'name' | 'expiry' | 'quantity'

const emptyFilters: PantryFilters = { search: '', category: '', status: '' }

function localDateWithOffset(days: number): string {
  const date = new Date()
  date.setDate(date.getDate() + days)
  return `${date.getFullYear()}-${String(date.getMonth() + 1).padStart(2, '0')}-${String(date.getDate()).padStart(2, '0')}`
}

function exampleItems(): PantryItem[] {
  const examples = [
    ['Pechuga de pollo', 'Carnes y pescados', 500, 'g', 200, 2],
    ['Arroz integral', 'Granos y legumbres', 1000, 'g', 300, null],
    ['Leche', 'Lácteos', 1000, 'ml', 500, 5],
    ['Palta', 'Frutas y verduras', 2, 'u', 1, 3],
    ['Tomates cherry', 'Frutas y verduras', 250, 'g', 300, 2],
    ['Aceite de oliva', 'Almacén', 750, 'ml', 150, null],
  ] as const satisfies ReadonlyArray<readonly [string, PantryCategory, number, PantryUnit, number, number | null]>

  return examples.map(([name, category, quantity, unit, minimum, expiryDays]) => ({
    id: crypto.randomUUID(), name, category, quantity, unit, minimum,
    expiry: expiryDays === null ? '' : localDateWithOffset(expiryDays),
  }))
}

function PantryEditor({ item, items, onClose, onSave }: {
  item: PantryItem
  items: PantryItem[]
  onClose: () => void
  onSave: (item: PantryItem) => boolean
}) {
  const dialogRef = useRef<HTMLDialogElement>(null)
  const [draft, setDraft] = useState(item)
  const [error, setError] = useState('')
  const editing = items.some((existing) => existing.id === item.id)

  useEffect(() => {
    const dialog = dialogRef.current
    dialog?.showModal()
    dialog?.querySelector<HTMLInputElement>('input[name="name"]')?.focus()
    return () => { if (dialog?.open) dialog.close() }
  }, [])

  function submit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault()
    const candidate = { ...draft, name: draft.name.trim().replace(/\s+/g, ' ') }
    if (!candidate.name || !Number.isFinite(candidate.quantity) || !Number.isFinite(candidate.minimum)) {
      setError('Revisá el nombre y las cantidades.')
      return
    }
    if (hasDuplicateItem(items, candidate)) {
      setError('Ese ingrediente con la misma unidad ya existe. Editalo para cambiar su cantidad.')
      dialogRef.current?.querySelector<HTMLInputElement>('input[name="name"]')?.focus()
      return
    }
    if (onSave(candidate)) onClose()
    else setError('No se pudo guardar. Revisá el espacio disponible del navegador.')
  }

  return <dialog aria-labelledby="pantry-editor-title" className="pantry-dialog" onCancel={(event) => { event.preventDefault(); onClose() }} ref={dialogRef}>
    <div className="pantry-dialog-header"><div><p className="eyebrow">DESPENSA</p><h2 id="pantry-editor-title">{editing ? 'Editar ingrediente' : 'Añadir ingrediente'}</h2></div><button aria-label="Cerrar formulario" className="pantry-icon-button" onClick={onClose} title="Cerrar" type="button"><X size={19} /></button></div>
    <p className="pantry-dialog-intro">Registrá el stock disponible y, si querés, un mínimo y un vencimiento.</p>
    <form className="pantry-form" onSubmit={submit}>
      <label className="field"><span>Ingrediente</span><input autoComplete="off" list="admin-ingredient-catalog" maxLength={70} name="name" onChange={(event) => { const name = event.currentTarget.value; const catalogItem = findActiveIngredient(name); const catalogData = getAdminData(); const category = catalogData.categories.find((item) => item.id === catalogItem?.categoryId)?.name; const baseUnit = catalogData.units.find((item) => item.id === catalogItem?.baseUnitId)?.abbreviation; setDraft({ ...draft, name, ...(category ? { category } : {}), ...(baseUnit ? { unit: baseUnit } : {}) }); setError('') }} placeholder="Ej.: arroz integral" required value={draft.name} /><datalist id="admin-ingredient-catalog">{getAdminData().ingredients.filter((item) => !item.isDeleted).map((item) => <option key={item.id} value={item.name} />)}</datalist></label>
      <label className="field"><span>Categoría</span><select onChange={(event) => setDraft({ ...draft, category: event.currentTarget.value as PantryCategory })} value={draft.category}>{getActiveCategories().map((category) => <option key={category}>{category}</option>)}</select></label>
      <div className="pantry-form-grid">
        <label className="field"><span>Cantidad disponible</span><input inputMode="decimal" max="1000000" min="0" name="quantity" onChange={(event) => setDraft({ ...draft, quantity: event.currentTarget.value === '' ? Number.NaN : event.currentTarget.valueAsNumber })} required step="any" type="number" value={Number.isNaN(draft.quantity) ? '' : draft.quantity} /></label>
        <label className="field"><span>Unidad</span><select onChange={(event) => setDraft({ ...draft, unit: event.currentTarget.value as PantryUnit })} value={draft.unit}>{getUnitsForIngredient(draft.name).map((unit) => <option key={unit}>{unit}</option>)}</select></label>
        <label className="field"><span>Avisar por debajo de</span><input inputMode="decimal" max="1000000" min="0" name="minimum" onChange={(event) => setDraft({ ...draft, minimum: event.currentTarget.value === '' ? Number.NaN : event.currentTarget.valueAsNumber })} required step="any" type="number" value={Number.isNaN(draft.minimum) ? '' : draft.minimum} /></label>
        <label className="field"><span>Vencimiento (opcional)</span><input onChange={(event) => setDraft({ ...draft, expiry: event.currentTarget.value })} type="date" value={draft.expiry} /></label>
      </div>
      <p className="pantry-form-hint">El mínimo usa la misma unidad. Un valor de 0 desactiva la alerta de stock bajo.</p>
      {error && <p className="form-message error" role="alert">{error}</p>}
      <div className="pantry-dialog-actions"><button className="button button-quiet" onClick={onClose} type="button">Cancelar</button><button className="button button-primary" type="submit">Guardar ingrediente</button></div>
    </form>
  </dialog>
}

function PantryConfirmation({ title, message, actionLabel, danger = false, onClose, onConfirm }: {
  title: string
  message: string
  actionLabel: string
  danger?: boolean
  onClose: () => void
  onConfirm: () => boolean
}) {
  const dialogRef = useRef<HTMLDialogElement>(null)
  useEffect(() => {
    const dialog = dialogRef.current
    dialog?.showModal()
    return () => { if (dialog?.open) dialog.close() }
  }, [])
  return <dialog aria-labelledby="pantry-confirm-title" className="pantry-dialog pantry-confirm" onCancel={(event) => { event.preventDefault(); onClose() }} ref={dialogRef}>
    <h2 id="pantry-confirm-title">{title}</h2>
    <p>{message}</p>
    <div className="pantry-dialog-actions"><button className="button button-quiet" onClick={onClose} type="button">Cancelar</button><button className={`button ${danger ? 'pantry-danger-button' : 'button-primary'}`} onClick={() => { if (onConfirm()) onClose() }} type="button">{danger && <Trash2 size={16} />}{actionLabel}</button></div>
  </dialog>
}

export function PantryPage() {
  const navigate = useNavigate()
  const [items, setItems] = useState<PantryItem[]>(() => readPantryItems())
  const [filters, setFilters] = useState<PantryFilters>(emptyFilters)
  const [sortOrder, setSortOrder] = useState<SortOrder>('name')
  const [editor, setEditor] = useState<PantryItem | null>(null)
  const [deleting, setDeleting] = useState<PantryItem | null>(null)
  const [confirmExamples, setConfirmExamples] = useState(false)
  const [notice, setNotice] = useState('')
  const [storageError, setStorageError] = useState('')
  const addButtonRef = useRef<HTMLButtonElement>(null)
  const focusBeforeDialog = useRef<HTMLElement | null>(null)

  function closeDialog() {
    setEditor(null)
    setDeleting(null)
    setConfirmExamples(false)
    const previousFocus = focusBeforeDialog.current
    requestAnimationFrame(() => (previousFocus?.isConnected ? previousFocus : addButtonRef.current)?.focus())
  }

  const visibleItems = useMemo(() => {
    const result = filterPantryItems(items, filters)
    if (sortOrder === 'expiry') result.sort((a, b) => (a.expiry || '9999-12-31').localeCompare(b.expiry || '9999-12-31') || a.name.localeCompare(b.name, 'es'))
    if (sortOrder === 'quantity') result.sort((a, b) => a.quantity - b.quantity || a.name.localeCompare(b.name, 'es'))
    return result
  }, [items, filters, sortOrder])

  const alertCounts = countPantryAlerts(items)

  function persist(next: PantryItem[]): boolean {
    try {
      writePantryItems(next)
      setItems(next)
      setStorageError('')
      return true
    } catch {
      setStorageError('No se pudieron guardar los cambios en este navegador.')
      return false
    }
  }

  function saveItem(item: PantryItem): boolean {
    const editing = items.some((existing) => existing.id === item.id)
    const next = editing ? items.map((existing) => existing.id === item.id ? item : existing) : [...items, item]
    if (!persist(next)) return false
    setNotice(editing ? 'Ingrediente actualizado.' : 'Ingrediente añadido.')
    return true
  }

  function addExamples(): boolean {
    const additions = exampleItems().filter((item) => !hasDuplicateItem(items, item))
    if (additions.length === 0) { setNotice('El kit de ejemplo ya está cargado.'); return true }
    if (!persist([...items, ...additions])) return false
    setNotice(`${additions.length} ingredientes de ejemplo añadidos.`)
    return true
  }

  function deleteItem(): boolean {
    if (!deleting || !persist(items.filter((item) => item.id !== deleting.id))) return false
    setNotice('Ingrediente eliminado.')
    return true
  }

  function sendRestockToShopping() {
    const suggestions = suggestPantryRestock(items)
    if (suggestions.length === 0) { setNotice('No hay productos para reponer.'); return }
    try { appendShoppingSuggestions(suggestions); navigate('/shopping') }
    catch { setStorageError('No se pudo guardar la lista de compras en este navegador.') }
  }

  return <div className="page pantry-page">
    <header className="page-heading pantry-heading">
      <div><p className="eyebrow">TUS INGREDIENTES</p><h1>Mi despensa</h1><p className="page-lead">Registrá cantidades y vencimientos para saber qué tenés disponible.</p></div>
      <div className="pantry-head-actions"><button className="button button-quiet" onClick={sendRestockToShopping} type="button"><ShoppingCart size={17} /> Reponer</button><button className="button button-quiet" onClick={(event) => { focusBeforeDialog.current = event.currentTarget; setConfirmExamples(true) }} type="button"><ClipboardList size={17} /> Kit de ejemplo</button><button className="button button-primary" onClick={(event) => { focusBeforeDialog.current = event.currentTarget; setEditor({ id: crypto.randomUUID(), name: '', category: getActiveCategories()[0], quantity: Number.NaN, unit: 'g', minimum: 0, expiry: '' }) }} ref={addButtonRef} type="button"><Plus size={18} /> Añadir ingrediente</button></div>
    </header>

    <section aria-label="Resumen de la despensa" className="pantry-summary">
      <button aria-pressed={filters.status === ''} onClick={() => setFilters(emptyFilters)} type="button"><ClipboardList aria-hidden="true" size={19} /><span>Productos</span><strong>{items.length}</strong></button>
      <button aria-pressed={filters.status === 'low'} className="pantry-summary-low" onClick={() => setFilters({ ...emptyFilters, status: 'low' })} type="button"><AlertTriangle aria-hidden="true" size={19} /><span>Stock bajo</span><strong>{alertCounts.low}</strong></button>
      <button aria-pressed={filters.status === 'expired'} className="pantry-summary-expiry" onClick={() => setFilters({ ...emptyFilters, status: 'expired' })} type="button"><CalendarClock aria-hidden="true" size={19} /><span>Vencidos</span><strong>{alertCounts.expired}</strong></button>
      <button aria-pressed={filters.status === 'soon'} className="pantry-summary-expiry" onClick={() => setFilters({ ...emptyFilters, status: 'soon' })} type="button"><CalendarClock aria-hidden="true" size={19} /><span>Por vencer</span><strong>{alertCounts.soon}</strong></button>
    </section>

    <section aria-label="Filtros de ingredientes" className="pantry-controls">
      <label className="field pantry-search"><span>Buscar por nombre</span><span className="pantry-search-input"><Search aria-hidden="true" size={17} /><input onChange={(event) => setFilters({ ...filters, search: event.currentTarget.value })} placeholder="Ej.: arroz, tomate" type="search" value={filters.search} /></span></label>
      <label className="field"><span>Categoría</span><select onChange={(event) => setFilters({ ...filters, category: event.currentTarget.value as PantryCategory | '' })} value={filters.category}><option value="">Todas</option>{getActiveCategories().map((category) => <option key={category}>{category}</option>)}</select></label>
      <label className="field"><span>Estado</span><select onChange={(event) => setFilters({ ...filters, status: event.currentTarget.value as PantryStatus | '' })} value={filters.status}><option value="">Todos</option><option value="ok">Disponibles</option><option value="low">Stock bajo</option><option value="empty">Sin stock</option><option value="soon">Por vencer</option><option value="expired">Vencidos</option></select></label>
      <label className="field"><span>Ordenar por</span><select onChange={(event) => setSortOrder(event.currentTarget.value as SortOrder)} value={sortOrder}><option value="name">Nombre</option><option value="expiry">Vencimiento</option><option value="quantity">Cantidad</option></select></label>
    </section>

    <div className="pantry-results"><span aria-live="polite">{visibleItems.length} {visibleItems.length === 1 ? 'ingrediente visible' : 'ingredientes visibles'}</span><button disabled={!filters.search && !filters.category && !filters.status} onClick={() => setFilters(emptyFilters)} type="button">Limpiar filtros</button></div>
    {notice && <p className="form-message pantry-notice" role="status"><Check size={16} /> {notice}</p>}
    {storageError && <p className="form-message error" role="alert">{storageError}</p>}

    {visibleItems.length === 0 ? <section className="pantry-empty" aria-label="Despensa vacía"><ClipboardList aria-hidden="true" size={34} /><h2>{items.length ? 'Sin resultados para estos filtros' : 'Tu despensa está vacía'}</h2><p>{items.length ? 'Probá otro nombre, categoría o estado.' : 'Añadí un ingrediente o cargá el kit de ejemplo para empezar.'}</p></section> : <section aria-label="Ingredientes de la despensa" className="pantry-list">
      {visibleItems.map((item) => {
        const status = getPantryStatus(item)
        return <article className="pantry-item" key={item.id}>
          <div className="pantry-item-main"><span className="pantry-item-symbol" aria-hidden="true">{item.name.charAt(0).toLocaleUpperCase('es')}</span><div><h2>{item.name}</h2><p>{item.category}</p></div></div>
          <div className="pantry-item-amount"><strong>{formatPantryAmount(item.quantity, item.unit)}</strong><small>Cantidad</small></div>
          <div className="pantry-item-status"><span className={`pantry-status pantry-status-${status.kind}`}>{status.label}</span><small>{item.minimum ? `Mínimo: ${formatPantryAmount(item.minimum, item.unit)}` : 'Sin mínimo'}</small></div>
          <div className="pantry-item-expiry"><span>{pantryExpiryText(item)}</span></div>
          <div className="pantry-item-actions"><button aria-label={`Editar ${item.name}`} className="pantry-icon-button" onClick={(event) => { focusBeforeDialog.current = event.currentTarget; setEditor(item) }} title="Editar ingrediente" type="button"><Pencil size={17} /></button><button aria-label={`Eliminar ${item.name}`} className="pantry-icon-button" onClick={(event) => { focusBeforeDialog.current = event.currentTarget; setDeleting(item) }} title="Eliminar ingrediente" type="button"><Trash2 size={17} /></button></div>
        </article>
      })}
    </section>}

    <p className="pantry-footnote">Los datos se guardan en este navegador y se usan para indicar la disponibilidad de ingredientes en recetas.</p>
    {editor && <PantryEditor item={editor} items={items} onClose={closeDialog} onSave={saveItem} />}
    {deleting && <PantryConfirmation actionLabel="Eliminar" danger message={`¿Querés eliminar ${deleting.name} de tu despensa?`} onClose={closeDialog} onConfirm={deleteItem} title="Eliminar ingrediente" />}
    {confirmExamples && <PantryConfirmation actionLabel="Cargar ejemplos" message="Se añadirán productos de muestra sin reemplazar tus ingredientes actuales ni duplicar productos del mismo nombre y unidad." onClose={closeDialog} onConfirm={addExamples} title="Cargar kit de ejemplo" />}
  </div>
}


