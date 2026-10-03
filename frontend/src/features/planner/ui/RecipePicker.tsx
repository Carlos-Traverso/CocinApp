import { useEffect, useId, useRef, useState } from 'react'
import { Search, X } from 'lucide-react'
import type { Recipe } from '../../recipes/domain/Recipe'
import { nextPlanRecipeIndex, planRecipeKeyAction, searchPlanRecipes } from '../domain/recipeSearch'
import { RecipeImage } from '../../recipes/ui/RecipeImage'
import { searchFeedback } from '../../../shared/search/debouncedSearch'
import { useDebouncedSearch } from '../../../shared/search/useDebouncedSearch'

interface Props {
  title: string
  recipes: Recipe[]
  onSelect: (id: string) => void
  onClose: () => void
  selectedId?: string
}

export function RecipePicker({ title, recipes, onSelect, onClose, selectedId }: Props) {
  const dialog = useRef<HTMLDialogElement>(null)
  const input = useRef<HTMLInputElement>(null)
  const listId = useId()
  const [query, setQuery] = useState('')
  const [active, setActive] = useState(0)
  const search = useDebouncedSearch(query)
  const results = search.status === 'ready' ? searchPlanRecipes(recipes, search.query) : []

  useEffect(() => {
    const previousFocus = document.activeElement instanceof HTMLElement ? document.activeElement : null
    const node = dialog.current
    node?.showModal()
    input.current?.focus()
    return () => { node?.close(); previousFocus?.focus() }
  }, [])

  function choose(index: number) {
    const recipe = results[index]
    if (recipe) {
      setQuery('')
      onSelect(recipe.id)
    }
  }

  return <dialog aria-labelledby={`${listId}-title`} className="recipe-picker surface" onCancel={onClose} ref={dialog}>
    <div className="shopping-editor-heading"><h2 id={`${listId}-title`}>{title}</h2><button aria-label="Cerrar buscador" className="pantry-icon-button" onClick={onClose} type="button"><X size={19} /></button></div>
    <p>Escribí el nombre de una receta y elegí una coincidencia.</p>
    <label className="field" htmlFor={`${listId}-search`}>Buscar receta</label>
    <div className="recipe-picker-search"><Search aria-hidden="true" size={18} /><input aria-activedescendant={results[active] ? `${listId}-option-${active}` : undefined} aria-autocomplete="list" aria-controls={`${listId}-results`} aria-expanded={search.status === 'ready' && results.length > 0} autoComplete="off" id={`${listId}-search`} onChange={(event) => { setQuery(event.currentTarget.value); setActive(0) }} onKeyDown={(event) => {
      const action = planRecipeKeyAction(event.key)
      if (!action) return
      event.preventDefault()
      if (action === 'next' || action === 'previous') setActive((current) => nextPlanRecipeIndex(current, results.length, action))
      if (action === 'select') choose(active)
      if (action === 'close') onClose()
    }} placeholder="Ej.: arroz" ref={input} role="combobox" type="search" value={query} />{query && <button aria-label="Limpiar búsqueda" onClick={() => { setQuery(''); setActive(0); input.current?.focus() }} type="button"><X size={17} /></button>}</div>
    <p aria-live="polite" className="recipe-picker-count" role="status">{searchFeedback(search.status, results.length)}</p>
    <div className="recipe-picker-results" id={`${listId}-results`} role="listbox">
      {search.status === 'ready' && results.length ? results.map((recipe, index) => {
        const isCurrent = recipe.id === selectedId
        return <button aria-selected={active === index} className={`recipe-picker-option${active === index ? ' active' : ''}${isCurrent ? ' current' : ''}`} id={`${listId}-option-${index}`} key={recipe.id} onClick={() => choose(index)} onMouseEnter={() => setActive(index)} role="option" type="button"><RecipeImage className="recipe-picker-thumb" recipe={recipe} /><span><strong>{recipe.name}</strong><small>{recipe.category} · {recipe.minutes} min · {recipe.difficulty}</small>{isCurrent && <em className="recipe-picker-current">Planificada actualmente</em>}</span></button>
      }) : search.status === 'ready' && <p className="recipe-picker-empty">No encontramos recetas con ese nombre. Probá otra búsqueda.</p>}
    </div>
  </dialog>
}
