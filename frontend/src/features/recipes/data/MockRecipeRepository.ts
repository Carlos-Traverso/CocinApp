import type { RecipeRepository } from './RecipeRepository'
import { sampleRecipes } from '../../../mocks/recipes'

export const mockRecipeRepository: RecipeRepository = {
  async list() {
    return sampleRecipes
  },
}
