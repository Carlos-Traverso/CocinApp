import type { Meal, PlannedMeal } from '../domain/planner'
import type { Recipe } from '../../recipes/domain/Recipe'

export interface PlannerRepository {
  list(): Promise<PlannedMeal[]>
  loadRecipes(): Promise<{ known: Recipe[]; available: Recipe[] }>
  save(plan: PlannedMeal[]): Promise<void>
  assign(date: string, meal: Meal, recipeId: string, portions: number): Promise<PlannedMeal[]>
  generateShopping(dates: string[]): Promise<number>
}
