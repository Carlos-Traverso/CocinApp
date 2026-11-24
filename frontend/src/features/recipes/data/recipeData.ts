import type { RecipeRepository } from './RecipeRepository'
import { isRelationalRecipesEnabled, isSupabaseConfigured } from '../../../shared/data/supabaseClient'
import { supabaseRecipeRepository } from './SupabaseRecipeRepository'
import { getAvailableRecipes, getKnownRecipes, getRecipeById } from './availableRecipes'
import { filterRecipes, getRecipeReadiness, type RecipeFilters } from '../domain/recipeRules'
import type { PantryItem } from '../../pantry/domain/pantry'
import { profileRepository } from '../../profile/data/ProfileRepository'
import { getAdminData } from '../../admin/data/localAdminStore'

const legacyRecipeRepository: RecipeRepository = {
  async list() { return getAvailableRecipes() },
  async listKnown() { return getKnownRecipes() },
  async getById(id: string, includeInactive = false) { return getRecipeById(id, includeInactive) },
  async match(pantry: PantryItem[], filters: Partial<RecipeFilters> = {}, portions?: number) {
    const catalog = getAdminData()
    const today = new Date()
    const recipes = filterRecipes(getAvailableRecipes(catalog), {
      search: '', category: '', maxMinutes: null, difficulty: '', pantryOnly: false, ...filters,
    }, pantry, today, catalog.units)
    return recipes.map((recipe) => {
      const { percentage, label, ingredients } = getRecipeReadiness(recipe, pantry, portions ?? recipe.portions, today, catalog.units.length ? catalog.units : undefined)
      return { recipe, percentage, label, ingredients }
    })
  },
  async getReadiness(id, pantry, portions, includeInactive = false) {
    const catalog = getAdminData()
    const recipe = getRecipeById(id, includeInactive, catalog)
    if (!recipe) return undefined
    const { percentage, label, ingredients } = getRecipeReadiness(recipe, pantry, portions ?? recipe.portions, new Date(), catalog.units.length ? catalog.units : undefined)
    return { percentage, label, ingredients }
  },
  async getDietaryPreferences() { return (await profileRepository.getProfile()).preferences ?? [] },
  async getProfile() { return profileRepository.getProfile() },
}

export const recipeRepository: RecipeRepository = isSupabaseConfigured && isRelationalRecipesEnabled
  ? supabaseRecipeRepository : legacyRecipeRepository
