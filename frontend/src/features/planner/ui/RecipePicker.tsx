import { useEffect, useId, useRef, useState } from 'react'
import { Search, X } from 'lucide-react'
import type { Recipe } from '../../recipes/domain/Recipe'
import { searchPlanRecipes } from '../domain/recipeSearch'

interface Props {
  title: string
  recipes: Recipe[]
  onSelect: (id: string) => void
  onClose: () => void
}

export function RecipePicker({ title, recipes, onSelect, onClose }: Props) {
  const dialog = useRef<HTMLDialogElement>(null)
  const input = useRef<HTMLInputElement>(null)
  const listId = useId()
  const [query, setQuery] = useState('')
  const [active, setActive] = useState(0)
  const results = searchPlanRecipes(recipes, query)

  useEffect(() => {
    const previousFocus = document.activeElement instanceof HTMLElement ? document.activeElement : null
    const node = dialog.current
    node?.showModal()
    input.current?.focus()
    return () => { node?.close(); previousFocus?.focus() }
  }, [])

  function choose(index: number) {
    const recipe = results[index]
    if (recipe) onSelect(recipe.id)
  }

  return <dialog aria-labelledby={`${listId}-title`} className="recipe-picker surface" onCancel={onClose} ref={dialog}>
    <div className="shopping-editor-heading"><h2 id={`${listId}-title`}>{title}</h2><button aria-label="Cerrar buscador" className="pantry-icon-button" onClick={onClose} type="button"><X size={19} /></button></div>
    <p>Escribí el nombre de una receta y elegí una coincidencia.</p>
    <label className="field" htmlFor={`${listId}-search`}>Buscar receta</label>
    <div className="recipe-picker-search"><Search aria-hidden="true" size={18} /><input aria-activedescendant={results[active] ? `${listId}-option-${active}` : undefined} aria-autocomplete="list" aria-controls={`${listId}-results`} aria-expanded="true" autoComplete="off" id={`${listId}-search`} onChange={(event) => { setQuery(event.currentTarget.value); setActive(0) }} onKeyDown={(event) => {
      if (event.key === 'ArrowDown') { event.preventDefault(); setActive((current) => Math.min(current + 1, results.length - 1)) }
      if (event.key === 'ArrowUp') { event.preventDefault(); setActive((current) => Math.max(current - 1, 0)) }
      if (event.key === 'Enter') { event.preventDefault(); choose(active) }
      if (event.key === 'Escape') { event.preventDefault(); onClose() }
    }} placeholder="Ej.: arroz" ref={input} role="combobox" type="search" value={query} />{query && <button aria-label="Limpiar búsqueda" onClick={() => { setQuery(''); setActive(0); input.current?.focus() }} type="button"><X size={17} /></button>}</div>
    <p aria-live="polite" className="recipe-picker-count">{results.length} {results.length === 1 ? 'receta' : 'recetas'}</p>
    <div className="recipe-picker-results" id={`${listId}-results`} role="listbox">
      {results.length ? results.map((recipe, index) => <button aria-selected={active === index} className={`recipe-picker-option${active === index ? ' active' : ''}`} id={`${listId}-option-${index}`} key={recipe.id} onClick={() => choose(index)} onMouseEnter={() => setActive(index)} role="option" type="button"><span aria-hidden="true" className={`recipe-picker-thumb ${recipe.color}`}>{recipe.symbol}</span><span><strong>{recipe.name}</strong><small>{recipe.category} · {recipe.minutes} min · {recipe.difficulty}</small></span></button>) : <p className="recipe-picker-empty">No encontramos recetas con ese nombre. Probá otra búsqueda.</p>}
    </div>
  </dialog>
}
