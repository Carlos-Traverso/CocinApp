import { mockShoppingRepository } from '../../shopping/data/MockShoppingRepository'
import { suggestForRecipes } from '../../shopping/domain/shopping'
import type { PantryItem } from '../../pantry/domain/pantry'
import type { Recipe } from '../domain/Recipe'
import { isRelationalShoppingEnabled, supabase } from '../../../shared/data/supabaseClient'
import { capturePersonalDataSession, assertPersonalDataSessionCurrent } from '../../../shared/data/personalDataSession'

/** Async mock action boundary so a remote shopping service can replace local persistence. */
export async function addRecipeToShopping(recipe: Recipe, pantry: PantryItem[], portions = recipe.portions): Promise<void> {
  const session = capturePersonalDataSession()
  const { catalog } = await mockShoppingRepository.load()
  const suggestions = suggestForRecipes([recipe], pantry, 'recipe', new Date(), catalog.units, new Map([[recipe.id, portions]]))
  if (isRelationalShoppingEnabled && supabase) {
    const { data, error } = await supabase.rpc('get_my_recipe_detail', recipe.relationalId
      ? { p_recipe_id: recipe.relationalId, p_legacy_id: null }
      : { p_recipe_id: null, p_legacy_id: recipe.legacyId ?? recipe.id })
    assertPersonalDataSessionCurrent(session)
    if (error) throw error
    const recipeId = data?.recipe?.id
    if (typeof recipeId !== 'string') throw new Error('La receta todavía no está disponible en el catálogo relacional.')
    await mockShoppingRepository.append(suggestions.map((suggestion) => ({ ...suggestion,
      sourceLinks: [{ source: 'recipe' as const, recipe_id: recipeId }],
    })))
    return
  }
  assertPersonalDataSessionCurrent(session)
  await mockShoppingRepository.append(suggestions)
}
