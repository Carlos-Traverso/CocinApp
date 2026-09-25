import type { RecipeRepository } from './RecipeRepository'
import { sampleRecipes } from '../../../mocks/recipes'
import { getAdminData } from '../../admin/data/localAdminStore'
import type { Recipe } from '../domain/Recipe'

export const mockRecipeRepository: RecipeRepository = {
  async list() {
    const adminData = getAdminData()
    // Convert AdminRecipes to domain Recipes
    const convertedAdminRecipes: Recipe[] = adminData.recipes.filter(r => !r.isDeleted && r.status === 'published').map(r => {
      return {
        id: r.id,
        name: r.title,
        description: r.description,
        category: r.category,
        minutes: r.minutes,
        portions: r.portions,
        difficulty: r.difficulty,
        steps: r.steps,
        symbol: r.symbol,
        color: r.color,
        ingredients: r.ingredients.map(ing => {
          const adminIngredient = adminData.ingredients.find(i => i.id === ing.ingredientId)
          const adminUnit = adminData.units.find(u => u.id === ing.unitId)
          return {
            name: adminIngredient ? adminIngredient.name : 'Desconocido',
            quantity: ing.quantity,
            unit: (adminUnit ? adminUnit.abbreviation : 'u') as 'g'|'ml'|'u'
          }
        })
      }
    })
    
    return [...sampleRecipes, ...convertedAdminRecipes]
  },
}
