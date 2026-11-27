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
  const pantryReady = active.filter((recipe) => getIngredientAvailability(recipe, pantry, today, units).missing.length === 0)
  const quick = active.filter((recipe) => recipe.minutes <= 20).sort((a, b) => a.minutes - b.minutes || a.name.localeCompare(b.name, 'es'))
  const hero = discovery.basedOnHistory[0] ?? pantryReady[0] ?? discovery.featured[0] ?? active[0]
  const selected = new Set<string>()
  if (hero) selected.add(hero.id)

  function selectSection(id: RecipeRecommendationSectionId, candidates: Recipe[]): RecipeRecommendationSection {
    const recipes: Recipe[] = []
    for (const recipe of candidates) {
      if (selected.has(recipe.id)) continue
      selected.add(recipe.id)
      recipes.push(recipe)
      if (recipes.length === 4) break
    }
    return { id, recipes }
  }

  return {
    hero,
    sections: [
      selectSection('recipe-featured', discovery.featured),
      selectSection('recipe-pantry-ready', pantryReady),
      selectSection('recipe-history-based', discovery.basedOnHistory),
      selectSection('recipe-recook', discovery.recook),
      selectSection('recipe-favorites', discovery.favorites),
      selectSection('recipe-quick', quick),
    ],
  }
}
