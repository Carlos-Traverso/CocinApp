import { readMealPlan, writeMealPlan } from './localMealPlanStore'
import { setPlannedMeal, type Meal } from '../domain/planner'
import type { PlannerRepository } from './PlannerRepository'
import { getAvailableRecipes, getKnownRecipes } from '../../recipes/data/availableRecipes'
import { mockShoppingRepository } from '../../shopping/data/MockShoppingRepository'
import { isSupabaseConfigured } from '../../../shared/data/supabaseClient'
import { loadPersonalData, savePersonalData } from '../../../shared/data/personalDataRepository'
import { assertPersonalDataSessionCurrent, capturePersonalDataSession, type PersonalDataSession } from '../../../shared/data/personalDataSession'

async function loadPlan(session: PersonalDataSession) {
  if (!isSupabaseConfigured) return readMealPlan()
  const remote = await loadPersonalData('meal_plan', session)
  assertPersonalDataSessionCurrent(session)
  if (remote !== null) {
    writeMealPlan(Array.isArray(remote) ? remote as Awaited<ReturnType<typeof readMealPlan>> : [])
    return readMealPlan()
  }
  const local = readMealPlan()
  if (local.length) await savePersonalData('meal_plan', local, session)
  assertPersonalDataSessionCurrent(session)
  return local
}

async function savePlan(plan: Awaited<ReturnType<typeof readMealPlan>>, session: PersonalDataSession) {
  if (isSupabaseConfigured) await savePersonalData('meal_plan', plan, session)
  assertPersonalDataSessionCurrent(session)
  writeMealPlan(plan)
}

export const mockPlannerRepository: PlannerRepository = {
  async list() { return loadPlan(capturePersonalDataSession()) },
  async loadRecipes() { return { known: getKnownRecipes(), available: getAvailableRecipes() } },
  async save(plan) { const session = capturePersonalDataSession(); await savePlan(plan, session) },
  async assign(date: string, meal: Meal, recipeId: string, portions: number) {
    const session = capturePersonalDataSession()
    const next = setPlannedMeal(await loadPlan(session), date, meal, recipeId, portions)
    assertPersonalDataSessionCurrent(session)
    await savePlan(next, session)
    return next
  },
  async generateShopping(dates: string[]) {
    const suggestions = await mockShoppingRepository.suggestionsFromWeek(dates)
    return (await mockShoppingRepository.append(suggestions)).length
  },
}
