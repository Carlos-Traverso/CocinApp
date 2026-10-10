import type { CookingSession, PreparationEvent } from '../domain/cooking'
import type { Recipe } from '../../recipes/domain/Recipe'
import type { IngredientDeficit } from '../../recipes/domain/recipeRules'

export interface CookingRepository {
  getSession(recipeId: string): Promise<CookingSession | null>
  saveSession(session: CookingSession): Promise<void>
  getHistory(): Promise<PreparationEvent[]>
  removeHistoryEntry(eventId: string): Promise<void>
  clearHistory(): Promise<void>
  checkStock(recipe: Recipe, portions: number): Promise<IngredientDeficit[]>
  finalize(recipe: Recipe, session: CookingSession, discount: boolean): Promise<{ history: PreparationEvent[]; exhaustedIngredients: string[] }>
}
