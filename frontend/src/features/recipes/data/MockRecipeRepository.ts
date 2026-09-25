import type { RecipeRepository } from './RecipeRepository'
import { getAvailableRecipes } from './availableRecipes'

export const mockRecipeRepository: RecipeRepository = {
  async list() { return getAvailableRecipes() },
}
