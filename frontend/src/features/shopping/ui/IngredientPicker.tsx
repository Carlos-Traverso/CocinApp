import { useId, useState } from 'react'
import type { AdminIngredient } from '../../admin/domain/adminModels'
import { normalizePantryName } from '../../pantry/domain/pantry'
import { useDebouncedSearch } from '../../../shared/search/useDebouncedSearch'

interface IngredientPickerProps {
  ingredients: AdminIngredient[]
  value: string
  disabled: boolean
  onChange: (ingredient?: AdminIngredient) => void
}

export function IngredientPicker({ ingredients, value, disabled, onChange }: IngredientPickerProps) {
  const listId = useId()
  const [search, setSearch] = useState<string | null>(null)
  const [open, setOpen] = useState(false)
  const [activeIndex, setActiveIndex] = useState(-1)
  const sorted = ingredients.filter((ingredient) => ingredient.active && !ingredient.isDeleted)
    .sort((a, b) => a.name.localeCompare(b.name, 'es', { sensitivity: 'base' }))
  const selected = sorted.find((ingredient) => ingredient.id === value)
  const text = search ?? selected?.name ?? ''
  const debounced = useDebouncedSearch(search ?? '')
  const query = normalizePantryName(debounced.query)
  const waiting = debounced.status === 'waiting'
  const matches = waiting ? [] : sorted.filter((ingredient) => normalizePantryName(ingredient.name).startsWith(query))
  const options: (AdminIngredient | undefined)[] = waiting ? [] : [undefined, ...matches]
  const expanded = open && !disabled

  function choose(ingredient?: AdminIngredient) {
    onChange(ingredient)
    setSearch(null)
    setOpen(false)
    setActiveIndex(-1)
  }

  return <div className="shopping-ingredient-picker">
    <label className="field"><span>Asociar a ingrediente de catálogo (opcional)</span>
      <input disabled={disabled} type="text" autoComplete="off" placeholder="Escribí para buscar, ej.: Ce…" value={text}
        role="combobox" aria-autocomplete="list" aria-expanded={expanded} aria-controls={listId}
        aria-activedescendant={expanded && activeIndex >= 0 && activeIndex < options.length ? `${listId}-${activeIndex}` : undefined}
        onFocus={() => { setOpen(true); setActiveIndex(-1) }}
        onBlur={() => { setOpen(false); setSearch(null); setActiveIndex(-1) }}
        onChange={(event) => {
          setSearch(event.currentTarget.value)
          setOpen(true)
          setActiveIndex(-1)
          if (value) onChange(undefined)
        }}
        onKeyDown={(event) => {
          if (event.key === 'Escape') { event.preventDefault(); setOpen(false); setSearch(null); setActiveIndex(-1) }
          if (event.key === 'ArrowDown' || event.key === 'ArrowUp') {
            event.preventDefault()
            setOpen(true)
            setActiveIndex((index) => {
              if (!options.length) return -1
              if (index < 0) return event.key === 'ArrowDown' ? 0 : options.length - 1
              return (index + (event.key === 'ArrowDown' ? 1 : -1) + options.length) % options.length
            })
          }
          if (event.key === 'Enter') {
            event.preventDefault()
            if (expanded && activeIndex >= 0 && activeIndex < options.length) choose(options[activeIndex])
          }
        }} />
    </label>
    {expanded && <div className="shopping-ingredient-dropdown">
      <ul id={listId} role="listbox" aria-label="Ingredientes del catálogo">
        {options.map((ingredient, index) => <li key={ingredient?.id ?? 'none'} id={`${listId}-${index}`}
          role="option" aria-selected={ingredient ? ingredient.id === value : !value}
          className={activeIndex === index ? 'active' : undefined}
          onMouseDown={(event) => event.preventDefault()} onClick={() => choose(ingredient)}>
          {ingredient?.name ?? 'Artículo propio (sin asociación)'}
        </li>)}
      </ul>
      <p className="shopping-picker-help" role="status">{waiting ? 'Buscando…' : matches.length === 0
        ? 'No hay ingredientes que comiencen así.'
        : `${matches.length} ${matches.length === 1 ? 'coincidencia' : 'coincidencias'}`}</p>
    </div>}
  </div>
}
