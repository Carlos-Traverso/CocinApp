import { readMealPlan, writeMealPlan } from './localMealPlanStore'
import { setPlannedMeal, type Meal } from '../domain/planner'
import type { PlannerRepository } from './PlannerRepository'
import { getAvailableRecipes, getKnownRecipes } from '../../recipes/data/availableRecipes'
import { mockShoppingRepository } from '../../shopping/data/MockShoppingRepository'
import { isSupabaseConfigured } from '../../../shared/data/supabaseClient'
import { loadPersonalData, savePersonalData } from '../../../shared/data/personalDataRepository'

async function loadPlan() {
  if (!isSupabaseConfigured) return readMealPlan()
  const remote = await loadPersonalData('meal_plan')
  if (remote !== null) {
    writeMealPlan(Array.isArray(remote) ? remote as Awaited<ReturnType<typeof readMealPlan>> : [])
    return readMealPlan()
  }
  const local = readMealPlan()
  if (local.length) await savePersonalData('meal_plan', local)
  return local
}

async function savePlan(plan: Awaited<ReturnType<typeof readMealPlan>>) {
  if (isSupabaseConfigured) await savePersonalData('meal_plan', plan)
  writeMealPlan(plan)
}

export const mockPlannerRepository: PlannerRepository = {
  async list() { return loadPlan() },
  async loadRecipes() { return { known: getKnownRecipes(), available: getAvailableRecipes() } },
  async save(plan) { await savePlan(plan) },
  async assign(date: string, meal: Meal, recipeId: string, portions: number) {
    const next = setPlannedMeal(await loadPlan(), date, meal, recipeId, portions)
    await savePlan(next)
    return next
  },
  async generateShopping(dates: string[]) {
    const suggestions = await mockShoppingRepository.suggestionsFromWeek(dates)
    return (await mockShoppingRepository.append(suggestions)).length
  },
}
