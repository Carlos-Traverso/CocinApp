import type { PreparationEvent } from '../../cooking/domain/cooking'
import type { PantryItem } from '../../pantry/domain/pantry'
import type { Recipe } from './Recipe'
import type { DietaryPreference } from '../../profile/domain/profile'
import type { AdminUnit } from '../../admin/domain/adminModels'
import { discoverRecipes } from './recipeDiscovery'
import { getIngredientAvailability, matchesDietaryPreferences } from './recipeRules'

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
  preferences: DietaryPreference[] = [],
  units?: AdminUnit[],
): RecipeRecommendations {
  const active = activeRecipes.filter((recipe) => matchesDietaryPreferences(recipe, preferences))
  const known = knownRecipes.filter((recipe) => matchesDietaryPreferences(recipe, preferences))
  const discovery = discoverRecipes(active, known, favoriteIds, history)
  const featured = discovery.featured.slice(0, 4)
  const pantryReady = active.filter((recipe) => getIngredientAvailability(recipe, pantry, today, units).missing.length === 0).slice(0, 4)
  const quick = active.filter((recipe) => recipe.minutes <= 20).sort((a, b) => a.minutes - b.minutes || a.name.localeCompare(b.name, 'es')).slice(0, 4)

  return {
    hero: discovery.basedOnHistory[0] ?? pantryReady[0] ?? featured[0] ?? active[0],
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
