import type { Recipe } from '../../recipes/domain/Recipe'
import { normalizePantryName } from '../../pantry/domain/pantry'
import type { AdminStorageData } from '../data/localAdminStore'

export function countAdminUsage(data: AdminStorageData, recipes: Recipe[]) {
  const ingredients = Object.fromEntries(data.ingredients.map((ingredient) => {
    const normalized = normalizePantryName(ingredient.name)
    return [ingredient.id, recipes.filter((recipe) => recipe.ingredients.some((entry) => normalizePantryName(entry.name) === normalized)).length]
  }))
  const categories = Object.fromEntries(data.categories.map((category) => {
    const ingredientIds = new Set(data.ingredients.filter((ingredient) => ingredient.categoryId === category.id).map((ingredient) => ingredient.id))
    const ingredientNames = new Set(data.ingredients.filter((ingredient) => ingredientIds.has(ingredient.id)).map((ingredient) => normalizePantryName(ingredient.name)))
    return [category.id, recipes.filter((recipe) => recipe.ingredients.some((ingredient) => ingredientNames.has(normalizePantryName(ingredient.name)))).length]
  }))
  const units = Object.fromEntries(data.units.map((unit) => [unit.id,
    data.ingredients.filter((ingredient) => ingredient.baseUnitId === unit.id).length
      + data.recipes.reduce((total, recipe) => total + recipe.ingredients.filter((ingredient) => ingredient.unitId === unit.id).length, 0),
  ]))
  return { ingredients, categories, units }
}
