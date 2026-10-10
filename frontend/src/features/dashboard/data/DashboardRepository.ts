import type { Recipe } from '../../recipes/domain/Recipe'
import type { PantryItem } from '../../pantry/domain/pantry'
import type { PreparationEvent } from '../../cooking/domain/cooking'
import type { PlannedMeal } from '../../planner/domain/planner'
import type { ProfileDraft } from '../../profile/domain/profile'
import type { AdminUnit } from '../../admin/domain/adminModels'
import { mockRecipeRepository } from '../../recipes/data/MockRecipeRepository'
import { getPantryItems } from '../../pantry/data/localPantryStore'
import { getCookingHistory } from '../../cooking/data/localCookingStore'
import { getFavoriteIds } from '../../recipes/data/localFavoritesStore'
import { mockPlannerRepository } from '../../planner/data/MockPlannerRepository'
import { getAdminData } from '../../admin/data/localAdminStore'

export interface DashboardHomeData {
  recipes: Recipe[]
  knownRecipes: Recipe[]
  pantry: PantryItem[]
  history: PreparationEvent[]
  favoriteIds: string[]
  plannedMeals: PlannedMeal[]
  profile: ProfileDraft
  units: AdminUnit[]
}

export interface DashboardRepository {
  loadHome(): Promise<DashboardHomeData>
}

export const mockDashboardRepository: DashboardRepository = {
  async loadHome() {
    const [recipes, knownRecipes, pantry, history, favoriteIds, plannedMeals, profile] = await Promise.all([
      mockRecipeRepository.list(), mockRecipeRepository.listKnown(), getPantryItems(), getCookingHistory(), getFavoriteIds(), mockPlannerRepository.list(), mockRecipeRepository.getProfile(),
    ])
    return { recipes, knownRecipes, pantry, history, favoriteIds, plannedMeals, profile, units: getAdminData().units }
  },
}
