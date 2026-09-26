import { useState } from 'react'
import { ArrowLeft, Clock3, Heart, UsersRound } from 'lucide-react'
import { Link, useParams } from 'react-router-dom'
import { readPantryItems } from '../features/pantry/data/localPantryStore'
import { formatPantryAmount } from '../features/pantry/domain/pantry'
import { readLocalProfile } from '../features/profile/data/localProfileStore'
import { estimateForProfile, recipeGoalPercentageRange } from '../features/profile/domain/profile'
import { readFavoriteIds, writeFavoriteIds } from '../features/recipes/data/localFavoritesStore'
import { getIngredientAvailability } from '../features/recipes/domain/recipeRules'
import { appendShoppingSuggestions } from '../features/shopping/data/localShoppingStore'
import { suggestForRecipes } from '../features/shopping/domain/shopping'
import { getAvailableRecipes, getRecipeById } from '../features/recipes/data/availableRecipes'

export function RecipeDetailPage() {
  const { id } = useParams()
  const recipe = getRecipeById(id ?? '', true)
  const isActive = getAvailableRecipes().some((item) => item.id === recipe?.id)
  const [pantry] = useState(readPantryItems)
  const [favoriteIds, setFavoriteIds] = useState(readFavoriteIds)
  const [error, setError] = useState('')
  const [shoppingNotice, setShoppingNotice] = useState('')
  if (!recipe) return <div className="page"><Link className="back-link" to="/recipes"><ArrowLeft size={16} /> Recetas</Link><h1>Receta no encontrada</h1></div>
  const availability = getIngredientAvailability(recipe, pantry)
  const favorite = favoriteIds.includes(recipe.id)
  const estimate = estimateForProfile(readLocalProfile())
  const proportion = recipe.calories !== undefined && estimate ? recipeGoalPercentageRange(recipe.calories, estimate) : undefined
  function toggleFavorite() {
    if (!isActive && !favorite) return
    const next = favorite ? favoriteIds.filter((item) => item !== recipe!.id) : [...favoriteIds, recipe!.id]
    try { writeFavoriteIds(next); setFavoriteIds(next); setError('') }
    catch { setError('No se pudo guardar el favorito en este navegador.') }
  }
  function sendMissingToShopping() {
    try {
      appendShoppingSuggestions(suggestForRecipes([recipe!], readPantryItems(), 'recipe'))
      setShoppingNotice('Faltantes añadidos a la lista de compras.')
      setError('')
    } catch {
      setShoppingNotice('')
      setError('No se pudo guardar la lista de compras en este navegador.')
    }
  }
  return <div className="page recipe-detail-page"><Link className="back-link" to="/recipes"><ArrowLeft size={16} /> Volver a recetas</Link><header className="recipe-detail-header"><div className={`recipe-art ${recipe.color}`} aria-hidden="true"><span>{recipe.symbol}</span></div><div><p className="eyebrow">{recipe.mealShift || recipe.category}</p><h1>{recipe.name}</h1><p className="page-lead">{recipe.description}</p>{!isActive && <p className="form-message">Receta inactiva: se conserva para consulta histórica.</p>}<div className="recipe-detail-meta"><span><Clock3 size={17} /> {recipe.minutes} min</span><span><UsersRound size={17} /> {recipe.portions} porciones</span><span>{recipe.difficulty}</span>{recipe.calories !== undefined && <span>{recipe.calories} kcal por porción (referencia)</span>}</div>{recipe.dietaryTags && recipe.dietaryTags.length > 0 && <p className="page-lead">Etiquetas: {recipe.dietaryTags.join(', ')}</p>}<div className="recipe-detail-actions">{isActive && <Link className="button button-primary" to={`/recipes/${recipe.id}/cook`}>Iniciar modo cocina</Link>}{(isActive || favorite) && <button aria-pressed={favorite} className="button button-quiet" onClick={toggleFavorite} type="button"><Heart fill={favorite ? 'currentColor' : 'none'} size={17} /> {favorite ? 'Quitar de favoritos' : 'Guardar en favoritos'}</button>}{isActive && <Link className="text-link" to="/history">Ver historial →</Link>}</div></div></header>{proportion && <p className="recipe-energy-note">Una porción equivale aproximadamente al {proportion.minimum}–{proportion.maximum}% de tu rango calórico diario orientativo. No registra una comida consumida.</p>}{shoppingNotice && <p className="form-message pantry-notice" role="status">{shoppingNotice} <Link className="text-link" to="/shopping">Abrir Compras</Link></p>}{error && <p className="form-message error" role="alert">{error}</p>}<div className="recipe-detail-layout"><section className="surface"><h2>Ingredientes</h2><p className="recipe-section-lead">Cantidades para {recipe.portions} porciones. La disponibilidad usa el stock actual de tu despensa.</p><ul className="recipe-ingredient-list">{recipe.ingredients.map((ingredient) => { const available = availability.available.includes(ingredient); return <li key={ingredient.name}><span><strong>{ingredient.name}</strong><small>{available ? 'Disponible' : 'Falta en tu despensa'}</small></span><span>{formatPantryAmount(ingredient.quantity, ingredient.unit)}</span></li> })}</ul>{isActive && <><p className="recipe-availability">{availability.available.length} disponibles · {availability.missing.length} faltantes</p><div className="recipe-ingredient-actions"><button className="button button-primary" disabled={availability.missing.length === 0} onClick={sendMissingToShopping} type="button">Enviar faltantes a compras</button><Link className="text-link" to="/pantry">Revisar despensa →</Link></div></>}</section><section className="surface"><h2>Preparación</h2><ol className="recipe-step-list">{recipe.steps.map((step) => <li key={step}>{step}</li>)}</ol></section></div></div>
}
