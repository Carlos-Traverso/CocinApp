import type { RecipeRepository } from './RecipeRepository'
import { getAvailableRecipes, getKnownRecipes, getRecipeById } from './availableRecipes'
import { filterRecipes, getRecipeReadiness, type RecipeFilters } from '../domain/recipeRules'
import type { PantryItem } from '../../pantry/domain/pantry'
import { readLocalProfile } from '../../profile/data/localProfileStore'
import { getAdminData } from '../../admin/data/localAdminStore'

export const mockRecipeRepository: RecipeRepository = {
  async list() { return getAvailableRecipes() },
  async listKnown() { return getKnownRecipes() },
  async getById(id: string, includeInactive = false) { return getRecipeById(id, includeInactive) },
  async match(pantry: PantryItem[], filters: Partial<RecipeFilters> = {}, portions?: number) {
    const recipes = filterRecipes(getAvailableRecipes(), {
      search: '', category: '', maxMinutes: null, difficulty: '', pantryOnly: false, ...filters,
    }, pantry, new Date(), getAdminData().units)
    return recipes.map((recipe) => {
      const { percentage, label, ingredients } = getRecipeReadiness(recipe, pantry, portions ?? recipe.portions, new Date(), getAdminData().units.length ? getAdminData().units : undefined)
      return { recipe, percentage, label, ingredients }
    })
  },
  async getReadiness(id, pantry, portions, includeInactive = false) {
    const recipe = getRecipeById(id, includeInactive)
    if (!recipe) return undefined
    const { percentage, label, ingredients } = getRecipeReadiness(recipe, pantry, portions ?? recipe.portions, new Date(), getAdminData().units.length ? getAdminData().units : undefined)
    return { percentage, label, ingredients }
  },
  async getDietaryPreferences() { return readLocalProfile().preferences ?? [] },
  async getProfile() { return readLocalProfile() },
}
