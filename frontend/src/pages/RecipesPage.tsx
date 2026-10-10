import { useEffect, useMemo, useState } from 'react'
import { ArrowRight, Clock3, Heart, Search, UsersRound } from 'lucide-react'
import { Link, useLocation, useNavigate } from 'react-router-dom'
import { getPantryItems } from '../features/pantry/data/localPantryStore'
import { mockFavoriteRepository } from '../features/recipes/data/localFavoritesStore'
import { recipeMealShifts, type RecipeFilters } from '../features/recipes/domain/recipeRules'
import { mockRecipeRepository } from '../features/recipes/data/MockRecipeRepository'
import { meals } from '../features/planner/domain/planner'
import type { Recipe } from '../features/recipes/domain/Recipe'
import { RecipeImage } from '../features/recipes/ui/RecipeImage'
import { SearchFeedback } from '../shared/search/SearchFeedback'
import { useDebouncedSearch } from '../shared/search/useDebouncedSearch'
import type { DietaryPreference } from '../features/profile/domain/profile'
import { useNotifications } from '../shared/notifications/NotificationProvider'

const initialFilters: RecipeFilters = { search: '', category: '', maxMinutes: null, difficulty: '', pantryOnly: false }
const dietOptions: Array<{ id: DietaryPreference; label: string }> = [
  { id: 'gluten-free', label: 'Sin TACC' }, { id: 'vegetarian', label: 'Vegetariana' }, { id: 'vegan', label: 'Vegana' },
  { id: 'lactose-free', label: 'Sin lactosa' }, { id: 'nut-free', label: 'Sin frutos secos' },
]

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
  const [matches, setMatches] = useState<Array<Awaited<ReturnType<typeof mockRecipeRepository.match>>[number]>>([])
  const [loading, setLoading] = useState(true)
  const [loadFailed, setLoadFailed] = useState(false)
  const [loadAttempt, setLoadAttempt] = useState(0)
  const [completionNotice] = useState(() => {
    const state = location.state as { completionMessage?: unknown } | null
    return typeof state?.completionMessage === 'string' ? state.completionMessage : ''
  })
  const search = useDebouncedSearch(filters.search)
  const selectedDiet = filters.preferences ?? []
  const effectivePreferences = useMemo(() => [...new Set([...activePreferences, ...(filters.preferences ?? [])])], [activePreferences, filters.preferences])
  const visibleMatches = (search.status === 'waiting' ? [] : matches)
    .filter(({ recipe }) => !favoritesOnly || favoriteIds.includes(recipe.id))
  const candidateCount = favoritesOnly ? Math.min(catalogCount, favoriteIds.length) : catalogCount

  useEffect(() => {
    let current = true
    void Promise.all([mockRecipeRepository.list(), getPantryItems(), mockFavoriteRepository.listIds(), mockRecipeRepository.getDietaryPreferences()])
      .then(([catalog, stock, favorites, preferences]) => { if (current) { setCatalogCount(catalog.length); setPantry(stock); setFavoriteIds(favorites); setActivePreferences(preferences) } })
      .catch(() => { if (current) { setLoadFailed(true); void notify({ type: 'error', title: 'No se pudieron cargar las recetas', message: 'Intentá de nuevo.' }) } })
      .finally(() => { if (current) setLoading(false) })
    return () => { current = false }
  }, [loadAttempt, notify])

  useEffect(() => {
    if (loading || loadFailed) return
    let current = true
    void mockRecipeRepository.match(pantry, { ...filters, search: search.query, preferences: effectivePreferences })
      .then((result) => { if (current) setMatches(result) })
      .catch(() => { if (current) void notify({ type: 'error', title: 'No se pudieron filtrar las recetas', message: 'Intentá de nuevo.' }) })
    return () => { current = false }
  }, [loading, loadFailed, pantry, filters, search.query, search.status, effectivePreferences, notify])

  function retryLoad() {
    setLoading(true)
    setLoadFailed(false)
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
    const next = favoriteIds.includes(id) ? favoriteIds.filter((item) => item !== id) : [...favoriteIds, id]
    void mockFavoriteRepository.saveIds(next).then(() => setFavoriteIds(next)).catch(() => { void notify({ type: 'error', title: 'No se pudo guardar el favorito', message: 'Revisá el espacio disponible del navegador e intentá de nuevo.' }) })
  }

  return <div className="page recipes-page">
    {favoritesOnly ? <header className="page-heading"><div><p className="eyebrow">RECETAS GUARDADAS</p><h1>Colección Personal</h1><p className="page-lead">Tus recetas favoritas activas, organizadas para volver a ellas.</p></div><Link className="button button-quiet" to="/recipes">Explorar recetas</Link></header> : <header className="page-heading"><div><p className="eyebrow">RECETARIO COCINAPP</p><h1>Recetas</h1><p className="page-lead">Buscá, filtrá y consultá todas las recetas disponibles.</p></div></header>}

    <section aria-labelledby="recipe-catalog-title" className="recipe-catalog" id="recipe-catalog">
      <div className="recipe-catalog-heading"><div><p className="eyebrow">{favoritesOnly ? 'TU COLECCIÓN' : 'TODAS LAS OPCIONES'}</p><h2 id="recipe-catalog-title">{favoritesOnly ? 'Todas tus favoritas' : 'Explorá el catálogo'}</h2></div><div><p aria-live="polite" className="recipe-result-count">{visibleMatches.length} de {candidateCount} recetas</p><SearchFeedback resultCount={visibleMatches.length} status={search.status} /></div></div>
      <div aria-label="Filtros de recetas" className="recipe-controls with-search">
        <label className="field"><span>Buscar receta o ingrediente</span><span className="pantry-search-input"><Search aria-hidden="true" size={17} /><input onChange={(event) => setFilters({ ...filters, search: event.currentTarget.value })} placeholder="Ej.: quinoa, calabaza" type="search" value={filters.search} /></span></label>
        <label className="field"><span>Categoría</span><select onChange={(event) => setFilters({ ...filters, category: event.currentTarget.value })} value={filters.category}><option value="">Todas</option>{meals.map((meal) => <option key={meal}>{meal}</option>)}</select></label>
        <label className="field"><span>Tiempo máximo</span><select onChange={(event) => setFilters({ ...filters, maxMinutes: event.currentTarget.value ? Number(event.currentTarget.value) : null })} value={filters.maxMinutes ?? ''}><option value="">Cualquiera</option><option value="20">20 min</option><option value="30">30 min</option><option value="60">60 min</option></select></label>
        <label className="field"><span>Dificultad</span><select onChange={(event) => setFilters({ ...filters, difficulty: event.currentTarget.value as RecipeFilters['difficulty'] })} value={filters.difficulty}><option value="">Todas</option><option>Fácil</option><option>Intermedia</option><option>Avanzada</option></select></label>
      </div>
      <fieldset className="recipe-dietary-filters"><legend>Preferencias dietéticas</legend><div>{dietOptions.map(({ id, label }) => <label key={id}><input checked={selectedDiet.includes(id)} onChange={(event) => setFilters({ ...filters, preferences: event.currentTarget.checked ? [...selectedDiet, id] : selectedDiet.filter((item) => item !== id) })} type="checkbox" /> {label}</label>)}</div></fieldset>
      <p className="recipe-cross-contamination-note" role="note">Las preferencias guardadas se aplican siempre: {activePreferences.length > 0 ? activePreferences.map((preference) => dietOptions.find((option) => option.id === preference)?.label ?? preference).join(', ') : 'sin restricciones dietéticas activas'}. Podés agregar filtros más restrictivos. Las etiquetas describen los ingredientes declarados y no garantizan ausencia de trazas; verificá rótulos y contaminación cruzada.</p>
      <div className="recipe-filter-footer"><label className="recipe-pantry-toggle"><input checked={filters.pantryOnly} onChange={(event) => setFilters({ ...filters, pantryOnly: event.currentTarget.checked })} type="checkbox" /> Puedo cocinar con mi despensa</label><button onClick={() => setFilters(initialFilters)} type="button">Limpiar filtros</button></div>
    </section>
    {!loading && search.status !== 'waiting' && candidateCount > visibleMatches.length && <p className="recipe-filter-exclusions" role="status">{candidateCount - visibleMatches.length} {candidateCount - visibleMatches.length === 1 ? 'receta no coincide' : 'recetas no coinciden'} con la búsqueda, los filtros y las preferencias dietéticas.</p>}
    {loading ? <p role="status">Cargando recetas…</p> : loadFailed ? <section className="pantry-empty"><h2>No se pudieron cargar las recetas</h2><p>Volvé a intentarlo para consultar el recetario.</p><button className="button button-primary" onClick={retryLoad} type="button">Reintentar</button></section> : search.status !== 'waiting' && (visibleMatches.length === 0 ? <section className="pantry-empty"><h2>{favoritesOnly && favoriteIds.length === 0 ? 'Todavía no guardaste recetas' : 'No encontramos recetas'}</h2><p>{favoritesOnly && favoriteIds.length === 0 ? 'Explorá el catálogo y tocá el corazón de una receta.' : 'Probá limpiar filtros o revisar tus preferencias dietéticas y la despensa.'}</p></section> : <section aria-label="Listado de recetas" className="recipe-grid">
      {visibleMatches.map(({ recipe, percentage, label, ingredients }) => {
        const missing = ingredients.filter((item) => item.missing > 0)
        const favorite = favoriteIds.includes(recipe.id)
        return <article className="recipe-card" key={recipe.id}><RecipeArtwork recipe={recipe} /><div className="recipe-body"><div className="recipe-card-top"><span className="recipe-category">{recipeMealShifts(recipe).join(' · ')}</span><button aria-label={`${favorite ? 'Quitar' : 'Agregar'} ${recipe.name} ${favorite ? 'de' : 'a'} favoritos`} aria-pressed={favorite} className="recipe-favorite" onClick={() => toggleFavorite(recipe.id)} type="button"><Heart fill={favorite ? 'currentColor' : 'none'} size={19} /></button></div><h2><Link to={`/recipes/${recipe.id}`}>{recipe.name}</Link></h2><p>{recipe.description}</p>{recipe.dietaryTags?.length ? <p className="recipe-dietary-tags">{recipe.dietaryTags.join(' · ')}</p> : null}<div className="recipe-meta"><span><Clock3 size={15} /> {recipe.minutes} min</span><span><UsersRound size={15} /> {recipe.portions} porciones</span><span>{recipe.difficulty}</span></div><p className={`recipe-availability ${percentage === 100 ? 'complete' : ''}`}>{label} · {percentage}%</p>{missing.length > 0 && <ul className="recipe-card-missing">{missing.map((item) => <li key={item.ingredient.name}>{item.ingredient.name}: faltan {item.missing} {item.ingredient.unit}</li>)}</ul>}<Link className="recipe-card-link" to={`/recipes/${recipe.id}`}>Ver receta <ArrowRight aria-hidden="true" size={16} /></Link></div></article>
      })}
    </section>)}
  </div>
}
