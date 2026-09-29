import { sampleRecipes } from '../../../mocks/recipes'
import type { Recipe } from '../domain/Recipe'

export const recipeSeedVersion = 3
export const recipeSeed: readonly Recipe[] = sampleRecipes

export function mergeRecipeSeed(seed: readonly Recipe[], administratorRecipes: readonly Recipe[]): Recipe[] {
  const catalog = new Map(seed.map((recipe): [string, Recipe] => [recipe.id, recipe]))
  for (const recipe of administratorRecipes) catalog.set(recipe.id, recipe)
  return [...catalog.values()]
}
