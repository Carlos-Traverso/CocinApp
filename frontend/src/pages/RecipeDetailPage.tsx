import { LoadingScreen } from '../components/LoadingScreen'
import { useEffect, useState } from 'react'
import { ArrowLeft, ChefHat, Clock3, Heart, Minus, Plus, UsersRound } from 'lucide-react'
import { Link, useParams, useSearchParams } from 'react-router-dom'
import { getPantryItems } from '../features/pantry/data/localPantryStore'
import { formatPantryAmount } from '../features/pantry/domain/pantry'
import { estimateForProfile, recipeGoalPercentageRange } from '../features/profile/domain/profile'
import { mockFavoriteRepository } from '../features/recipes/data/localFavoritesStore'
import { mockRecipeRepository } from '../features/recipes/data/MockRecipeRepository'
import { matchesDietaryPreferences, parseRecipePortions, recipeMealShifts } from '../features/recipes/domain/recipeRules'
import type { IngredientDeficit } from '../features/recipes/domain/recipeRules'
import type { Recipe } from '../features/recipes/domain/Recipe'
import { RecipeImage } from '../features/recipes/ui/RecipeImage'
import { addRecipeToShopping } from '../features/recipes/data/recipeActions'
import type { DietaryPreference } from '../features/profile/domain/profile'
import { useNotifications } from '../shared/notifications/NotificationProvider'

const preferenceLabels: Record<DietaryPreference, string> = {
  'gluten-free': 'Sin TACC', vegetarian: 'Vegetariana', vegan: 'Vegana', 'lactose-free': 'Sin lactosa', 'nut-free': 'Sin frutos secos',
}

export function RecipeDetailPage() {
  const { id = '' } = useParams()
  const { notify } = useNotifications()
  const [searchParams] = useSearchParams()
  const [recipe, setRecipe] = useState<Recipe | null>(null)
  const [active, setActive] = useState(false)
  const [portions, setPortions] = useState(1)
  const [pantry, setPantry] = useState<Awaited<ReturnType<typeof getPantryItems>>>([])
  const [favoriteIds, setFavoriteIds] = useState<string[]>([])
  const [preferences, setPreferences] = useState<Awaited<ReturnType<typeof mockRecipeRepository.getDietaryPreferences>>>([])
  const [profile, setProfile] = useState<Awaited<ReturnType<typeof mockRecipeRepository.getProfile>>>({})
  const [readiness, setReadiness] = useState<{ percentage: number; label: string; ingredients: IngredientDeficit[] }>()
  const [loadAttempt, setLoadAttempt] = useState(0)
  const [loadOutcome, setLoadOutcome] = useState<{ key: string; status: 'success' | 'error' } | null>(null)
  const loadKey = `${id}:${loadAttempt}`
  const loading = loadOutcome?.key !== loadKey
  const loadFailed = loadOutcome?.key === loadKey && loadOutcome.status === 'error'

  useEffect(() => {
    let current = true
    void Promise.all([mockRecipeRepository.getById(id, true), mockRecipeRepository.list(), getPantryItems(), mockFavoriteRepository.listIds(), mockRecipeRepository.getDietaryPreferences(), mockRecipeRepository.getProfile()])
      .then(([found, activeRecipes, stock, favorites, selectedPreferences, profileData]) => {
        if (!current) return
        setRecipe(found ?? null)
        setActive(Boolean(found && activeRecipes.some((item) => item.id === found.id)))
        setPortions(found ? parseRecipePortions(searchParams.get('portions')) ?? found.portions : 1)
        setPantry(stock)
        setFavoriteIds(favorites)
        setPreferences(selectedPreferences)
        setProfile(profileData)
        setLoadOutcome({ key: loadKey, status: 'success' })
      })
      .catch(() => { if (current) { setLoadOutcome({ key: loadKey, status: 'error' }); void notify({ type: 'error', title: 'No se pudo cargar la receta', message: 'Intentá volver al recetario y abrirla de nuevo.' }) } })
    return () => { current = false }
  }, [id, searchParams, loadKey, notify])

  useEffect(() => {
    if (!recipe) return
    let current = true
    void mockRecipeRepository.getReadiness(recipe.id, pantry, portions, true)
      .then((value) => { if (current) setReadiness(value) })
      .catch(() => { if (current) void notify({ type: 'error', title: 'No se pudo consultar el stock', message: 'No se pudo actualizar la disponibilidad para esta cantidad.' }) })
    return () => { current = false }
  }, [recipe, pantry, portions, notify])

  if (loading) return <div className="page"><LoadingScreen message="Cargando receta…" /></div>
  if (loadFailed) return <div className="page"><Link className="back-link" to="/recipes"><ArrowLeft size={16} /> Recetas</Link><h1>No se pudo cargar la receta</h1><p>Volvé a intentarlo para consultar sus datos.</p><button className="button button-primary" onClick={() => setLoadAttempt((attempt) => attempt + 1)} type="button">Reintentar</button></div>
  if (!recipe) return <div className="page"><Link className="back-link" to="/recipes"><ArrowLeft size={16} /> Recetas</Link><h1>Receta no encontrada</h1></div>

  const favorite = favoriteIds.includes(recipe.id)
  const estimate = estimateForProfile(profile)
  const proportion = recipe.calories !== undefined && estimate ? recipeGoalPercentageRange(recipe.calories, estimate) : undefined
  const excludedPreferences = preferences.filter((preference) => !matchesDietaryPreferences(recipe, [preference]))
  const preferenceMatch = excludedPreferences.length === 0
  const totalCalories = recipe.calories === undefined ? undefined : Math.round(recipe.calories * portions)
  const ingredientRows = readiness?.ingredients ?? []

  async function toggleFavorite() {
    const next = favorite ? favoriteIds.filter((item) => item !== recipe!.id) : [...favoriteIds, recipe!.id]
    try { await mockFavoriteRepository.saveIds(next); setFavoriteIds(next) }
    catch { await notify({ type: 'error', title: 'No se pudo guardar el favorito', message: 'Revisá el espacio disponible del navegador e intentá de nuevo.' }) }
  }

  async function sendMissingToShopping() {
    try {
      await addRecipeToShopping(recipe!, pantry, portions)
      await notify({ type: 'success', title: 'Ingredientes añadidos a Compras', message: 'Los ingredientes faltantes se añadieron a tu lista de compras.' })
    } catch {
      await notify({ type: 'error', title: 'No se pudo guardar la lista de compras', message: 'Revisá el espacio disponible del navegador e intentá de nuevo.' })
    }
  }

  return <div className="page recipe-detail-page"><Link className="back-link" to="/recipes"><ArrowLeft size={16} /> Volver a recetas</Link><header className="recipe-detail-header"><RecipeImage className="recipe-art" loading="eager" recipe={recipe} /><div><p className="eyebrow">{recipeMealShifts(recipe).join(' · ')}</p><h1>{recipe.name}</h1><p className="page-lead">{recipe.description}</p>{!active && <p className="form-message">Receta inactiva: se conserva para consulta histórica.</p>}{!preferenceMatch && <p className="form-message">No aparece en tu descubrimiento porque no coincide con: {excludedPreferences.map((item) => preferenceLabels[item]).join(', ')}.</p>}<div className="recipe-detail-meta"><span><Clock3 size={17} /> {recipe.minutes} min</span><span><UsersRound size={17} /> {portions} porciones</span><span>{recipe.difficulty}</span>{recipe.calories !== undefined && <span>{recipe.calories} kcal por porción · {totalCalories} kcal en total</span>}</div>{recipe.dietaryTags && recipe.dietaryTags.length > 0 && <p className="page-lead recipe-detail-tags">Etiquetas: {recipe.dietaryTags.join(', ')}</p>}<div className="recipe-detail-actions">{active && preferenceMatch && <Link className="button button-primary" to={`/recipes/${recipe.id}/cook?portions=${portions}`}><ChefHat aria-hidden="true" size={20} /> Iniciar Modo Cocina</Link>}{(active || favorite) && <button aria-pressed={favorite} className="button button-quiet" onClick={() => void toggleFavorite()} type="button"><Heart fill={favorite ? 'currentColor' : 'none'} size={17} /> {favorite ? 'Quitar de favoritos' : 'Guardar en favoritos'}</button>}{active && <Link className="text-link" to="/history">Ver historial →</Link>}</div></div></header>{recipe.dietaryTags?.length ? <p className="recipe-cross-contamination-note" role="note"><strong>Importante:</strong> Las etiquetas describen ingredientes declarados, no garantizan ausencia de trazas. {recipe.crossContaminationNote ?? 'Verificá siempre los rótulos y las condiciones de preparación para evitar contaminación cruzada.'}</p> : null}{recipe.calories !== undefined && <p className="recipe-energy-note">{proportion ? `Una porción equivale aproximadamente al ${proportion.minimum}–${proportion.maximum}% de tu rango calórico diario orientativo. ` : ''}Las calorías son una referencia orientativa y pueden variar según marcas, preparación y cantidad real servida. El total de la preparación se ajusta al número de porciones y no registra una comida consumida.</p>}<div className="recipe-detail-layout"><section className="surface"><div className="recipe-detail-section-heading"><div><h2>Ingredientes</h2><p className="recipe-section-lead">Cantidades ajustadas para esta preparación.</p></div><div className="recipe-portions-control"><button aria-label="Disminuir porciones" disabled={portions <= 1} onClick={() => setPortions(Math.max(1, portions - 1))} type="button"><Minus size={16} /></button><output aria-live="polite">{portions}</output><button aria-label="Aumentar porciones" disabled={portions >= 20} onClick={() => setPortions(Math.min(20, portions + 1))} type="button"><Plus size={16} /></button></div></div><p className="recipe-availability">{readiness?.label ?? 'Consultando stock'}{readiness && ` · ${readiness.percentage}%`}</p><ul className="recipe-ingredient-list">{ingredientRows.map(({ ingredient, available, required, missing }) => <li key={`${ingredient.name}-${ingredient.unit}`}><span><strong>{ingredient.name}</strong><small>{missing > 0 ? `Tenés ${formatPantryAmount(available, ingredient.unit)} · faltan ${formatPantryAmount(missing, ingredient.unit)}` : 'Disponible en tu despensa'}</small></span><span>{formatPantryAmount(required, ingredient.unit)}</span></li>)}</ul>{active && <div className="recipe-ingredient-actions"><button className="button button-primary" disabled={!readiness || readiness.ingredients.every((item) => item.missing === 0)} onClick={() => void sendMissingToShopping()} type="button">Enviar faltantes a compras</button><Link className="text-link" to="/pantry">Revisar despensa →</Link></div>}</section><section className="surface"><h2>Preparación</h2><ol className="recipe-step-list">{recipe.steps.map((step) => <li key={step}>{step}</li>)}</ol></section></div></div>
}
