import type { PreparationEvent } from '../../cooking/domain/cooking'
import type { PantryItem } from '../../pantry/domain/pantry'
import type { Meal } from '../../planner/domain/planner'
import type { Recipe } from '../../recipes/domain/Recipe'
import { getIngredientAvailability } from '../../recipes/domain/recipeRules'

export interface CookingSuggestion {
  recipe: Recipe
  availableCount: number
  missingNames: string[]
  canCook: boolean
  reason: string
}

export interface RecommendationContext {
  pantry?: PantryItem[]
  favoriteIds?: string[]
  history?: PreparationEvent[]
  rotation?: number
  today?: Date
}

export interface TimeRecommendation { meal: Meal; recipe?: Recipe; reason?: string }

export function recentPreparations(history: PreparationEvent[], knownRecipeIds: Iterable<string>, limit = 4): PreparationEvent[] {
  const known = new Set(knownRecipeIds)
  return [...history].filter((event) => known.has(event.recipeId))
    .sort((first, second) => second.cookedAt.localeCompare(first.cookedAt)).slice(0, limit)
}

export function mealForHour(hour: number): Meal {
  const normalizedHour = ((Math.floor(hour) % 24) + 24) % 24
  if (normalizedHour >= 5 && normalizedHour < 11) return 'Desayuno'
  if (normalizedHour >= 11 && normalizedHour < 15) return 'Almuerzo'
  if (normalizedHour >= 15 && normalizedHour < 19) return 'Merienda'
  return 'Cena'
}

export function buildCookingSuggestions(recipes: Recipe[], pantry: PantryItem[], today = new Date(), limit = 4): CookingSuggestion[] {
  return recipes.flatMap((recipe): CookingSuggestion[] => {
    const availability = getIngredientAvailability(recipe, pantry, today)
    const missingNames = availability.missing.map((ingredient) => ingredient.name)
    if (missingNames.length > 2) return []
    const canCook = missingNames.length === 0
    return [{ recipe, availableCount: availability.available.length, missingNames, canCook,
      reason: canCook ? 'Tenés todos los ingredientes disponibles.' : `Te ${missingNames.length === 1 ? 'falta' : 'faltan'} ${missingNames.join(' y ')}.` }]
  }).sort((first, second) => Number(second.canCook) - Number(first.canCook)
    || first.missingNames.length - second.missingNames.length
    || second.availableCount - first.availableCount
    || first.recipe.minutes - second.recipe.minutes)
    .slice(0, limit)
}

function localRotation(date: Date): number {
  return Math.floor(new Date(date.getFullYear(), date.getMonth(), date.getDate()).getTime() / 86_400_000)
}

export function recommendRecipeForTime(recipes: Recipe[], hour: number, context: RecommendationContext = {}): TimeRecommendation {
  const meal = mealForHour(hour)
  const matching = recipes.filter((recipe) => recipe.mealShift === meal || recipe.category === meal)
  const candidates = matching.length > 0 ? matching : recipes
  if (candidates.length === 0) return { meal }
  const pantry = context.pantry ?? []
  const favorites = new Set(context.favoriteIds ?? [])
  const historyIds = new Set((context.history ?? []).map((event) => event.recipeId))
  const ranked = candidates.map((recipe) => {
    const availability = getIngredientAvailability(recipe, pantry, context.today)
    const canCook = availability.missing.length === 0 && recipe.ingredients.length > 0
    const favorite = favorites.has(recipe.id)
    const known = historyIds.has(recipe.id)
    const score = Number(canCook) * 8 + Number(favorite) * 4 + Number(known) * 2 + Number(recipe.featured === true)
    return { recipe, score, canCook, favorite, known }
  }).sort((first, second) => second.score - first.score || first.recipe.minutes - second.recipe.minutes || first.recipe.id.localeCompare(second.recipe.id))
  const bestScore = ranked[0].score
  const tied = ranked.filter((entry) => entry.score === bestScore)
  const rotation = context.rotation ?? localRotation(context.today ?? new Date())
  const selected = tied[((rotation % tied.length) + tied.length) % tied.length]
  const reasons = [`Es apropiada para ${meal.toLocaleLowerCase('es')}`]
  if (selected.canCook) reasons.push('podés prepararla con tu despensa')
  if (selected.favorite) reasons.push('está entre tus favoritas')
  else if (selected.known) reasons.push('ya forma parte de tu historial')
  else if (selected.recipe.featured) reasons.push('fue destacada por administración')
  return { meal, recipe: selected.recipe, reason: `${reasons.join(' y ')}.` }
}
