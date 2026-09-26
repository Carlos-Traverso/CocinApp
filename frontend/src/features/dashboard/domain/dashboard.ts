import { getPantryFlags, type PantryItem } from '../../pantry/domain/pantry'
import { getIngredientAvailability } from '../../recipes/domain/recipeRules'
import type { Recipe } from '../../recipes/domain/Recipe'
import type { PlannedMeal } from '../../planner/domain/planner'
import type { ShoppingItem } from '../../shopping/domain/shopping'
import type { PreparationEvent } from '../../cooking/domain/cooking'
import { meals, weekDates } from '../../planner/domain/planner'
import { discoverRecipes, type RecipeDiscovery } from '../../recipes/domain/recipeDiscovery'

export interface DashboardData {
  pantry: PantryItem[]
  recipes: Recipe[]
  knownRecipes?: Recipe[]
  favoriteIds: string[]
  plan: PlannedMeal[]
  shopping: ShoppingItem[]
  history: PreparationEvent[]
}

export interface DashboardSummary {
  pantry: {
    totalItems: number
    lowStock: PantryItem[]
    expired: PantryItem[]
    expiringSoon: PantryItem[]
  }
  suggestedRecipes: { recipe: Recipe; availableCount: number; missingNames: string[]; canCook: boolean }[]
  favorites: Recipe[]
  todayMeals: (PlannedMeal & { recipe: Recipe })[]
  weeklyMealCount: number
  shopping: { pendingCount: number; completedCount: number; pendingItems: ShoppingItem[] }
  recentHistory: PreparationEvent[]
  discovery: RecipeDiscovery
}

function toLocalDate(date: Date): string {
  return `${date.getFullYear()}-${String(date.getMonth() + 1).padStart(2, '0')}-${String(date.getDate()).padStart(2, '0')}`
}

export function buildDashboardSummary(data: DashboardData, today = new Date()): DashboardSummary {
  const flags = data.pantry.map((item) => ({ item, flags: getPantryFlags(item, today) }))
  const week = new Set(weekDates(today))
  const todayKey = toLocalDate(today)
  const recipeById = new Map((data.knownRecipes ?? data.recipes).map((recipe) => [recipe.id, recipe]))
  const activeRecipeById = new Map(data.recipes.map((recipe) => [recipe.id, recipe]))
  const todayMeals = data.plan.flatMap((entry) => {
    const recipe = recipeById.get(entry.recipeId)
    return entry.date === todayKey && recipe ? [{ ...entry, recipe }] : []
  }).sort((first, second) => meals.indexOf(first.meal) - meals.indexOf(second.meal))
  const pendingItems = data.shopping.filter((item) => !item.checked)
  const discovery = discoverRecipes(data.recipes, data.knownRecipes ?? data.recipes, data.favoriteIds, data.history)

  return {
    pantry: {
      totalItems: data.pantry.length,
      lowStock: flags.filter(({ flags: itemFlags }) => itemFlags.low || itemFlags.empty).map(({ item }) => item),
      expired: flags.filter(({ flags: itemFlags }) => itemFlags.expired).map(({ item }) => item),
      expiringSoon: flags.filter(({ flags: itemFlags }) => itemFlags.soon).map(({ item }) => item),
    },
    suggestedRecipes: data.recipes.map((recipe) => {
      const availability = getIngredientAvailability(recipe, data.pantry, today)
      return {
        recipe,
        availableCount: availability.available.length,
        missingNames: availability.missing.map((ingredient) => ingredient.name),
        canCook: availability.missing.length === 0,
      }
    }).sort((first, second) => Number(second.canCook) - Number(first.canCook)
      || second.availableCount - first.availableCount
      || first.recipe.minutes - second.recipe.minutes),
    favorites: data.favoriteIds.flatMap((id) => {
      const recipe = activeRecipeById.get(id)
      return recipe ? [recipe] : []
    }),
    todayMeals,
    weeklyMealCount: data.plan.filter((entry) => week.has(entry.date) && recipeById.has(entry.recipeId)).length,
    shopping: {
      pendingCount: pendingItems.length,
      completedCount: data.shopping.length - pendingItems.length,
      pendingItems,
    },
    recentHistory: [...data.history]
      .filter((event) => recipeById.has(event.recipeId))
      .sort((first, second) => second.cookedAt.localeCompare(first.cookedAt))
      .slice(0, 4),
    discovery,
  }
}
