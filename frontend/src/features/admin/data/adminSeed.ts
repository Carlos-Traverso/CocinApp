import { recipeSeed } from '../../recipes/data/recipeSeed'
import { defaultPantryCategories, normalizePantryName } from '../../pantry/domain/pantry'
import type { AdminStorageData } from './localAdminStore'
import { inferIngredientCategory } from '../domain/ingredientCategory'

export const adminCatalogVersion = 4

export const seedUnitDefinitions = {
  g: { name: 'Gramo', dimension: 'masa' as const },
  kg: { name: 'Kilogramo', dimension: 'masa' as const },
  ml: { name: 'Mililitro', dimension: 'volumen' as const },
  l: { name: 'Litro', dimension: 'volumen' as const },
  u: { name: 'Unidad', dimension: 'conteo' as const },
}

export function adminSeedId(prefix: string, value: string): string {
  return `seed-${prefix}-${normalizePantryName(value).replace(/[^a-z0-9]+/g, '-').replace(/(^-|-$)/g, '')}`
}

export function createInitialAdminData(): AdminStorageData {
  const categories = defaultPantryCategories.map((name) => ({ id: adminSeedId('category', name), name, active: true, isDeleted: false }))
  const units = Object.entries(seedUnitDefinitions).map(([abbreviation, definition]) => {
    const baseAbbreviation = definition.dimension === 'masa' ? 'g' : definition.dimension === 'volumen' ? 'ml' : 'u'
    return {
      id: adminSeedId('unit', abbreviation),
      name: definition.name,
      abbreviation,
      dimension: definition.dimension,
      baseUnitId: baseAbbreviation === abbreviation ? undefined : adminSeedId('unit', baseAbbreviation),
      equivalenceMultiplier: abbreviation === 'kg' || abbreviation === 'l' ? 1000 : undefined,
      active: true,
      isDeleted: false,
    }
  })
  const ingredientsById = new Map<string, AdminStorageData['ingredients'][number]>()
  for (const recipe of recipeSeed) {
    for (const ingredient of recipe.ingredients) {
      const id = adminSeedId('ingredient', ingredient.name)
      if (!ingredientsById.has(id)) ingredientsById.set(id, {
        id,
        name: ingredient.name,
        categoryId: adminSeedId('category', inferIngredientCategory(ingredient.name) ?? 'Otros'),
        baseUnitId: adminSeedId('unit', ingredient.unit in seedUnitDefinitions ? ingredient.unit : 'u'),
        active: true,
        isDeleted: false,
      })
    }
  }
  return { categories, units, ingredients: [...ingredientsById.values()], recipes: [] }
}
