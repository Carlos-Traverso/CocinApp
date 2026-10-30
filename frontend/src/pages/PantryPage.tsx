import { LoadingScreen } from '../components/LoadingScreen'
import { AlertTriangle, CalendarClock, ClipboardList, ImagePlus, Pencil, Plus, Search, ShoppingCart, Trash2, X } from 'lucide-react'
import { type FormEvent, useEffect, useMemo, useRef, useState } from 'react'
import { useNavigate } from 'react-router-dom'
import { getPantryItems, savePantryItems } from '../features/pantry/data/localPantryStore'
import {
  countPantryAlerts, filterPantryItems, formatPantryAmount, getPantryStatus,
  hasDuplicateItem, pantryExpiryText,
  type PantryCategory, type PantryFilters, type PantryItem, type PantryStatus, type PantryUnit,
} from '../features/pantry/domain/pantry'
import { adminRepository } from '../features/admin/data/AdminRepository'
import type { AdminStorageData } from '../features/admin/data/localAdminStore'
import { defaultPantryCategories, defaultPantryUnits, normalizePantryName } from '../features/pantry/domain/pantry'
import { mockShoppingRepository } from '../features/shopping/data/MockShoppingRepository'
import { SearchFeedback } from '../shared/search/SearchFeedback'
import { useDebouncedSearch } from '../shared/search/useDebouncedSearch'
import { compatibleUnitAbbreviations } from '../shared/domain/units'
import { isValidReceiptImage, mockReceiptScanner } from '../features/pantry/data/mockReceiptScanner'
import { useNotifications } from '../shared/notifications/NotificationProvider'

type ReceiptLine = { id: string; name: string; quantity: number; unit: string; ingredientName: string }

type SortOrder = 'name' | 'expiry' | 'quantity'

const emptyFilters: PantryFilters = { search: '', category: '', status: '' }

function activeCategories(catalog: AdminStorageData) {
  const custom = catalog.categories.filter((item) => item.active && !item.isDeleted).map((item) => item.name)
  const defaults = defaultPantryCategories.filter((name) => {
    const record = catalog.categories.find((item) => normalizePantryName(item.name) === normalizePantryName(name))
    return !record || record.active && !record.isDeleted
  })
  return [...new Set([...defaults, ...custom])].sort((a, b) => a.localeCompare(b, 'es'))
}

function activeUnits(catalog: AdminStorageData) {
  const custom = catalog.units.filter((item) => item.active && !item.isDeleted).map((item) => item.abbreviation)
  const defaults = defaultPantryUnits.filter((abbreviation) => {
    const record = catalog.units.find((item) => item.abbreviation.toLocaleLowerCase('es') === abbreviation.toLocaleLowerCase('es'))
    return !record || record.active && !record.isDeleted
  })
  return [...new Set([...defaults, ...custom])]
}

function findCatalogIngredient(catalog: AdminStorageData, name: string) {
  const normalized = normalizePantryName(name)
  return catalog.ingredients.find((item) => item.active && !item.isDeleted && normalizePantryName(item.name) === normalized)
}

function fieldValidationMessage(field: HTMLInputElement | HTMLSelectElement): string {
  if (field.validity.valueMissing) return 'Completá este campo.'
  if (field.validity.typeMismatch) return 'Ingresá un valor válido.'
  if (field.validity.rangeUnderflow) return `El valor debe ser al menos ${field.getAttribute('min')}.`
  if (field.validity.rangeOverflow) return `El valor no puede superar ${field.getAttribute('max')}.`
  if (field.validity.tooLong) return `El texto no puede superar ${field.getAttribute('maxLength')} caracteres.`
  return 'Revisá el dato ingresado.'
}

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

function PantryEditor({ item, items, catalog, categories, onClose, onSave }: {
  item: PantryItem
  items: PantryItem[]
  catalog: AdminStorageData
  categories: string[]
  onClose: () => void
  onSave: (item: PantryItem) => Promise<boolean>
}) {
  const dialogRef = useRef<HTMLDialogElement>(null)
  const [draft, setDraft] = useState(item)
  const [error, setError] = useState('')
  const editing = items.some((existing) => existing.id === item.id)
  const selectedIngredient = findCatalogIngredient(catalog, draft.name)
  const selectedBase = catalog.units.find((unit) => unit.id === selectedIngredient?.baseUnitId)
  const unitChoices = selectedBase ? compatibleUnitAbbreviations(selectedBase.id, catalog.units) : activeUnits(catalog)

  useEffect(() => {
    const dialog = dialogRef.current
    dialog?.showModal()
    dialog?.querySelector<HTMLInputElement>('input[name="name"]')?.focus()
    return () => { if (dialog?.open) dialog.close() }
  }, [])

  async function submit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault()
    const form = event.currentTarget
    if (!form.checkValidity()) {
      const invalidField = form.querySelector<HTMLInputElement | HTMLSelectElement>(':invalid')
      setError(invalidField ? fieldValidationMessage(invalidField) : 'Revisá los datos ingresados.')
      invalidField?.focus()
      return
    }
    const candidate = { ...draft, name: draft.name.trim().replace(/\s+/g, ' ') }
    if (!candidate.name || !Number.isFinite(candidate.quantity) || candidate.quantity < 0 || (!editing && candidate.quantity === 0) || !Number.isFinite(candidate.minimum) || candidate.minimum < 0) {
      setError('Revisá el nombre y las cantidades.')
      return
    }
    if (hasDuplicateItem(items, candidate)) {
      setError('Ese ingrediente con la misma unidad ya existe. Editalo para cambiar su cantidad.')
      dialogRef.current?.querySelector<HTMLInputElement>('input[name="name"]')?.focus()
      return
    }
    if (await onSave(candidate)) onClose()
    // Persistence failures are announced by the page; keep this form's inline
    // message for field validation while the dialog is open.
  }

  return <dialog aria-labelledby="pantry-editor-title" className="pantry-dialog" onCancel={(event) => { event.preventDefault(); onClose() }} ref={dialogRef}>
    <div className="pantry-dialog-header"><div><p className="eyebrow">DESPENSA</p><h2 id="pantry-editor-title">{editing ? 'Editar ingrediente' : 'Añadir ingrediente'}</h2></div><button aria-label="Cerrar formulario" className="pantry-icon-button" onClick={onClose} title="Cerrar" type="button"><X size={19} /></button></div>
    <p className="pantry-dialog-intro">Registrá el stock disponible y, si querés, un mínimo y un vencimiento.</p>
    <form className="pantry-form" noValidate onSubmit={submit}>
      <label className="field"><span>Ingrediente</span><input autoComplete="off" list="admin-ingredient-catalog" maxLength={70} name="name" onChange={(event) => { const name = event.currentTarget.value; const catalogItem = findCatalogIngredient(catalog, name); const category = catalog.categories.find((entry) => entry.id === catalogItem?.categoryId)?.name; const baseUnit = catalog.units.find((entry) => entry.id === catalogItem?.baseUnitId)?.abbreviation; setDraft({ ...draft, name, ingredientId: catalogItem?.id, ...(category ? { category } : {}), ...(baseUnit ? { unit: baseUnit } : {}) }); setError('') }} placeholder="Ej.: arroz integral" required value={draft.name} /><datalist id="admin-ingredient-catalog">{catalog.ingredients.filter((entry) => entry.active && !entry.isDeleted).map((entry) => <option key={entry.id} value={entry.name} />)}</datalist></label>
      <label className="field"><span>Categoría</span><select onChange={(event) => setDraft({ ...draft, category: event.currentTarget.value as PantryCategory })} value={draft.category}>{categories.map((category) => <option key={category}>{category}</option>)}</select></label>
      <div className="pantry-form-grid">
        <label className="field"><span>Cantidad disponible</span><input inputMode="decimal" max="1000000" min="0" name="quantity" onChange={(event) => setDraft({ ...draft, quantity: event.currentTarget.value === '' ? Number.NaN : event.currentTarget.valueAsNumber })} required step="any" type="number" value={Number.isNaN(draft.quantity) ? '' : draft.quantity} /></label>
        <label className="field"><span>Unidad</span><select onChange={(event) => setDraft({ ...draft, unit: event.currentTarget.value as PantryUnit })} value={draft.unit}>{unitChoices.map((unit) => <option key={unit}>{unit}</option>)}</select></label>
        <label className="field"><span>Avisar por debajo de</span><input inputMode="decimal" max="1000000" min="0" name="minimum" onChange={(event) => setDraft({ ...draft, minimum: event.currentTarget.value === '' ? Number.NaN : event.currentTarget.valueAsNumber })} required step="any" type="number" value={Number.isNaN(draft.minimum) ? '' : draft.minimum} /></label>
        <label className="field"><span>Vencimiento (opcional)</span><input onChange={(event) => setDraft({ ...draft, expiry: event.currentTarget.value || null })} type="date" value={draft.expiry ?? ''} /></label>
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
  onConfirm: () => Promise<boolean>
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
    <div className="pantry-dialog-actions"><button className="button button-quiet" onClick={onClose} type="button">Cancelar</button><button className={`button ${danger ? 'pantry-danger-button' : 'button-primary'}`} onClick={async () => { if (await onConfirm()) onClose() }} type="button">{danger && <Trash2 size={16} />}{actionLabel}</button></div>
  </dialog>
}

export function PantryPage() {
  const navigate = useNavigate()
  const { notify } = useNotifications()
  const [items, setItems] = useState<PantryItem[]>([])
  const [catalog, setCatalog] = useState<AdminStorageData>({ categories: [], units: [], ingredients: [], recipes: [] })
  const [filters, setFilters] = useState<PantryFilters>(emptyFilters)
  const [sortOrder, setSortOrder] = useState<SortOrder>('name')
  const [editor, setEditor] = useState<PantryItem | null>(null)
  const [deleting, setDeleting] = useState<PantryItem | null>(null)
  const [confirmExamples, setConfirmExamples] = useState(false)
  const [receiptLines, setReceiptLines] = useState<ReceiptLine[] | null>(null)
  const [receiptBusy, setReceiptBusy] = useState(false)
  const [pantryLoading, setPantryLoading] = useState(true)
  const receiptAbort = useRef<AbortController | null>(null)
  const addButtonRef = useRef<HTMLButtonElement>(null)
  const receiptInputRef = useRef<HTMLInputElement>(null)
  const focusBeforeDialog = useRef<HTMLElement | null>(null)
  const search = useDebouncedSearch(filters.search)

  useEffect(() => { void Promise.all([getPantryItems(), adminRepository.getCatalog()]).then(([pantry, admin]) => { setItems(pantry); setCatalog(admin) }).catch(() => { void notify({ type: 'error', title: 'No se pudo cargar la despensa', message: 'No se pudo cargar la despensa y su catálogo.' }) }).finally(() => setPantryLoading(false)) }, [notify])
  const categories = useMemo(() => activeCategories(catalog), [catalog])

  function closeDialog() {
    setEditor(null)
    setDeleting(null)
    setConfirmExamples(false)
    const previousFocus = focusBeforeDialog.current
    requestAnimationFrame(() => (previousFocus?.isConnected ? previousFocus : addButtonRef.current)?.focus())
  }

  const visibleItems = useMemo(() => {
    if (search.status === 'waiting') return []
    const result = filterPantryItems(items, { ...filters, search: search.query })
    if (sortOrder === 'expiry') result.sort((a, b) => (a.expiry || '9999-12-31').localeCompare(b.expiry || '9999-12-31') || a.name.localeCompare(b.name, 'es'))
    if (sortOrder === 'quantity') result.sort((a, b) => a.quantity - b.quantity || a.name.localeCompare(b.name, 'es'))
    return result
  }, [items, filters, search.query, search.status, sortOrder])

  const alertCounts = countPantryAlerts(items)

  async function persist(next: PantryItem[]): Promise<boolean> {
    try {
      await savePantryItems(next)
      setItems(next)
      return true
    } catch {
      void notify({ type: 'error', title: 'No se pudieron guardar los cambios', message: 'Revisá el espacio disponible del navegador e intentá de nuevo.' })
      return false
    }
  }

  async function saveItem(item: PantryItem): Promise<boolean> {
    const editing = items.some((existing) => existing.id === item.id)
    const next = editing ? items.map((existing) => existing.id === item.id ? item : existing) : [...items, item]
    if (!await persist(next)) return false
    await notify({ type: 'success', title: editing ? 'Ingrediente actualizado' : 'Ingrediente añadido', message: editing ? 'Los cambios se guardaron en tu despensa.' : 'El ingrediente se guardó en tu despensa.' })
    return true
  }

  async function addExamples(): Promise<boolean> {
    const additions = exampleItems().filter((item) => !hasDuplicateItem(items, item))
    if (additions.length === 0) { await notify({ type: 'info', title: 'Kit de ejemplo', message: 'El kit de ejemplo ya está cargado.' }); return true }
    if (!await persist([...items, ...additions])) return false
    await notify({ type: 'success', title: 'Kit de ejemplo cargado', message: `${additions.length} ingredientes de ejemplo añadidos.` })
    return true
  }

  async function deleteItem(): Promise<boolean> {
    if (!deleting || !await persist(items.filter((item) => item.id !== deleting.id))) return false
    await notify({ type: 'success', title: 'Ingrediente eliminado', message: 'Se quitó de tu despensa.' })
    return true
  }

  async function sendRestockToShopping() {
    try {
      const suggestions = await mockShoppingRepository.suggestionsForRestock()
      if (suggestions.length === 0) { await notify({ type: 'info', title: 'No hay productos para reponer', message: 'Tu despensa no tiene productos pendientes de reposición.' }); return }
      await mockShoppingRepository.append(suggestions)
      navigate('/shopping')
    } catch { await notify({ type: 'error', title: 'No se pudo guardar la lista de compras', message: 'Revisá el espacio disponible del navegador e intentá de nuevo.' }) }
  }

  async function processReceipt(file: File | undefined) {
    receiptAbort.current?.abort()
    receiptAbort.current = null
    setReceiptBusy(false)
    setReceiptLines(null)
    if (!file) return
    if (!isValidReceiptImage(file)) {
      await notify({ type: 'error', title: 'Imagen no válida', message: 'Elegí una imagen JPG, PNG, WebP o HEIC de hasta 5 MB.' })
      return
    }
    setReceiptBusy(true)
    const controller = new AbortController()
    receiptAbort.current = controller
    try {
      const scanned = await mockReceiptScanner.scan(file, controller.signal)
      if (receiptAbort.current !== controller || controller.signal.aborted) return
      const examples: ReceiptLine[] = scanned.map((line) => ({ ...line, ingredientName: catalog.ingredients.find((item) => item.active && !item.isDeleted && item.name.toLocaleLowerCase('es').includes(line.name.toLocaleLowerCase('es')))?.name ?? '' }))
      setReceiptLines(examples)
    } catch {
      if (receiptAbort.current === controller && !controller.signal.aborted) await notify({ type: 'error', title: 'No se pudo procesar la imagen', message: 'Probá de nuevo.' })
    } finally { if (receiptAbort.current === controller) { receiptAbort.current = null; setReceiptBusy(false) } }
  }

  async function confirmReceipt() {
    if (!receiptLines?.length || receiptLines.some((line) => {
      const ingredient = catalog.ingredients.find((entry) => entry.active && !entry.isDeleted && entry.name === line.ingredientName)
      const base = catalog.units.find((unit) => unit.id === ingredient?.baseUnitId)
      return !ingredient || !base || !Number.isFinite(line.quantity) || line.quantity <= 0 || line.quantity > 1_000_000
        || !compatibleUnitAbbreviations(base.id, catalog.units).includes(line.unit)
    })) {
      await notify({ type: 'error', title: 'Revisá los productos detectados', message: 'Asociá cada producto con un ingrediente activo y una unidad compatible; la cantidad debe ser positiva y no superar 1.000.000.' })
      return
    }
    const additions = receiptLines.map((line): PantryItem => {
      const ingredient = catalog.ingredients.find((item) => item.active && !item.isDeleted && item.name === line.ingredientName)
      const category = catalog.categories.find((item) => item.id === ingredient?.categoryId)?.name ?? 'Otros'
      return { id: crypto.randomUUID(), ...(ingredient ? { ingredientId: ingredient.id } : {}), name: ingredient?.name ?? line.name, category, quantity: line.quantity, unit: line.unit, minimum: 0, expiry: null }
    })
    const next = [...items]
    for (const addition of additions) {
      const duplicateIndex = next.findIndex((item) => item.unit === addition.unit && normalizePantryName(item.name) === normalizePantryName(addition.name))
      if (duplicateIndex === -1) next.push(addition)
      else {
        const combined = next[duplicateIndex]!.quantity + addition.quantity
        if (combined > 1_000_000) { await notify({ type: 'error', title: 'Cantidad fuera de rango', message: 'La cantidad combinada supera el máximo permitido.' }); return }
        next[duplicateIndex] = { ...next[duplicateIndex]!, quantity: combined, ingredientId: addition.ingredientId }
      }
    }
    if (await persist(next)) { setReceiptLines(null); await notify({ type: 'success', title: 'Productos añadidos', message: 'Los productos de la factura se añadieron a la despensa.' }) }
  }

  return <div className="page pantry-page">
    <header className="page-heading pantry-heading">
      <div><p className="eyebrow">TUS INGREDIENTES</p><h1>Mi despensa</h1><p className="page-lead">Registrá cantidades y vencimientos para saber qué tenés disponible.</p></div>
      <div className="pantry-head-actions"><button className="button button-quiet" disabled={receiptBusy} onClick={() => receiptInputRef.current?.click()} type="button"><ImagePlus size={17} /> {receiptBusy ? 'Leyendo…' : 'Escanear factura'}</button><input accept="image/jpeg,image/png,image/webp,image/heic,image/heif" aria-label="Seleccionar imagen de factura" capture="environment" disabled={receiptBusy} onChange={(event) => { void processReceipt(event.currentTarget.files?.[0]); event.currentTarget.value = '' }} ref={receiptInputRef} style={{ position: 'absolute', width: 1, height: 1, padding: 0, margin: -1, overflow: 'hidden', clip: 'rect(0, 0, 0, 0)', whiteSpace: 'nowrap', border: 0 }} tabIndex={-1} type="file" /><button className="button button-quiet" onClick={() => void sendRestockToShopping()} type="button"><ShoppingCart size={17} /> Reponer</button><button className="button button-quiet" onClick={(event) => { focusBeforeDialog.current = event.currentTarget; setConfirmExamples(true) }} type="button"><ClipboardList size={17} /> Kit de ejemplo</button><button className="button button-primary" onClick={(event) => { focusBeforeDialog.current = event.currentTarget; setEditor({ id: crypto.randomUUID(), name: '', category: categories[0] ?? 'Otros', quantity: Number.NaN, unit: activeUnits(catalog)[0] ?? 'g', minimum: 0, expiry: '' }) }} ref={addButtonRef} type="button"><Plus size={18} /> Añadir ingrediente</button></div>
    </header>

    <section aria-label="Resumen de la despensa" className="pantry-summary">
      <button aria-pressed={filters.status === ''} onClick={() => setFilters(emptyFilters)} type="button"><ClipboardList aria-hidden="true" size={19} /><span>Productos</span><strong>{items.length}</strong></button>
      <button aria-pressed={filters.status === 'low'} className="pantry-summary-low" onClick={() => setFilters({ ...emptyFilters, status: 'low' })} type="button"><AlertTriangle aria-hidden="true" size={19} /><span>Stock bajo</span><strong>{alertCounts.low}</strong></button>
      <button aria-pressed={filters.status === 'expired'} className="pantry-summary-expiry" onClick={() => setFilters({ ...emptyFilters, status: 'expired' })} type="button"><CalendarClock aria-hidden="true" size={19} /><span>Vencidos</span><strong>{alertCounts.expired}</strong></button>
      <button aria-pressed={filters.status === 'soon'} className="pantry-summary-expiry" onClick={() => setFilters({ ...emptyFilters, status: 'soon' })} type="button"><CalendarClock aria-hidden="true" size={19} /><span>Por vencer</span><strong>{alertCounts.soon}</strong></button>
    </section>

    <section aria-label="Filtros de ingredientes" className="pantry-controls">
      <label className="field pantry-search"><span>Buscar por nombre</span><span className="pantry-search-input"><Search aria-hidden="true" size={17} /><input onChange={(event) => setFilters({ ...filters, search: event.currentTarget.value })} placeholder="Ej.: arroz, tomate" type="search" value={filters.search} /></span></label>
      <label className="field"><span>Categoría</span><select onChange={(event) => setFilters({ ...filters, category: event.currentTarget.value as PantryCategory | '' })} value={filters.category}><option value="">Todas</option>{categories.map((category) => <option key={category}>{category}</option>)}</select></label>
      <label className="field"><span>Estado</span><select onChange={(event) => setFilters({ ...filters, status: event.currentTarget.value as PantryStatus | '' })} value={filters.status}><option value="">Todos</option><option value="ok">Disponibles</option><option value="low">Stock bajo</option><option value="empty">Sin stock</option><option value="soon">Por vencer</option><option value="expired">Vencidos</option></select></label>
      <label className="field"><span>Ordenar por</span><select onChange={(event) => setSortOrder(event.currentTarget.value as SortOrder)} value={sortOrder}><option value="name">Nombre</option><option value="expiry">Vencimiento</option><option value="quantity">Cantidad</option></select></label>
    </section>

    <div className="pantry-results"><span><SearchFeedback resultCount={visibleItems.length} status={search.status} />{search.status === 'empty' && ` · ${visibleItems.length} ${visibleItems.length === 1 ? 'ingrediente visible' : 'ingredientes visibles'}`}</span><button disabled={!filters.search && !filters.category && !filters.status} onClick={() => setFilters(emptyFilters)} type="button">Limpiar filtros</button></div>
    {receiptBusy && <p className="form-message" role="status">Procesando imagen de muestra… <button className="button button-quiet" onClick={() => receiptAbort.current?.abort()} type="button">Cancelar lectura</button></p>}
    <p className="pantry-footnote">La lectura de facturas es una demostración local: la imagen no se sube ni se guarda. En una etapa futura, el reconocimiento se realizará mediante un servicio externo.</p>
    {receiptLines && <section aria-label="Revisar productos detectados" className="surface"><h2>Revisar productos detectados</h2><p>Verificá los datos y confirmá para agregarlos.</p>{receiptLines.map((line) => {
      const ingredient = catalog.ingredients.find((item) => item.active && !item.isDeleted && item.name === line.ingredientName)
      const base = catalog.units.find((item) => item.id === ingredient?.baseUnitId)
      const units = base ? compatibleUnitAbbreviations(base.id, catalog.units) : []
      return <div className="pantry-form-grid" key={line.id}><label className="field"><span>Producto {line.ingredientName ? '· Asociado' : '· Pendiente de revisión'}</span><input value={line.name} onChange={(event) => setReceiptLines(receiptLines.map((entry) => entry.id === line.id ? { ...entry, name: event.currentTarget.value } : entry))} /></label><label className="field"><span>Ingrediente asociado</span><select value={line.ingredientName} onChange={(event) => { const match = catalog.ingredients.find((entry) => entry.name === event.currentTarget.value); const unit = catalog.units.find((entry) => entry.id === match?.baseUnitId)?.abbreviation ?? line.unit; setReceiptLines(receiptLines.map((entry) => entry.id === line.id ? { ...entry, ingredientName: event.currentTarget.value, unit } : entry)) }}><option value="">Seleccionar ingrediente…</option>{catalog.ingredients.filter((entry) => entry.active && !entry.isDeleted).map((entry) => <option key={entry.id}>{entry.name}</option>)}</select></label><label className="field"><span>Cantidad</span><input min="0.000001" step="any" type="number" value={line.quantity} onChange={(event) => setReceiptLines(receiptLines.map((entry) => entry.id === line.id ? { ...entry, quantity: event.currentTarget.valueAsNumber } : entry))} /></label><label className="field"><span>Unidad</span><select value={line.unit} onChange={(event) => setReceiptLines(receiptLines.map((entry) => entry.id === line.id ? { ...entry, unit: event.currentTarget.value } : entry))}>{units.map((unit) => <option key={unit}>{unit}</option>)}</select></label><button className="button button-quiet" onClick={() => setReceiptLines(receiptLines.filter((entry) => entry.id !== line.id))} type="button">Omitir producto</button></div>
    })}<div className="pantry-dialog-actions"><button className="button button-quiet" onClick={() => setReceiptLines(null)} type="button">Cancelar</button><button className="button button-primary" onClick={confirmReceipt} type="button">Confirmar productos</button></div></section>}

    {pantryLoading ? <LoadingScreen message="Cargando tu despensa…" variant="section" /> : search.status !== 'waiting' && (visibleItems.length === 0 ? <section className="pantry-empty" aria-label="Despensa vacía"><ClipboardList aria-hidden="true" size={34} /><h2>{items.length ? 'Sin resultados para estos filtros' : 'Tu despensa está vacía'}</h2><p>{items.length ? 'Probá otro nombre, categoría o estado.' : 'Añadí un ingrediente o cargá el kit de ejemplo para empezar.'}</p></section> : <section aria-label="Ingredientes de la despensa" className="pantry-list">
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
    </section>)}

    <p className="pantry-footnote">Los datos se guardan en este navegador y se usan para indicar la disponibilidad de ingredientes en recetas.</p>
    {editor && <PantryEditor item={editor} items={items} catalog={catalog} categories={categories} onClose={closeDialog} onSave={saveItem} />}
    {deleting && <PantryConfirmation actionLabel="Eliminar" danger message={`¿Querés eliminar ${deleting.name} de tu despensa?`} onClose={closeDialog} onConfirm={deleteItem} title="Eliminar ingrediente" />}
    {confirmExamples && <PantryConfirmation actionLabel="Cargar ejemplos" message="Se añadirán productos de muestra sin reemplazar tus ingredientes actuales ni duplicar productos del mismo nombre y unidad." onClose={closeDialog} onConfirm={addExamples} title="Cargar kit de ejemplo" />}
  </div>
}


