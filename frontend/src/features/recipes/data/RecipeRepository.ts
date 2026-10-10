import type { Recipe } from '../domain/Recipe'
import type { PantryItem } from '../../pantry/domain/pantry'
import type { IngredientDeficit, RecipeFilters } from '../domain/recipeRules'
import type { DietaryPreference } from '../../profile/domain/profile'
import type { ProfileDraft } from '../../profile/domain/profile'

export interface RecipeRepository {
  list(): Promise<Recipe[]>
  listKnown(): Promise<Recipe[]>
  getById(id: string, includeInactive?: boolean): Promise<Recipe | undefined>
  match(pantry: PantryItem[], filters?: Partial<RecipeFilters>, portions?: number): Promise<Array<{ recipe: Recipe; percentage: number; label: string; ingredients: IngredientDeficit[] }>>
  getReadiness(id: string, pantry: PantryItem[], portions?: number, includeInactive?: boolean): Promise<{ percentage: number; label: string; ingredients: IngredientDeficit[] } | undefined>
  getDietaryPreferences(): Promise<DietaryPreference[]>
  getProfile(): Promise<ProfileDraft>
}
