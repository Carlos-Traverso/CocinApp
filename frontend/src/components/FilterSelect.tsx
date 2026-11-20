import { useEffect, useId, useRef, useState } from 'react'
import { Check, ChevronDown, X } from 'lucide-react'
import './FilterSelect.css'

export interface FilterOption {
  value: string
  label: string
}

interface Props {
  label: string
  value: string
  options: FilterOption[]
  onChange: (value: string) => void
}

export function FilterSelect({ label, value, options, onChange }: Props) {
  const id = useId()
  const [open, setOpen] = useState(false)
  const dialog = useRef<HTMLDialogElement>(null)
  const trigger = useRef<HTMLButtonElement>(null)
  const selected = options.find((option) => option.value === value)

  useEffect(() => {
    if (!open) return
    const node = dialog.current
    const returnFocus = trigger.current
    node?.showModal()
    node?.querySelector<HTMLButtonElement>('[aria-pressed="true"]')?.focus()
    return () => {
      node?.close()
      returnFocus?.focus()
    }
  }, [open])

  return <div className="field filter-select">
    <label className="filter-select-native" htmlFor={id}><span>{label}</span><select id={id} onChange={(event) => onChange(event.currentTarget.value)} value={value}>{options.map((option) => <option key={option.value} value={option.value}>{option.label}</option>)}</select></label>
    <div className="filter-select-mobile">
      <span id={`${id}-label`}>{label}</span>
      <button aria-expanded={open} aria-haspopup="dialog" aria-labelledby={`${id}-label ${id}-value`} className="filter-select-trigger" onClick={() => setOpen(true)} ref={trigger} type="button"><span id={`${id}-value`}>{selected?.label ?? ''}</span><ChevronDown aria-hidden="true" size={18} /></button>
    </div>
    {open && <dialog aria-labelledby={`${id}-title`} className="filter-select-dialog" onCancel={() => setOpen(false)} onClick={(event) => { if (event.target === event.currentTarget) setOpen(false) }} ref={dialog}>
      <div className="filter-select-panel">
        <header><h2 id={`${id}-title`}>{label}</h2><button aria-label="Cerrar opciones" className="filter-select-close" onClick={() => setOpen(false)} type="button"><X aria-hidden="true" size={20} /></button></header>
        <div className="filter-select-options">{options.map((option) => <button aria-pressed={value === option.value} className="filter-select-option" key={option.value} onClick={() => { onChange(option.value); setOpen(false) }} type="button"><span>{option.label}</span>{value === option.value && <Check aria-hidden="true" size={18} />}</button>)}</div>
      </div>
    </dialog>}
  </div>
}
