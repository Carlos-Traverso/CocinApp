import { daysUntilExpiry, normalizePantryName, type PantryItem } from '../../pantry/domain/pantry'
import type { Recipe } from './Recipe'
import { getAdminData } from '../../admin/data/localAdminStore'

const defaultUnits: Record<string, { dimension: string; base: string; multiplier: number }> = {
  g: { dimension: 'masa', base: 'g', multiplier: 1 }, kg: { dimension: 'masa', base: 'g', multiplier: 1000 },
  ml: { dimension: 'volumen', base: 'ml', multiplier: 1 }, l: { dimension: 'volumen', base: 'ml', multiplier: 1000 },
  u: { dimension: 'conteo', base: 'u', multiplier: 1 },
}

function normalizeAmount(quantity: number, abbreviation: string) {
  const data = getAdminData()
  let unit = data.units.find((candidate) => !candidate.isDeleted && candidate.abbreviation.toLocaleLowerCase('es') === abbreviation.toLocaleLowerCase('es'))
  let amount = quantity
  const seen = new Set<string>()
  while (unit?.baseUnitId && !seen.has(unit.id)) {
    seen.add(unit.id)
    amount *= unit.equivalenceMultiplier ?? 0
    unit = data.units.find((candidate) => candidate.id === unit?.baseUnitId && !candidate.isDeleted)
  }
  if (unit) return { dimension: unit.dimension, base: unit.abbreviation.toLocaleLowerCase('es'), amount }
  const fallback = defaultUnits[abbreviation.toLocaleLowerCase('es')]
  return fallback ? { dimension: fallback.dimension, base: fallback.base, amount: amount * fallback.multiplier } : null
}

export interface RecipeFilters {
  search: string
  category: string
  maxMinutes: number | null
  difficulty: Recipe['difficulty'] | ''
  pantryOnly: boolean
}

export function getIngredientAvailability(recipe: Recipe, pantry: PantryItem[], today = new Date()) {
  const available: Recipe['ingredients'] = []
  const missing: Recipe['ingredients'] = []
  for (const ingredient of recipe.ingredients) {
    const required = normalizeAmount(ingredient.quantity, ingredient.unit)
    const quantity = pantry.filter((item) => normalizePantryName(item.name) === normalizePantryName(ingredient.name)
      && (!item.expiry || (daysUntilExpiry(item.expiry, today) ?? -1) >= 0))
      .reduce((sum, item) => {
        const stored = normalizeAmount(item.quantity, item.unit)
        return required && stored && stored.dimension === required.dimension && stored.base === required.base ? sum + stored.amount : sum
      }, 0)
    ;(required && quantity >= required.amount ? available : missing).push(ingredient)
  }
  return { available, missing }
}

export function filterRecipes(recipes: Recipe[], filters: RecipeFilters, pantry: PantryItem[], today = new Date()): Recipe[] {
  const search = normalizePantryName(filters.search)
  return recipes.filter((recipe) => {
    if (search && ![recipe.name, recipe.description, ...recipe.ingredients.map((item) => item.name)]
      .some((value) => normalizePantryName(value).includes(search))) return false
    if (filters.category && recipe.category !== filters.category) return false
    if (filters.maxMinutes !== null && recipe.minutes > filters.maxMinutes) return false
    if (filters.difficulty && recipe.difficulty !== filters.difficulty) return false
    return !filters.pantryOnly || getIngredientAvailability(recipe, pantry, today).missing.length === 0
  })
}
