import { daysUntilExpiry, normalizePantryName, type PantryItem } from '../../pantry/domain/pantry'
import type { Recipe } from './Recipe'
import type { DietaryPreference } from '../../profile/domain/profile'
import { convertQuantity, normalizeQuantity, quantityDeficit, roundQuantity } from '../../../shared/domain/units'
import type { AdminUnit } from '../../admin/domain/adminModels'

export interface RecipeFilters {
  search: string
  category: string
  maxMinutes: number | null
  difficulty: Recipe['difficulty'] | ''
  pantryOnly: boolean
  preferences?: DietaryPreference[]
}

export function recipeMealShifts(recipe: Pick<Recipe, 'category' | 'mealShift' | 'mealShifts'>): string[] {
  if (recipe.mealShifts !== undefined) return [...recipe.mealShifts]
  return [recipe.mealShift || recipe.category]
}

export function parseRecipePortions(value: string | null): number | undefined {
  if (!value || !/^[1-9]\d?$/.test(value)) return undefined
  const portions = Number(value)
  return portions <= 20 ? portions : undefined
}

export function getIngredientAvailability(recipe: Recipe, pantry: PantryItem[], today = new Date(), units?: AdminUnit[]) {
  const deficits = getIngredientDeficits(recipe, pantry, recipe.portions, today, units)
  return { available: deficits.filter((item) => item.missing === 0).map((item) => item.ingredient), missing: deficits.filter((item) => item.missing > 0).map((item) => item.ingredient) }
}

export interface IngredientDeficit {
  ingredient: Recipe['ingredients'][number]
  available: number
  required: number
  missing: number
}

export function getIngredientDeficits(recipe: Recipe, pantry: PantryItem[], portions = recipe.portions, today = new Date(), units?: AdminUnit[]): IngredientDeficit[] {
  const scale = portions / recipe.portions
  const groups: Array<{ key: string; ingredients: Recipe['ingredients'] }> = []
  for (const ingredient of recipe.ingredients) {
    const normalized = normalizeQuantity(1, ingredient.unit, units)
    const key = `${normalizePantryName(ingredient.name)}:${normalized ? `${normalized.dimension}:${normalized.baseUnit}` : `invalid:${ingredient.unit}`}`
    const compatible = groups.find((group) => group.key === key
      && (group.ingredients[0]?.unit === ingredient.unit || convertQuantity(ingredient.quantity, ingredient.unit, group.ingredients[0]!.unit, units) !== null))
    if (compatible) compatible.ingredients.push(ingredient)
    else groups.push({ key, ingredients: [ingredient] })
  }
  return groups.flatMap(({ ingredients: group }) => {
    const unit = group[0]?.unit
    if (!unit) return []
    const required = roundQuantity(group.reduce((sum, item) => sum + (convertQuantity(item.quantity * scale, item.unit, unit, units) ?? (item.unit === unit ? item.quantity * scale : 0)), 0))
    const name = normalizePantryName(group[0]!.name)
    const available = pantry.filter((item) => normalizePantryName(item.name) === name
      && (!item.expiry || (daysUntilExpiry(item.expiry, today) ?? -1) >= 0))
      .reduce((sum, item) => sum + (convertQuantity(item.quantity, item.unit, unit, units) ?? 0), 0)
    const missing = quantityDeficit(required, available)
    const ingredient = { ...group[0]!, quantity: required, unit }
    return [{ ingredient, available, required, missing }]
  })
}

export function getRecipeReadiness(recipe: Recipe, pantry: PantryItem[], portions = recipe.portions, today = new Date(), units?: AdminUnit[]) {
  const ingredients = getIngredientDeficits(recipe, pantry, portions, today, units)
  const missing = ingredients.filter((item) => item.missing > 0)
  const ratio = ingredients.length ? (ingredients.length - missing.length) / ingredients.length * 100 : 0
  const percentage = ratio === 100 ? 100 : Math.min(99, Math.round(ratio))
  return { percentage, label: ratio === 100 ? 'Lista para cocinar' : ratio >= 60 ? 'Casi lista' : 'Requiere compra', ingredients, missing }
}

const preferenceTags: Record<DietaryPreference, string[]> = {
  'gluten-free': ['sin tacc', 'sin gluten', 'gluten free', 'apto celiaco', 'apta celiaca'],
  vegetarian: ['vegetariana', 'vegetariano', 'vegetarian'],
  vegan: ['vegana', 'vegano', 'vegan'],
  'lactose-free': ['sin lactosa', 'lactose free'],
  'nut-free': ['sin frutos secos', 'sin nueces', 'nut free'],
}

export function matchesDietaryPreferences(recipe: Recipe, preferences: DietaryPreference[] = []): boolean {
  const tags = new Set((recipe.dietaryTags ?? []).map(normalizePantryName))
  return preferences.every((preference) => preferenceTags[preference].some((tag) => tags.has(normalizePantryName(tag))))
}

export function filterRecipes(recipes: Recipe[], filters: RecipeFilters, pantry: PantryItem[], today = new Date(), units?: AdminUnit[]): Recipe[] {
  const search = normalizePantryName(filters.search)
  return recipes.filter((recipe) => {
    if (search && ![recipe.name, recipe.description, ...recipe.ingredients.map((item) => item.name)]
      .some((value) => normalizePantryName(value).includes(search))) return false
    if (filters.category && !recipeMealShifts(recipe).some((meal) => normalizePantryName(meal) === normalizePantryName(filters.category))) return false
    if (filters.maxMinutes !== null && recipe.minutes > filters.maxMinutes) return false
    if (filters.difficulty && recipe.difficulty !== filters.difficulty) return false
    if (!matchesDietaryPreferences(recipe, filters.preferences)) return false
    return !filters.pantryOnly || getIngredientAvailability(recipe, pantry, today, units).missing.length === 0
  })
}
