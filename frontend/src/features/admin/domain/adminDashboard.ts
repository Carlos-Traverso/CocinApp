import type { Recipe } from '../../recipes/domain/Recipe'
import type { AdminStorageData } from '../data/localAdminStore'

export function createAdminDashboard(data: AdminStorageData, knownRecipes?: Recipe[], availableRecipes?: Recipe[]) {
  const recipes = data.recipes
  const activeRecipes = recipes.filter((recipe) => recipe.status === 'published' && recipe.active && !recipe.isDeleted)
  const incomplete = recipes.filter((recipe) => !recipe.isDeleted && (recipe.ingredients.length === 0 || recipe.steps.length === 0)).length
  return {
    metrics: {
      total: knownRecipes?.length ?? recipes.length,
      active: availableRecipes?.length ?? activeRecipes.length,
      inactive: knownRecipes && availableRecipes ? knownRecipes.filter((recipe) => !availableRecipes.some((active) => active.id === recipe.id)).length : recipes.length - activeRecipes.length,
      featured: (availableRecipes ?? activeRecipes).filter((recipe) => recipe.featured).length,
    },
    catalog: {
      ingredients: data.ingredients.filter((item) => item.active && !item.isDeleted).length,
      categories: data.categories.filter((item) => item.active && !item.isDeleted).length,
      units: data.units.filter((item) => item.active && !item.isDeleted).length,
    },
    alerts: {
      missingImage: knownRecipes ? knownRecipes.filter((recipe) => !recipe.image).length : recipes.filter((recipe) => !recipe.isDeleted && !recipe.image).length,
      incomplete,
      drafts: recipes.filter((recipe) => !recipe.isDeleted && recipe.status === 'draft').length,
    },
    recent: [...recipes]
      .filter((recipe) => recipe.updatedAt || recipe.createdAt)
      .sort((first, second) => (second.updatedAt ?? second.createdAt ?? '').localeCompare(first.updatedAt ?? first.createdAt ?? ''))
      .slice(0, 5),
  }
}
