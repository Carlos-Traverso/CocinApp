import type { PreparationEvent } from '../../cooking/domain/cooking'
import { normalizePantryName } from '../../pantry/domain/pantry'
import type { Recipe } from './Recipe'

export interface RecipeDiscovery {
  featured: Recipe[]
  basedOnHistory: Recipe[]
  recook: Recipe[]
  favorites: Recipe[]
}

export function discoverRecipes(active: Recipe[], known: Recipe[], favoriteIds: string[], history: PreparationEvent[]): RecipeDiscovery {
  const activeById = new Map(active.map((recipe) => [recipe.id, recipe]))
  const knownById = new Map(known.map((recipe) => [recipe.id, recipe]))
  const recentIds = [...history].sort((a, b) => b.cookedAt.localeCompare(a.cookedAt)).map((event) => event.recipeId)
  const cookedIds = [...new Set(recentIds)]
  const cookedRecipes = cookedIds.flatMap((id) => {
    const recipe = knownById.get(id)
    return recipe ? [recipe] : []
  })
  const recook = cookedIds.flatMap((id) => {
    const recipe = activeById.get(id)
    return recipe ? [recipe] : []
  }).slice(0, 4)
  const cookedSet = new Set(cookedIds)
  const favoriteSet = new Set(favoriteIds)
  const basedOnHistory = active.filter((recipe) => !cookedSet.has(recipe.id) && !favoriteSet.has(recipe.id))
    .map((recipe) => {
      const ingredients = new Set(recipe.ingredients.map((item) => normalizePantryName(item.name)))
      const score = Math.max(0, ...cookedRecipes.map((cooked) =>
        (recipe.category === cooked.category ? 3 : 0)
        + cooked.ingredients.filter((item) => ingredients.has(normalizePantryName(item.name))).length))
      return { recipe, score }
    })
    .filter((entry) => entry.score > 0)
    .sort((a, b) => b.score - a.score || a.recipe.name.localeCompare(b.recipe.name, 'es') || a.recipe.id.localeCompare(b.recipe.id))
    .slice(0, 4)
    .map((entry) => entry.recipe)

  return {
    featured: active.filter((recipe) => recipe.featured).sort((a, b) => a.name.localeCompare(b.name, 'es')),
    basedOnHistory,
    recook,
    favorites: [...new Set(favoriteIds)].flatMap((id) => {
      const recipe = activeById.get(id)
      return recipe ? [recipe] : []
    }),
  }
}
