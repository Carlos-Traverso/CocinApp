import type { Recipe } from '../../recipes/domain/Recipe'
import type { AdminStorageData } from '../data/localAdminStore'

export function createAdminDashboard(data: AdminStorageData, knownRecipes: Recipe[], availableRecipes: Recipe[]) {
  const availableIds = new Set(availableRecipes.map((recipe) => recipe.id))
  const incomplete = data.recipes.filter((recipe) => !recipe.isDeleted && (recipe.ingredients.length === 0 || recipe.steps.length === 0)).length
  return {
    metrics: {
      total: knownRecipes.length,
      active: availableIds.size,
      inactive: knownRecipes.filter((recipe) => !availableIds.has(recipe.id)).length,
      featured: availableRecipes.filter((recipe) => recipe.featured).length,
    },
    catalog: {
      ingredients: data.ingredients.filter((item) => item.active && !item.isDeleted).length,
      categories: data.categories.filter((item) => item.active && !item.isDeleted).length,
      units: data.units.filter((item) => item.active && !item.isDeleted).length,
    },
    alerts: {
      missingImage: knownRecipes.filter((recipe) => !recipe.image).length,
      incomplete,
      drafts: data.recipes.filter((recipe) => !recipe.isDeleted && recipe.status === 'draft').length,
    },
    recent: [...data.recipes]
      .filter((recipe) => recipe.updatedAt || recipe.createdAt)
      .sort((first, second) => (second.updatedAt ?? second.createdAt ?? '').localeCompare(first.updatedAt ?? first.createdAt ?? ''))
      .slice(0, 5),
  }
}
