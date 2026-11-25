import { LoadingScreen } from '../components/LoadingScreen'
import { FilterSelect } from '../components/FilterSelect'
import { useEffect, useLayoutEffect, useMemo, useRef, useState } from 'react'
import { ArrowRight, Clock3, Heart, Search, UsersRound } from 'lucide-react'
import { Link, useLocation, useNavigate } from 'react-router-dom'
import { getPantryItems } from '../features/pantry/data/localPantryStore'
import { favoriteRepository } from '../features/recipes/data/localFavoritesStore'
import { recipeMealShifts, type RecipeFilters } from '../features/recipes/domain/recipeRules'
import { recipeRepository } from '../features/recipes/data/recipeData'
import { meals } from '../features/planner/domain/planner'
import type { Recipe } from '../features/recipes/domain/Recipe'
import { RecipeImage } from '../features/recipes/ui/RecipeImage'
import { SearchFeedback } from '../shared/search/SearchFeedback'
import { useDebouncedSearch } from '../shared/search/useDebouncedSearch'
import type { DietaryPreference } from '../features/profile/domain/profile'
import { useNotifications } from '../shared/notifications/NotificationProvider'
import { scrollBehavior } from '../components/scrollToTop'

const initialFilters: RecipeFilters = { search: '', category: '', maxMinutes: null, difficulty: '', pantryOnly: false }
const dietOptions: Array<{ id: DietaryPreference; label: string }> = [
  { id: 'gluten-free', label: 'Sin TACC' }, { id: 'vegetarian', label: 'Vegetariana' }, { id: 'vegan', label: 'Vegana' },
  { id: 'lactose-free', label: 'Sin lactosa' }, { id: 'nut-free', label: 'Sin frutos secos' },
]
const recipesPerPage = 12
type RecipeMatches = Awaited<ReturnType<typeof recipeRepository.match>>
type MatchResult = { filters: RecipeFilters } & (
  { status: 'ready'; matches: RecipeMatches } | { status: 'error' }
)

function scrollToFirstRecipe(recipe: HTMLElement | null) {
  if (!recipe) return
  recipe.focus({ preventScroll: true })
  recipe.scrollIntoView({ behavior: scrollBehavior(window.matchMedia('(prefers-reduced-motion: reduce)').matches), block: 'start' })
}

function RecipePagination({ currentPage, pageCount, onPageChange, position }: { currentPage: number; pageCount: number; onPageChange: (page: number) => void; position: 'superior' | 'inferior' }) {
  if (pageCount <= 1) return null

  return <nav aria-label={`Paginación ${position} de recetas`} className="recipe-pagination">
    <button disabled={currentPage === 1} onClick={() => onPageChange(currentPage - 1)} type="button">Anterior</button>
    <div className="recipe-pagination-pages">
      {Array.from({ length: pageCount }, (_, index) => index + 1).map((page) => <button aria-current={page === currentPage ? 'page' : undefined} aria-label={`Ir a la página ${page}`} className={page === currentPage ? 'active' : undefined} key={page} onClick={() => onPageChange(page)} type="button">{page}</button>)}
    </div>
    <button disabled={currentPage === pageCount} onClick={() => onPageChange(currentPage + 1)} type="button">Siguiente</button>
  </nav>
}

function RecipeArtwork({ recipe, size = 'card' }: { recipe: Recipe; size?: 'hero' | 'card' | 'mini' }) {
  return <RecipeImage className={`recipe-artwork recipe-artwork-${size}`} loading={size === 'hero' ? 'eager' : 'lazy'} recipe={recipe} />
}

export function RecipesPage({ favoritesOnly = false }: { favoritesOnly?: boolean }) {
  const location = useLocation()
  const navigate = useNavigate()
  const { hash } = location
  const { notify } = useNotifications()
  const [filters, setFilters] = useState<RecipeFilters>(initialFilters)
  const [pantry, setPantry] = useState<Awaited<ReturnType<typeof getPantryItems>>>([])
  const [favoriteIds, setFavoriteIds] = useState<string[]>([])
  const [activePreferences, setActivePreferences] = useState<DietaryPreference[]>([])
  const [catalogCount, setCatalogCount] = useState(0)
  const [matchResult, setMatchResult] = useState<MatchResult | null>(null)
  const [loadingInputs, setLoadingInputs] = useState(true)
  const [loadFailed, setLoadFailed] = useState(false)
  const [loadAttempt, setLoadAttempt] = useState(0)
  const [requestedPage, setRequestedPage] = useState(1)
  const firstRecipeRef = useRef<HTMLElement | null>(null)
  const pendingPageScrollRef = useRef<number | null>(null)
  const [completionNotice] = useState(() => {
    const state = location.state as { completionMessage?: unknown } | null
    return typeof state?.completionMessage === 'string' ? state.completionMessage : ''
  })
  const search = useDebouncedSearch(filters.search)
  const selectedDiet = filters.preferences ?? []
  const matchFilters = useMemo(() => ({
    ...filters,
    search: search.query,
    preferences: [...new Set([...activePreferences, ...(filters.preferences ?? [])])],
  }), [activePreferences, filters, search.query])
  const currentResult = search.status !== 'waiting' && matchResult?.filters === matchFilters ? matchResult : null
  const failed = loadFailed || currentResult?.status === 'error'
  const loading = !failed && (loadingInputs || !currentResult)
  const visibleMatches = (currentResult?.status === 'ready' ? currentResult.matches : [])
    .filter(({ recipe }) => !favoritesOnly || favoriteIds.includes(recipe.id))
  const pageCount = Math.ceil(visibleMatches.length / recipesPerPage)
  const currentPage = Math.min(requestedPage, Math.max(1, pageCount))
  const pageMatches = visibleMatches.slice((currentPage - 1) * recipesPerPage, currentPage * recipesPerPage)
  const candidateCount = favoritesOnly ? Math.min(catalogCount, favoriteIds.length) : catalogCount

  useLayoutEffect(() => {
    if (pendingPageScrollRef.current !== currentPage) return
    pendingPageScrollRef.current = null
    scrollToFirstRecipe(firstRecipeRef.current)
  }, [currentPage])

  function changePage(page: number) {
    if (page === currentPage) {
      scrollToFirstRecipe(firstRecipeRef.current)
      return
    }
    pendingPageScrollRef.current = page
    setRequestedPage(page)
  }

  function updateFilters(next: Parameters<typeof setFilters>[0]) {
    pendingPageScrollRef.current = null
    setRequestedPage(1)
    setFilters(next)
  }

  useEffect(() => {
    let current = true
    void Promise.all([recipeRepository.list(), getPantryItems(), favoriteRepository.listIds(), recipeRepository.getDietaryPreferences()])
      .then(([catalog, stock, favorites, preferences]) => { if (current) { setCatalogCount(catalog.length); setPantry(stock); setFavoriteIds(favorites); setActivePreferences(preferences) } })
      .catch(() => { if (current) { setLoadFailed(true); void notify({ type: 'error', title: 'No se pudieron cargar las recetas', message: 'Intentá de nuevo.' }) } })
      .finally(() => { if (current) setLoadingInputs(false) })
    return () => { current = false }
  }, [loadAttempt, notify])

  useEffect(() => {
    if (loadingInputs || loadFailed || search.status === 'waiting') return
    let current = true
    void recipeRepository.match(pantry, matchFilters)
      .then((matches) => { if (current) setMatchResult({ filters: matchFilters, status: 'ready', matches }) })
      .catch(() => {
        if (!current) return
        setMatchResult({ filters: matchFilters, status: 'error' })
        void notify({ type: 'error', title: 'No se pudieron filtrar las recetas', message: 'Intentá de nuevo.' })
      })
    return () => { current = false }
  }, [loadingInputs, loadFailed, pantry, matchFilters, search.status, notify])

  function retryLoad() {
    setLoadingInputs(true)
    setLoadFailed(false)
    setMatchResult(null)
    setLoadAttempt((attempt) => attempt + 1)
  }

  useEffect(() => {
    if (hash) document.getElementById(hash.slice(1))?.scrollIntoView()
  }, [hash])

  useEffect(() => {
    if (!completionNotice) return
    navigate(`${location.pathname}${location.hash}`, { replace: true, state: null })
    void notify({ type: 'success', title: 'Preparación finalizada', message: completionNotice })
  }, [completionNotice, location.hash, location.pathname, navigate, notify])

  function toggleFavorite(id: string) {
    const favorite = !favoriteIds.includes(id)
    const next = favorite ? [...favoriteIds, id] : favoriteIds.filter((item) => item !== id)
    const save = favoriteRepository.setFavorite ? favoriteRepository.setFavorite(id, favorite) : favoriteRepository.saveIds(next)
    void save.then(() => setFavoriteIds(next)).catch(() => { void notify({ type: 'error', title: 'No se pudo guardar el favorito', message: 'Intentá de nuevo.' }) })
  }

  return <div className="page recipes-page">
    <section aria-labelledby="recipe-catalog-title" className="recipe-catalog recipe-catalog-primary" id="recipe-catalog">
      <div className="recipe-catalog-heading">
        <h1 id="recipe-catalog-title">{favoritesOnly ? 'Todas tus favoritas' : 'Explorá el catálogo'}</h1>
        {!favoritesOnly && <div>
          {currentResult?.status === 'ready' && <p aria-live="polite" className="recipe-result-count">{visibleMatches.length} de {candidateCount} recetas</p>}
          <SearchFeedback resultCount={visibleMatches.length} status={failed ? 'error' : loading && search.status !== 'empty' ? 'waiting' : search.status} />
        </div>}
      </div>
      <div aria-label="Filtros de recetas" className="recipe-controls with-search">
        <label className="field"><span>Buscar receta o ingrediente</span><span className="pantry-search-input"><Search aria-hidden="true" size={17} /><input onChange={(event) => updateFilters({ ...filters, search: event.currentTarget.value })} placeholder="Ej.: quinoa, calabaza" type="search" value={filters.search} /></span></label>
        <FilterSelect label="Categoría" onChange={(category) => updateFilters((current) => ({ ...current, category }))} options={[{ value: '', label: 'Todas' }, ...meals.map((meal) => ({ value: meal, label: meal }))]} value={filters.category} />
        <FilterSelect label="Tiempo máximo" onChange={(minutes) => updateFilters((current) => ({ ...current, maxMinutes: minutes ? Number(minutes) : null }))} options={[{ value: '', label: 'Cualquiera' }, { value: '20', label: '20 min' }, { value: '30', label: '30 min' }, { value: '60', label: '60 min' }]} value={String(filters.maxMinutes ?? '')} />
        <FilterSelect label="Dificultad" onChange={(difficulty) => updateFilters((current) => ({ ...current, difficulty: difficulty as RecipeFilters['difficulty'] }))} options={[{ value: '', label: 'Todas' }, { value: 'Fácil', label: 'Fácil' }, { value: 'Intermedia', label: 'Intermedia' }, { value: 'Avanzada', label: 'Avanzada' }]} value={filters.difficulty} />
      </div>
      <fieldset className="recipe-dietary-filters"><legend>Preferencias dietéticas</legend><div>{dietOptions.map(({ id, label }) => <label key={id}><input checked={selectedDiet.includes(id)} onChange={(event) => updateFilters({ ...filters, preferences: event.currentTarget.checked ? [...selectedDiet, id] : selectedDiet.filter((item) => item !== id) })} type="checkbox" /> {label}</label>)}</div></fieldset>
      <p className="recipe-cross-contamination-note" role="note">Las preferencias guardadas se aplican siempre: {activePreferences.length > 0 ? activePreferences.map((preference) => dietOptions.find((option) => option.id === preference)?.label ?? preference).join(', ') : 'sin restricciones dietéticas activas'}. Podés agregar filtros más restrictivos. Las etiquetas describen los ingredientes declarados y no garantizan ausencia de trazas; verificá rótulos y contaminación cruzada.</p>
      <div className="recipe-filter-footer">
        <label className="recipe-pantry-toggle"><input checked={filters.pantryOnly} onChange={(event) => updateFilters({ ...filters, pantryOnly: event.currentTarget.checked })} type="checkbox" /> Puedo cocinar con mi despensa</label>
        <div className="recipe-filter-actions">
          <button onClick={() => updateFilters(initialFilters)} type="button">Limpiar filtros</button>
          {favoritesOnly && <Link className="button button-quiet" to="/recipes">Ver recetas</Link>}
        </div>
      </div>
    </section>
    {currentResult?.status === 'ready' && candidateCount > visibleMatches.length && <p className="recipe-filter-exclusions" role="status">{candidateCount - visibleMatches.length} {candidateCount - visibleMatches.length === 1 ? 'receta no coincide' : 'recetas no coinciden'} con la búsqueda, los filtros y las preferencias dietéticas.</p>}
    {loading ? <LoadingScreen message="Cargando recetas…" variant="section" /> : failed ? <section className="pantry-empty"><h2>No se pudieron cargar las recetas</h2><p>Volvé a intentarlo para consultar el recetario.</p><button className="button button-primary" onClick={retryLoad} type="button">Reintentar</button></section> : visibleMatches.length === 0 ? <section className="pantry-empty"><h2>{favoritesOnly && favoriteIds.length === 0 ? 'Todavía no guardaste recetas' : 'No encontramos recetas'}</h2><p>{favoritesOnly && favoriteIds.length === 0 ? 'Explorá el catálogo y tocá el corazón de una receta.' : 'Probá limpiar filtros o revisar tus preferencias dietéticas y la despensa.'}</p></section> : <>
    <RecipePagination currentPage={currentPage} onPageChange={changePage} pageCount={pageCount} position="superior" />
    <section aria-label="Listado de recetas" className="recipe-grid">
      {pageMatches.map(({ recipe, percentage, label }, index) => {
        const favorite = favoriteIds.includes(recipe.id)
        return <article className="recipe-card" key={recipe.id} ref={index === 0 ? firstRecipeRef : undefined} tabIndex={index === 0 ? -1 : undefined}><RecipeArtwork recipe={recipe} /><div className="recipe-body"><div className="recipe-card-top"><span className="recipe-category">{recipeMealShifts(recipe).join(' · ')}</span><button aria-label={`${favorite ? 'Quitar' : 'Agregar'} ${recipe.name} ${favorite ? 'de' : 'a'} favoritos`} aria-pressed={favorite} className="recipe-favorite" onClick={() => toggleFavorite(recipe.id)} type="button"><Heart fill={favorite ? 'currentColor' : 'none'} size={19} /></button></div><h2><Link to={`/recipes/${recipe.id}`}>{recipe.name}</Link></h2><p>{recipe.description}</p>{recipe.dietaryTags?.length ? <p className="recipe-dietary-tags">{recipe.dietaryTags.join(' · ')}</p> : null}<div className="recipe-meta"><span><Clock3 size={15} /> {recipe.minutes} min</span><span><UsersRound size={15} /> {recipe.portions} porciones</span><span>{recipe.difficulty}</span></div><p className={`recipe-availability ${percentage === 100 ? 'complete' : ''}`}>{label} · {percentage}%</p><Link className="recipe-card-link" to={`/recipes/${recipe.id}`}>Ver receta <ArrowRight aria-hidden="true" size={16} /></Link></div></article>
      })}
    </section>
    <RecipePagination currentPage={currentPage} onPageChange={changePage} pageCount={pageCount} position="inferior" />
    </>}
  </div>
}
