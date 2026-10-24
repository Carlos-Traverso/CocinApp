import { appendShoppingSuggestions, markAllShoppingPurchased, readShoppingItems, setShoppingPurchased, transferPurchasedToPantry, writeShoppingItems } from './localShoppingStore'
import type { ShoppingRepository } from './ShoppingRepository'
import { getAdminData } from '../../admin/data/localAdminStore'
import { readPantryItems } from '../../pantry/data/localPantryStore'
import { getFavoriteIds } from '../../recipes/data/localFavoritesStore'
import { getAvailableRecipes } from '../../recipes/data/availableRecipes'
import { readMealPlan } from '../../planner/data/localMealPlanStore'
import { suggestForRecipes, suggestPantryRestock } from '../domain/shopping'
import { isSupabaseConfigured } from '../../../shared/data/supabaseClient'
import { loadPersonalData, savePersonalData } from '../../../shared/data/personalDataRepository'
import type { ShoppingItem } from '../domain/shopping'
import { assertPersonalDataSessionCurrent, capturePersonalDataSession, type PersonalDataSession } from '../../../shared/data/personalDataSession'

async function loadShoppingItems(session: PersonalDataSession): Promise<ShoppingItem[]> {
  if (!isSupabaseConfigured) return readShoppingItems()
  const remote = await loadPersonalData('shopping', session)
  assertPersonalDataSessionCurrent(session)
  if (remote !== null) {
    writeShoppingItems(Array.isArray(remote) ? remote as ShoppingItem[] : [])
    return readShoppingItems()
  }
  const local = readShoppingItems()
  if (local.length) await savePersonalData('shopping', local, session)
  assertPersonalDataSessionCurrent(session)
  return local
}

async function saveShoppingItems(items: ShoppingItem[], session: PersonalDataSession): Promise<void> {
  if (isSupabaseConfigured) await savePersonalData('shopping', items, session)
  assertPersonalDataSessionCurrent(session)
  writeShoppingItems(items)
}

export const mockShoppingRepository: ShoppingRepository = {
  async list() { return loadShoppingItems(capturePersonalDataSession()) },
  async save(items) { const session = capturePersonalDataSession(); await saveShoppingItems(items, session) },
  async append(suggestions) { const session = capturePersonalDataSession(); const items = appendShoppingSuggestions(suggestions); await saveShoppingItems(items, session); return items },
  async setPurchased(id, checked) { const session = capturePersonalDataSession(); const items = setShoppingPurchased(id, checked); await saveShoppingItems(items, session); return items },
  async markAllPurchased() { const session = capturePersonalDataSession(); const items = markAllShoppingPurchased(); await saveShoppingItems(items, session); return items },
  async transferPurchased() { const session = capturePersonalDataSession(); const result = transferPurchasedToPantry(); await saveShoppingItems(result.items, session); return result },
  async load() { const session = capturePersonalDataSession(); const items = await loadShoppingItems(session); assertPersonalDataSessionCurrent(session); return { items, catalog: getAdminData() } },
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
