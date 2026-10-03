import { useEffect, useState } from 'react'
import { ArrowRight, Clock3, Heart, Search, UsersRound } from 'lucide-react'
import { Link, useLocation, useNavigate } from 'react-router-dom'
import { readPantryItems } from '../features/pantry/data/localPantryStore'
import { readFavoriteIds, writeFavoriteIds } from '../features/recipes/data/localFavoritesStore'
import { filterRecipes, getIngredientAvailability, type RecipeFilters } from '../features/recipes/domain/recipeRules'
import { getAvailableRecipes } from '../features/recipes/data/availableRecipes'
import { meals } from '../features/planner/domain/planner'
import type { Recipe } from '../features/recipes/domain/Recipe'
import { RecipeImage } from '../features/recipes/ui/RecipeImage'
import { SearchFeedback } from '../shared/search/SearchFeedback'
import { useDebouncedSearch } from '../shared/search/useDebouncedSearch'

const initialFilters: RecipeFilters = { search: '', category: '', maxMinutes: null, difficulty: '', pantryOnly: false }

function RecipeArtwork({ recipe, size = 'card' }: { recipe: Recipe; size?: 'hero' | 'card' | 'mini' }) {
  return <RecipeImage className={`recipe-artwork recipe-artwork-${size}`} loading={size === 'hero' ? 'eager' : 'lazy'} recipe={recipe} />
}

export function RecipesPage({ favoritesOnly = false }: { favoritesOnly?: boolean }) {
  const location = useLocation()
  const navigate = useNavigate()
  const { hash } = location
  const [filters, setFilters] = useState<RecipeFilters>(initialFilters)
  const [pantry] = useState(readPantryItems)
  const [favoriteIds, setFavoriteIds] = useState(readFavoriteIds)
  const [error, setError] = useState('')
  const [completionNotice, setCompletionNotice] = useState(() => {
    const state = location.state as { completionMessage?: unknown } | null
    return typeof state?.completionMessage === 'string' ? state.completionMessage : ''
  })
  const search = useDebouncedSearch(filters.search)
  const activeRecipes = getAvailableRecipes()
  const catalog = activeRecipes
  const recipes = (search.status === 'waiting' ? [] : filterRecipes(catalog, { ...filters, search: search.query }, pantry))
    .filter((recipe) => !favoritesOnly || favoriteIds.includes(recipe.id))
  const activeIds = new Set(activeRecipes.map((recipe) => recipe.id))

  useEffect(() => {
    if (hash) document.getElementById(hash.slice(1))?.scrollIntoView()
  }, [hash])

  useEffect(() => {
    if (!completionNotice) return
    navigate(`${location.pathname}${location.hash}`, { replace: true, state: null })
    const timeout = window.setTimeout(() => setCompletionNotice(''), 5000)
    return () => window.clearTimeout(timeout)
  }, [completionNotice, location.hash, location.pathname, navigate])

  function toggleFavorite(id: string) {
    const next = favoriteIds.includes(id) ? favoriteIds.filter((item) => item !== id) : [...favoriteIds, id]
    try { writeFavoriteIds(next); setFavoriteIds(next); setError('') }
    catch { setError('No se pudo guardar el favorito en este navegador.') }
  }

  return <div className="page recipes-page">
    {completionNotice && <p className="form-message pantry-notice" role="status">{completionNotice}</p>}
    {favoritesOnly ? <header className="page-heading"><div><p className="eyebrow">RECETAS GUARDADAS</p><h1>Tus favoritas</h1><p className="page-lead">Tus recetas preferidas, guardadas en este navegador.</p></div><Link className="button button-quiet" to="/recipes">Explorar recetas</Link></header> : <header className="page-heading"><div><p className="eyebrow">RECETARIO COCINAPP</p><h1>Recetas</h1><p className="page-lead">Buscá, filtrá y consultá todas las recetas disponibles.</p></div></header>}

    <section aria-labelledby="recipe-catalog-title" className="recipe-catalog" id="recipe-catalog">
      <div className="recipe-catalog-heading"><div><p className="eyebrow">{favoritesOnly ? 'TU COLECCIÓN' : 'TODAS LAS OPCIONES'}</p><h2 id="recipe-catalog-title">{favoritesOnly ? 'Todas tus favoritas' : 'Explorá el catálogo'}</h2></div><SearchFeedback resultCount={recipes.length} status={search.status} /></div>
      <div aria-label="Filtros de recetas" className="recipe-controls with-search">
        <label className="field"><span>Buscar receta o ingrediente</span><span className="pantry-search-input"><Search aria-hidden="true" size={17} /><input onChange={(event) => setFilters({ ...filters, search: event.currentTarget.value })} placeholder="Ej.: quinoa, calabaza" type="search" value={filters.search} /></span></label>
        <label className="field"><span>Categoría</span><select onChange={(event) => setFilters({ ...filters, category: event.currentTarget.value })} value={filters.category}><option value="">Todas</option>{meals.map((meal) => <option key={meal}>{meal}</option>)}</select></label>
        <label className="field"><span>Tiempo máximo</span><select onChange={(event) => setFilters({ ...filters, maxMinutes: event.currentTarget.value ? Number(event.currentTarget.value) : null })} value={filters.maxMinutes ?? ''}><option value="">Cualquiera</option><option value="20">20 min</option><option value="30">30 min</option><option value="60">60 min</option></select></label>
        <label className="field"><span>Dificultad</span><select onChange={(event) => setFilters({ ...filters, difficulty: event.currentTarget.value as RecipeFilters['difficulty'] })} value={filters.difficulty}><option value="">Todas</option><option>Fácil</option><option>Intermedia</option><option>Avanzada</option></select></label>
      </div>
      <div className="recipe-filter-footer"><label className="recipe-pantry-toggle"><input checked={filters.pantryOnly} onChange={(event) => setFilters({ ...filters, pantryOnly: event.currentTarget.checked })} type="checkbox" /> Puedo cocinar con mi despensa</label><button onClick={() => setFilters(initialFilters)} type="button">Limpiar filtros</button></div>
    </section>
    {error && <p className="form-message error" role="alert">{error}</p>}
    {search.status !== 'waiting' && (recipes.length === 0 ? <section className="pantry-empty"><h2>{favoritesOnly && favoriteIds.length === 0 ? 'Todavía no guardaste recetas' : 'No encontramos recetas'}</h2><p>{favoritesOnly && favoriteIds.length === 0 ? 'Explorá el catálogo y tocá el corazón de una receta.' : 'Probá otros filtros o agregá ingredientes a tu despensa.'}</p></section> : <section aria-label="Listado de recetas" className="recipe-grid">
      {recipes.map((recipe) => {
        const availability = getIngredientAvailability(recipe, pantry)
        const favorite = favoriteIds.includes(recipe.id)
        return <article className="recipe-card" key={recipe.id}><RecipeArtwork recipe={recipe} /><div className="recipe-body"><div className="recipe-card-top"><span className="recipe-category">{recipe.category}</span><button aria-label={`${favorite ? 'Quitar' : 'Agregar'} ${recipe.name} ${favorite ? 'de' : 'a'} favoritos`} aria-pressed={favorite} className="recipe-favorite" onClick={() => toggleFavorite(recipe.id)} type="button"><Heart fill={favorite ? 'currentColor' : 'none'} size={19} /></button></div><h2><Link to={`/recipes/${recipe.id}`}>{recipe.name}</Link></h2><p>{recipe.description}</p>{!activeIds.has(recipe.id) && <p className="form-message">Receta inactiva: disponible solo para consulta.</p>}<div className="recipe-meta"><span><Clock3 size={15} /> {recipe.minutes} min</span><span><UsersRound size={15} /> {recipe.portions} porciones</span><span>{recipe.difficulty}</span></div><p className={`recipe-availability ${availability.missing.length === 0 ? 'complete' : ''}`}>{availability.missing.length === 0 ? 'Lista con tu despensa' : `${availability.available.length} de ${recipe.ingredients.length} ingredientes`}</p><Link className="recipe-card-link" to={`/recipes/${recipe.id}`}>Ver receta <ArrowRight aria-hidden="true" size={16} /></Link></div></article>
      })}
    </section>)}
  </div>
}
