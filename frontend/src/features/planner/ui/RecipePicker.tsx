import { useEffect, useId, useRef, useState } from 'react'
import { Search, X } from 'lucide-react'
import type { Recipe } from '../../recipes/domain/Recipe'
import { recipeMealShifts } from '../../recipes/domain/recipeRules'
import { nextPlanRecipeIndex, planRecipeKeyAction, recipesForMeal, searchPlanRecipes, suggestedPlanRecipes } from '../domain/recipeSearch'
import { meals, type Meal } from '../domain/planner'
import { RecipeImage } from '../../recipes/ui/RecipeImage'
import { searchFeedback } from '../../../shared/search/debouncedSearch'
import { useDebouncedSearch } from '../../../shared/search/useDebouncedSearch'

interface Props {
  title: string
  meal: Meal
  recipes: Recipe[]
  onSelect: (id: string, portions: number) => Promise<boolean>
  onClose: () => void
  selectedId?: string
  selectedPortions?: number
}

export function RecipePicker({ title, meal, recipes, onSelect, onClose, selectedId, selectedPortions }: Props) {
  const dialog = useRef<HTMLDialogElement>(null)
  const input = useRef<HTMLInputElement>(null)
  const portionsInput = useRef<HTMLInputElement>(null)
  const listId = useId()
  const [query, setQuery] = useState('')
  const [active, setActive] = useState(0)
  const [filterMeal, setFilterMeal] = useState<Meal>(meal)
  const [candidateId, setCandidateId] = useState(selectedId ?? '')
  const [portions, setPortions] = useState(String(selectedPortions ?? recipes.find((recipe) => recipe.id === selectedId)?.portions ?? 2))
  const [portionInvalid, setPortionInvalid] = useState(false)
  const [saving, setSaving] = useState(false)
  const search = useDebouncedSearch(query)
  const compatibleRecipes = recipesForMeal(recipes, filterMeal)
  const suggestions = suggestedPlanRecipes(recipes, filterMeal)
  const results = search.status === 'empty' ? suggestions : search.status === 'ready' ? searchPlanRecipes(compatibleRecipes, search.query) : []
  const candidate = recipes.find((recipe) => recipe.id === candidateId)

  useEffect(() => {
    const previousFocus = document.activeElement instanceof HTMLElement ? document.activeElement : null
    const node = dialog.current
    node?.showModal()
    if (portionsInput.current) portionsInput.current.focus()
    else input.current?.focus()
    return () => { node?.close(); previousFocus?.focus() }
  }, [])

  function choose(index: number) {
    const recipe = results[index]
    if (recipe) {
      setCandidateId(recipe.id)
      setPortions(String(recipe.id === selectedId ? selectedPortions ?? recipe.portions : recipe.portions))
      setPortionInvalid(false)
      requestAnimationFrame(() => portionsInput.current?.focus())
    }
  }

  function chooseAnotherRecipe() {
    setCandidateId('')
    setPortions('2')
    setPortionInvalid(false)
    setQuery('')
    setActive(0)
    requestAnimationFrame(() => input.current?.focus())
  }

  async function confirmSelection() {
    const value = Number(portions)
    if (!Number.isInteger(value) || value < 1 || value > 20) {
      setPortionInvalid(true)
      portionsInput.current?.focus()
      return
    }
    if (!candidateId || saving) return
    setSaving(true)
    try {
      if (await onSelect(candidateId, value)) onClose()
    } finally {
      setSaving(false)
    }
  }

  return <dialog aria-labelledby={`${listId}-title`} className="recipe-picker surface" onCancel={onClose} ref={dialog}>
    <div className="shopping-editor-heading"><h2 id={`${listId}-title`}>{title}</h2><button aria-label="Cerrar buscador" className="pantry-icon-button" onClick={onClose} type="button"><X size={19} /></button></div>
    {candidate ? <>
      <div aria-label={`Receta elegida: ${candidate.name}`} className="recipe-picker-option current">
        <RecipeImage className="recipe-picker-thumb" recipe={candidate} />
        <span><strong>{candidate.name}</strong><small>{recipeMealShifts(candidate).join(' · ')} · {candidate.minutes} min · {candidate.difficulty}</small></span>
      </div>
      <button className="button button-quiet" disabled={saving} onClick={chooseAnotherRecipe} type="button">Elegir otra receta</button>
    </> : <>
      <p>Podés elegir una receta de otro turno; la comida planificada seguirá siendo {meal.toLocaleLowerCase('es-AR')}.</p>
      <div aria-label="Filtrar recetas por turno" className="recipe-picker-meal-filters">
        {meals.map((option) => <button aria-pressed={filterMeal === option} className="button button-quiet" key={option} onClick={() => { setFilterMeal(option); setActive(0) }} type="button">{option}</button>)}
      </div>
      <label className="field" htmlFor={`${listId}-search`}>Buscar receta</label>
      <div className="recipe-picker-search"><Search aria-hidden="true" size={18} /><input aria-activedescendant={results[active] ? `${listId}-option-${active}` : undefined} aria-autocomplete="list" aria-controls={`${listId}-results`} aria-expanded={search.status !== 'waiting' && results.length > 0} autoComplete="off" id={`${listId}-search`} onChange={(event) => { setQuery(event.currentTarget.value); setActive(0) }} onKeyDown={(event) => {
        const action = planRecipeKeyAction(event.key)
        if (!action) return
        event.preventDefault()
        if (action === 'next' || action === 'previous') setActive((current) => nextPlanRecipeIndex(current, results.length, action))
        if (action === 'select') choose(active)
        if (action === 'close') onClose()
      }} placeholder="Ej.: arroz" ref={input} role="combobox" type="search" value={query} />{query && <button aria-label="Limpiar búsqueda" onClick={() => { setQuery(''); setActive(0); input.current?.focus() }} type="button"><X size={17} /></button>}</div>
      <p aria-live="polite" className="recipe-picker-count" role="status">{search.query ? searchFeedback(search.status, results.length) : `${suggestions.length} recetas sugeridas para ${filterMeal.toLocaleLowerCase('es-AR')}`}</p>
      <div className="recipe-picker-results" id={`${listId}-results`} role="listbox" aria-label="Recetas disponibles">
        {search.status !== 'waiting' && results.length ? results.map((recipe, index) => {
          const isCurrent = recipe.id === selectedId
          return <button aria-selected={recipe.id === candidateId} className={`recipe-picker-option${active === index ? ' active' : ''}${isCurrent ? ' current' : ''}`} id={`${listId}-option-${index}`} key={recipe.id} onClick={() => choose(index)} onMouseEnter={() => setActive(index)} role="option" type="button"><RecipeImage className="recipe-picker-thumb" recipe={recipe} /><span><strong>{recipe.name}</strong><small>{recipeMealShifts(recipe).join(' · ')} · {recipe.minutes} min · {recipe.difficulty}</small>{isCurrent && <em className="recipe-picker-current">Planificada actualmente</em>}</span></button>
        }) : search.status !== 'waiting' && (search.query ? <p className="recipe-picker-empty">No encontramos recetas con ese nombre para {filterMeal.toLocaleLowerCase('es-AR')}. Probá otra búsqueda o elegí otro turno.</p> : <p className="recipe-picker-empty">No hay recetas disponibles para {filterMeal.toLocaleLowerCase('es-AR')}.</p>)}
      </div>
    </>}
    {candidate && <>
      <label className="field" htmlFor={`${listId}-portions`}>Cantidad de porciones<input aria-describedby={portionInvalid ? `${listId}-portions-error` : undefined} aria-invalid={portionInvalid} disabled={saving} id={`${listId}-portions`} max="20" min="1" onChange={(event) => { setPortions(event.currentTarget.value); setPortionInvalid(false) }} ref={portionsInput} step="1" type="number" value={portions} />{portionInvalid && <span className="form-message error" id={`${listId}-portions-error`} role="alert">Elegí un número entero entre 1 y 20.</span>}</label>
      <button className="button button-primary" disabled={saving} onClick={() => void confirmSelection()} type="button">{saving ? 'Guardando…' : 'Planificar receta'}</button>
    </>}
  </dialog>
}
