import { readMealPlan, writeMealPlan } from './localMealPlanStore'
import { setPlannedMeal, type Meal } from '../domain/planner'
import type { PlannerRepository } from './PlannerRepository'
import { getAvailableRecipes, getKnownRecipes } from '../../recipes/data/availableRecipes'
import { mockShoppingRepository } from '../../shopping/data/MockShoppingRepository'

export const mockPlannerRepository: PlannerRepository = {
  async list() { return readMealPlan() },
  async loadRecipes() { return { known: getKnownRecipes(), available: getAvailableRecipes() } },
  async save(plan) { writeMealPlan(plan) },
  async assign(date: string, meal: Meal, recipeId: string, portions: number) {
    const next = setPlannedMeal(readMealPlan(), date, meal, recipeId, portions)
    writeMealPlan(next)
    return next
  },
  async generateShopping(dates: string[]) {
    const suggestions = await mockShoppingRepository.suggestionsFromWeek(dates)
    return (await mockShoppingRepository.append(suggestions)).length
  },
}
