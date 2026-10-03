import type { PreparationEvent } from '../../cooking/domain/cooking'
import type { PantryItem } from '../../pantry/domain/pantry'
import type { Recipe } from './Recipe'
import { discoverRecipes } from './recipeDiscovery'
import { getIngredientAvailability } from './recipeRules'

export type RecipeRecommendationSectionId =
  | 'recipe-featured'
  | 'recipe-pantry-ready'
  | 'recipe-history-based'
  | 'recipe-recook'
  | 'recipe-favorites'
  | 'recipe-quick'

export interface RecipeRecommendationSection {
  id: RecipeRecommendationSectionId
  recipes: Recipe[]
}

export interface RecipeRecommendations {
  hero?: Recipe
  sections: RecipeRecommendationSection[]
}

export function buildRecipeRecommendations(
  activeRecipes: Recipe[],
  knownRecipes: Recipe[],
  pantry: PantryItem[],
  favoriteIds: string[],
  history: PreparationEvent[],
  today = new Date(),
): RecipeRecommendations {
  const discovery = discoverRecipes(activeRecipes, knownRecipes, favoriteIds, history)
  const featured = discovery.featured.slice(0, 4)
  const pantryReady = activeRecipes.filter((recipe) => getIngredientAvailability(recipe, pantry, today).missing.length === 0).slice(0, 4)
  const quick = activeRecipes.filter((recipe) => recipe.minutes <= 20).sort((a, b) => a.minutes - b.minutes || a.name.localeCompare(b.name, 'es')).slice(0, 4)

  return {
    hero: discovery.basedOnHistory[0] ?? pantryReady[0] ?? featured[0] ?? activeRecipes[0],
    sections: [
      { id: 'recipe-featured', recipes: featured },
      { id: 'recipe-pantry-ready', recipes: pantryReady },
      { id: 'recipe-history-based', recipes: discovery.basedOnHistory },
      { id: 'recipe-recook', recipes: discovery.recook },
      { id: 'recipe-favorites', recipes: discovery.favorites },
      { id: 'recipe-quick', recipes: quick },
    ],
  }
}
