import { useEffect, useState } from 'react'
import { ArrowRight, Clock3, Heart, PackageCheck, Search, Sparkles, UsersRound } from 'lucide-react'
import { Link, useLocation, useNavigate } from 'react-router-dom'
import { readPantryItems } from '../features/pantry/data/localPantryStore'
import { readFavoriteIds, writeFavoriteIds } from '../features/recipes/data/localFavoritesStore'
import { filterRecipes, getIngredientAvailability, type RecipeFilters } from '../features/recipes/domain/recipeRules'
import { getAvailableRecipes, getKnownRecipes } from '../features/recipes/data/availableRecipes'
import { readHistory } from '../features/cooking/data/localCookingStore'
import { discoverRecipes } from '../features/recipes/domain/recipeDiscovery'
import { meals } from '../features/planner/domain/planner'
import type { Recipe } from '../features/recipes/domain/Recipe'
import { RecipeImage } from '../features/recipes/ui/RecipeImage'
import { SearchFeedback } from '../shared/search/SearchFeedback'
import { useDebouncedSearch } from '../shared/search/useDebouncedSearch'

const initialFilters: RecipeFilters = { search: '', category: '', maxMinutes: null, difficulty: '', pantryOnly: false }

function RecipeArtwork({ recipe, size = 'card' }: { recipe: Recipe; size?: 'hero' | 'card' | 'mini' }) {
  return <RecipeImage className={`recipe-artwork recipe-artwork-${size}`} loading={size === 'hero' ? 'eager' : 'lazy'} recipe={recipe} />
}

function RecipeRail({ id, eyebrow, title, description, recipes, empty }: {
  id: string; eyebrow: string; title: string; description: string; recipes: Recipe[]; empty: string
}) {
  return <section aria-labelledby={`${id}-title`} className="recipe-rail" id={id}>
    <div className="recipe-rail-heading"><div><p className="eyebrow">{eyebrow}</p><h2 id={`${id}-title`}>{title}</h2><p>{description}</p></div><a className="recipe-rail-catalog-link" href="#recipe-catalog">Ver catálogo <ArrowRight aria-hidden="true" size={15} /></a></div>
    {recipes.length === 0
      ? <div className="recipe-rail-empty"><Sparkles aria-hidden="true" size={19} /><span>{empty}</span></div>
      : <div className="recipe-rail-items">{recipes.slice(0, 4).map((recipe) => <Link className="recipe-mini-card" key={recipe.id} to={`/recipes/${recipe.id}`}><RecipeArtwork recipe={recipe} size="mini" /><span className="recipe-mini-copy"><span className="recipe-category">{recipe.category}</span><strong>{recipe.name}</strong><small><Clock3 aria-hidden="true" size={13} /> {recipe.minutes} min · {recipe.difficulty}</small></span><ArrowRight aria-hidden="true" className="recipe-mini-arrow" size={17} /></Link>)}</div>}
  </section>
}

export function RecipesPage({ favoritesOnly = false }: { favoritesOnly?: boolean }) {
  const location = useLocation()
  const navigate = useNavigate()
  const { hash } = location
  const [filters, setFilters] = useState<RecipeFilters>(initialFilters)
  const [pantry] = useState(readPantryItems)
  const [favoriteIds, setFavoriteIds] = useState(readFavoriteIds)
  const [history] = useState(readHistory)
  const [error, setError] = useState('')
  const [completionNotice, setCompletionNotice] = useState(() => {
    const state = location.state as { completionMessage?: unknown } | null
    return typeof state?.completionMessage === 'string' ? state.completionMessage : ''
  })
  const search = useDebouncedSearch(filters.search)
  const activeRecipes = getAvailableRecipes()
  const knownRecipes = getKnownRecipes()
  const discovery = discoverRecipes(activeRecipes, knownRecipes, favoriteIds, history)
  const catalog = activeRecipes
  const recipes = (search.status === 'waiting' ? [] : filterRecipes(catalog, { ...filters, search: search.query }, pantry))
    .filter((recipe) => !favoritesOnly || favoriteIds.includes(recipe.id))
  const activeIds = new Set(activeRecipes.map((recipe) => recipe.id))
  const featured = activeRecipes.filter((recipe) => recipe.featured).sort((a, b) => a.name.localeCompare(b.name, 'es')).slice(0, 4)
  const pantryReady = activeRecipes.filter((recipe) => getIngredientAvailability(recipe, pantry).missing.length === 0).slice(0, 4)
  const quickRecipes = activeRecipes.filter((recipe) => recipe.minutes <= 20).sort((a, b) => a.minutes - b.minutes).slice(0, 4)
  const heroRecipe = discovery.basedOnHistory[0] ?? pantryReady[0] ?? featured[0] ?? activeRecipes[0]
  const heroAvailability = heroRecipe ? getIngredientAvailability(heroRecipe, pantry) : null

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
    {favoritesOnly ? <header className="page-heading"><div><p className="eyebrow">RECETAS GUARDADAS</p><h1>Tus favoritas</h1><p className="page-lead">Tus recetas preferidas, guardadas en este navegador.</p></div><Link className="button button-quiet" to="/recipes">Explorar recetas</Link></header> : <>
      <header className="recipes-intro"><div><p className="eyebrow">TU PRÓXIMA COMIDA EMPIEZA ACÁ</p><h1>¿Qué cocinamos hoy?</h1><p>Ideas pensadas para tu tiempo, tu despensa y lo que ya disfrutaste.</p></div><label className="recipe-hero-search"><Search aria-hidden="true" size={20} /><span className="sr-only">Buscar receta o ingrediente</span><input onChange={(event) => setFilters({ ...filters, search: event.currentTarget.value })} placeholder="Buscá una receta o ingrediente" type="search" value={filters.search} /></label></header>
      {heroRecipe && <section className={`recipe-hero ${heroRecipe.color}`} aria-labelledby="recipe-hero-title"><div className="recipe-hero-copy"><p className="recipe-hero-kicker"><Sparkles aria-hidden="true" size={16} /> Recomendación para vos</p><h2 id="recipe-hero-title">{heroRecipe.name}</h2><p>{heroRecipe.description}</p><div className="recipe-hero-meta"><span><Clock3 aria-hidden="true" size={16} />{heroRecipe.minutes} min</span><span><UsersRound aria-hidden="true" size={16} />{heroRecipe.portions} porciones</span><span>{heroRecipe.difficulty}</span></div><div className="recipe-hero-actions"><Link className="button button-dark" to={`/recipes/${heroRecipe.id}`}>Ver receta <ArrowRight aria-hidden="true" size={17} /></Link>{heroAvailability && <span className={heroAvailability.missing.length === 0 ? 'ready' : ''}><PackageCheck aria-hidden="true" size={17} />{heroAvailability.missing.length === 0 ? 'Tenés todo para cocinarla' : `Te faltan ${heroAvailability.missing.length} ingredientes`}</span>}</div></div><RecipeArtwork recipe={heroRecipe} size="hero" /></section>}
      <RecipeRail description="Selecciones destacadas desde la administración de CocinAPP." empty="Todavía no hay recetas destacadas." eyebrow="SELECCIÓN COCINAPP" id="recipe-featured" recipes={featured} title="Recetas destacadas" />
      <RecipeRail description="Opciones que podés preparar con el stock disponible." empty="Agregá ingredientes a tu despensa para recibir sugerencias listas para cocinar." eyebrow="APROVECHÁ TU STOCK" id="recipe-pantry-ready" recipes={pantryReady} title="Con lo que ya tenés" />
      <RecipeRail description="Sugerencias relacionadas con tus últimas preparaciones." empty="Cociná una receta y usaremos ese historial para recomendarte nuevas ideas." eyebrow="HECHO A TU MEDIDA" id="recipe-history-based" recipes={discovery.basedOnHistory} title="Según lo que cocinaste" />
      {(discovery.recook.length > 0 || discovery.favorites.length > 0) && <div className="recipe-personal-grid">
        <RecipeRail description="Tus preparaciones recientes, a un toque de distancia." empty="Tu historial todavía está vacío." eyebrow="OTRA VEZ, POR FAVOR" id="recipe-recook" recipes={discovery.recook} title="Volvé a cocinar" />
        <RecipeRail description="Las recetas que marcaste para tener siempre a mano." empty="Marcá una receta con el corazón para verla acá." eyebrow="TU COLECCIÓN" id="recipe-favorites" recipes={discovery.favorites} title="Tus favoritas" />
      </div>}
      <RecipeRail description="Preparaciones simples para los días con poco tiempo." empty="No hay recetas rápidas publicadas por el momento." eyebrow="POCO TIEMPO, MUCHO SABOR" id="recipe-quick" recipes={quickRecipes} title="Listas en 20 minutos" />
    </>}

    <section aria-labelledby="recipe-catalog-title" className="recipe-catalog" id="recipe-catalog">
      <div className="recipe-catalog-heading"><div><p className="eyebrow">{favoritesOnly ? 'TU COLECCIÓN' : 'TODAS LAS OPCIONES'}</p><h2 id="recipe-catalog-title">{favoritesOnly ? 'Todas tus favoritas' : 'Explorá el catálogo'}</h2></div><SearchFeedback resultCount={recipes.length} status={search.status} /></div>
      <div aria-label="Filtros de recetas" className={`recipe-controls${favoritesOnly ? ' with-search' : ''}`}>
        {favoritesOnly && <label className="field"><span>Buscar receta o ingrediente</span><span className="pantry-search-input"><Search aria-hidden="true" size={17} /><input onChange={(event) => setFilters({ ...filters, search: event.currentTarget.value })} placeholder="Ej.: quinoa, calabaza" type="search" value={filters.search} /></span></label>}
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
