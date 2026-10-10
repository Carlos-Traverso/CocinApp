import { appendShoppingSuggestions, markAllShoppingPurchased, readShoppingItems, setShoppingPurchased, transferPurchasedToPantry, writeShoppingItems } from './localShoppingStore'
import type { ShoppingRepository } from './ShoppingRepository'
import { getAdminData } from '../../admin/data/localAdminStore'
import { readPantryItems } from '../../pantry/data/localPantryStore'
import { getFavoriteIds } from '../../recipes/data/localFavoritesStore'
import { getAvailableRecipes } from '../../recipes/data/availableRecipes'
import { readMealPlan } from '../../planner/data/localMealPlanStore'
import { suggestForRecipes, suggestPantryRestock } from '../domain/shopping'

export const mockShoppingRepository: ShoppingRepository = {
  async list() { return readShoppingItems() },
  async save(items) { writeShoppingItems(items) },
  async append(suggestions) { return appendShoppingSuggestions(suggestions) },
  async setPurchased(id, checked) { return setShoppingPurchased(id, checked) },
  async markAllPurchased() { return markAllShoppingPurchased() },
  async transferPurchased() { return transferPurchasedToPantry() },
  async load() { return { items: readShoppingItems(), catalog: getAdminData() } },
  async suggestionsFromFavorites() {
    const ids = await getFavoriteIds()
    return suggestForRecipes(getAvailableRecipes().filter((recipe) => ids.includes(recipe.id)), readPantryItems(), 'favorites', new Date(), getAdminData().units)
  },
  async suggestionsFromWeek(dates) {
    const dateSet = new Set(dates)
    const entries = readMealPlan().filter((entry) => dateSet.has(entry.date))
    const scheduled = entries.flatMap((entry) => {
      const recipe = getAvailableRecipes().find((item) => item.id === entry.recipeId)
      return recipe ? [{ recipe: { ...recipe, id: `${recipe.id}:${entry.date}:${entry.meal}` }, portions: entry.portions }] : []
    })
    return suggestForRecipes(scheduled.map((entry) => entry.recipe), readPantryItems(), 'plan', new Date(), getAdminData().units, new Map(scheduled.map((entry) => [entry.recipe.id, entry.portions])))
  },
  async suggestionsForRestock() { return suggestPantryRestock(readPantryItems(), new Date(), getAdminData().units) },
}
