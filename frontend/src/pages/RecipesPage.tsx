import { useState } from 'react'
import { Clock3, Heart, Search, UsersRound } from 'lucide-react'
import { Link } from 'react-router-dom'
import { readPantryItems } from '../features/pantry/data/localPantryStore'
import { readFavoriteIds, writeFavoriteIds } from '../features/recipes/data/localFavoritesStore'
import { filterRecipes, getIngredientAvailability, type RecipeFilters } from '../features/recipes/domain/recipeRules'
import { getAvailableRecipes, getKnownRecipes } from '../features/recipes/data/availableRecipes'
import { readHistory } from '../features/cooking/data/localCookingStore'
import { discoverRecipes } from '../features/recipes/domain/recipeDiscovery'
import { meals } from '../features/planner/domain/planner'
import type { Recipe } from '../features/recipes/domain/Recipe'

const initialFilters: RecipeFilters = { search: '', category: '', maxMinutes: null, difficulty: '', pantryOnly: false }

function DiscoverySection({ title, description, recipes, empty, action = 'Ver receta' }: {
  title: string; description: string; recipes: Recipe[]; empty: string; action?: string
}) {
  return <section aria-label={title} className="recipe-discovery-section"><h2>{title}</h2><p>{description}</p>{recipes.length === 0 ? <p className="recipe-discovery-empty">{empty}</p> : <ul className="recipe-discovery-items">{recipes.map((recipe) => <li key={recipe.id}><span><strong>{recipe.name}</strong><small>{recipe.category} · {recipe.minutes} min</small></span><Link className="text-link" to={`/recipes/${recipe.id}`}>{action}</Link></li>)}</ul>}</section>
}

export function RecipesPage({ favoritesOnly = false }: { favoritesOnly?: boolean }) {
  const [filters, setFilters] = useState<RecipeFilters>(initialFilters)
  const [pantry] = useState(readPantryItems)
  const [favoriteIds, setFavoriteIds] = useState(readFavoriteIds)
  const [history] = useState(readHistory)
  const [error, setError] = useState('')
  const activeRecipes = getAvailableRecipes()
  const knownRecipes = getKnownRecipes()
  const discovery = discoverRecipes(activeRecipes, knownRecipes, favoriteIds, history)
  const catalog = favoritesOnly ? knownRecipes : activeRecipes
  const recipes = filterRecipes(catalog, filters, pantry).filter((recipe) => !favoritesOnly || favoriteIds.includes(recipe.id))
  const activeIds = new Set(activeRecipes.map((recipe) => recipe.id))

  function toggleFavorite(id: string) {
    const next = favoriteIds.includes(id) ? favoriteIds.filter((item) => item !== id) : [...favoriteIds, id]
    try { writeFavoriteIds(next); setFavoriteIds(next); setError('') }
    catch { setError('No se pudo guardar el favorito en este navegador.') }
  }

  return <div className="page recipes-page">
    <header className="page-heading"><div><p className="eyebrow">{favoritesOnly ? 'RECETAS GUARDADAS' : 'EXPLORÁ Y COCINÁ'}</p><h1>{favoritesOnly ? 'Tus favoritas' : 'Ideas para cocinar'}</h1><p className="page-lead">{favoritesOnly ? 'Tus recetas preferidas, guardadas en este navegador.' : 'Descubrí recetas y mirá qué ingredientes ya tenés en tu despensa.'}</p></div>{favoritesOnly && <Link className="button button-quiet" to="/recipes">Explorar recetas</Link>}</header>
    {!favoritesOnly && <div className="recipe-discovery">
      <DiscoverySection description="Selección editorial de ejemplo y recetas que ADMIN marcó como destacadas." empty="Todavía no hay recetas destacadas." recipes={discovery.featured} title="Destacadas" />
      <DiscoverySection description="Ideas similares a tus preparaciones anteriores, sin repetirlas." empty={history.length ? 'Todavía no hay recetas similares disponibles.' : 'Cociná una receta para recibir sugerencias basadas en tu historial.'} recipes={discovery.basedOnHistory} title="Basado en lo que cocinaste" />
      <DiscoverySection action="Ver receta" description="Tus preparaciones recientes que siguen disponibles." empty="Tu historial aún no tiene recetas activas para volver a cocinar." recipes={discovery.recook} title="Volver a cocinar" />
      <DiscoverySection description="Las recetas activas que guardaste." empty="Todavía no guardaste recetas favoritas activas." recipes={discovery.favorites} title="Favoritas" />
    </div>}
    <h2 className="recipe-catalog-title">{favoritesOnly ? 'Todas tus favoritas' : 'Catálogo completo'}</h2>
    <section aria-label="Filtros de recetas" className="recipe-controls">
      <label className="field"><span>Buscar receta o ingrediente</span><span className="pantry-search-input"><Search aria-hidden="true" size={17} /><input onChange={(event) => setFilters({ ...filters, search: event.currentTarget.value })} placeholder="Ej.: quinoa, calabaza" type="search" value={filters.search} /></span></label>
      <label className="field"><span>Categoría</span><select onChange={(event) => setFilters({ ...filters, category: event.currentTarget.value })} value={filters.category}><option value="">Todas</option>{meals.map((meal) => <option key={meal}>{meal}</option>)}</select></label>
      <label className="field"><span>Tiempo máximo</span><select onChange={(event) => setFilters({ ...filters, maxMinutes: event.currentTarget.value ? Number(event.currentTarget.value) : null })} value={filters.maxMinutes ?? ''}><option value="">Cualquiera</option><option value="20">20 min</option><option value="30">30 min</option><option value="60">60 min</option></select></label>
      <label className="field"><span>Dificultad</span><select onChange={(event) => setFilters({ ...filters, difficulty: event.currentTarget.value as RecipeFilters['difficulty'] })} value={filters.difficulty}><option value="">Todas</option><option>Fácil</option><option>Intermedia</option><option>Avanzada</option></select></label>
    </section>
    <label className="recipe-pantry-toggle"><input checked={filters.pantryOnly} onChange={(event) => setFilters({ ...filters, pantryOnly: event.currentTarget.checked })} type="checkbox" /> Puedo cocinar con mi despensa</label>
    <div className="pantry-results"><span aria-live="polite">{recipes.length} {recipes.length === 1 ? 'receta encontrada' : 'recetas encontradas'}</span><button onClick={() => setFilters(initialFilters)} type="button">Limpiar filtros</button></div>
    {error && <p className="form-message error" role="alert">{error}</p>}
    {recipes.length === 0 ? <section className="pantry-empty"><h2>{favoritesOnly && favoriteIds.length === 0 ? 'Todavía no guardaste recetas' : 'No encontramos recetas'}</h2><p>{favoritesOnly && favoriteIds.length === 0 ? 'Explorá el catálogo y tocá el corazón de una receta.' : 'Probá otros filtros o agregá ingredientes a tu despensa.'}</p></section> : <section aria-label="Listado de recetas" className="recipe-grid">
      {recipes.map((recipe) => {
        const availability = getIngredientAvailability(recipe, pantry)
        const favorite = favoriteIds.includes(recipe.id)
        return <article className="recipe-card" key={recipe.id}><div className={`recipe-art ${recipe.color}`} aria-hidden="true"><span>{recipe.symbol}</span></div><div className="recipe-body"><div className="recipe-card-top"><span className="recipe-category">{recipe.category}</span><button aria-label={`${favorite ? 'Quitar' : 'Agregar'} ${recipe.name} ${favorite ? 'de' : 'a'} favoritos`} aria-pressed={favorite} className="recipe-favorite" onClick={() => toggleFavorite(recipe.id)} type="button"><Heart fill={favorite ? 'currentColor' : 'none'} size={19} /></button></div><h2><Link to={`/recipes/${recipe.id}`}>{recipe.name}</Link></h2><p>{recipe.description}</p>{!activeIds.has(recipe.id) && <p className="form-message">Receta inactiva: disponible solo para consulta.</p>}<div className="recipe-meta"><span><Clock3 size={15} /> {recipe.minutes} min</span><span><UsersRound size={15} /> {recipe.portions} porciones</span><span>{recipe.difficulty}</span></div><p className={`recipe-availability ${availability.missing.length === 0 ? 'complete' : ''}`}>{availability.missing.length === 0 ? 'Podés cocinarla' : `${availability.available.length} de ${recipe.ingredients.length} ingredientes disponibles`}</p><Link className="text-link" to={`/recipes/${recipe.id}`}>Ver receta →</Link></div></article>
      })}
    </section>}
  </div>
}
