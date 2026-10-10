import { mockShoppingRepository } from '../../shopping/data/MockShoppingRepository'
import { suggestForRecipes } from '../../shopping/domain/shopping'
import type { PantryItem } from '../../pantry/domain/pantry'
import type { Recipe } from '../domain/Recipe'

/** Async mock action boundary so a remote shopping service can replace local persistence. */
export async function addRecipeToShopping(recipe: Recipe, pantry: PantryItem[], portions = recipe.portions): Promise<void> {
  const { catalog } = await mockShoppingRepository.load()
  const suggestions = suggestForRecipes([recipe], pantry, 'recipe', new Date(), catalog.units, new Map([[recipe.id, portions]]))
  await mockShoppingRepository.append(suggestions)
}
