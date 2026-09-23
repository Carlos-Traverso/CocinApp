import type { Recipe } from '../domain/Recipe'

export interface RecipeRepository {
  list(): Promise<Recipe[]>
}
