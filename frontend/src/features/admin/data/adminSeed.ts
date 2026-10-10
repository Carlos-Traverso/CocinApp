import { recipeSeed } from '../../recipes/data/recipeSeed'
import { defaultPantryCategories, normalizePantryName } from '../../pantry/domain/pantry'
import type { AdminStorageData } from './localAdminStore'
import { inferIngredientCategory } from '../domain/ingredientCategory'

export const adminCatalogVersion = 6

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
      const definition = seedUnitDefinitions[ingredient.unit as keyof typeof seedUnitDefinitions] ?? { dimension: 'conteo' as const }
      const baseAbbreviation = definition.dimension === 'masa' ? 'g' : definition.dimension === 'volumen' ? 'ml' : 'u'
      if (!ingredientsById.has(id)) ingredientsById.set(id, {
        id,
        name: ingredient.name,
        categoryId: adminSeedId('category', inferIngredientCategory(ingredient.name) ?? 'Otros'),
        baseUnitId: adminSeedId('unit', baseAbbreviation),
        active: true,
        isDeleted: false,
      })
    }
  }
  return { categories, units, ingredients: [...ingredientsById.values()], recipes: [] }
}

export function migrateUneditedSeedDietaryTags(data: AdminStorageData): void {
  for (const ingredient of data.ingredients) {
    const seedIngredient = recipeSeed.flatMap((recipe) => recipe.ingredients).find((item) => adminSeedId('ingredient', item.name) === ingredient.id)
    if (!seedIngredient) continue
    const definition = seedUnitDefinitions[seedIngredient.unit as keyof typeof seedUnitDefinitions] ?? { dimension: 'conteo' as const }
    const baseAbbreviation = definition.dimension === 'masa' ? 'g' : definition.dimension === 'volumen' ? 'ml' : 'u'
    const oldBaseAbbreviation = seedIngredient.unit in seedUnitDefinitions ? seedIngredient.unit : 'u'
    const previousSeedBaseId = adminSeedId('unit', oldBaseAbbreviation)
    if (ingredient.baseUnitId === previousSeedBaseId && previousSeedBaseId !== adminSeedId('unit', baseAbbreviation)) ingredient.baseUnitId = adminSeedId('unit', baseAbbreviation)
  }
  for (const record of data.recipes) {
    const seed = recipeSeed.find((item) => item.id === record.id)
    if (!seed || (record.dietaryTags?.length ?? 0) > 0) continue
    const unchanged = record.title === seed.name
      && record.author === 'CocinAPP'
      && record.description === seed.description
      && record.minutes === seed.minutes
      && record.portions === seed.portions
      && record.difficulty === seed.difficulty
      && record.calories === (seed.calories ?? 0)
      && (record.mealShifts?.[0] ?? record.mealShift) === (seed.mealShifts?.[0] ?? seed.mealShift ?? seed.category)
      && record.status === 'published' && record.active && !record.isDeleted
      && Boolean(record.createdAt) && record.updatedAt === record.createdAt
      && record.symbol === seed.symbol && record.color === seed.color
      && record.image === seed.image && record.imageAlt === seed.imageAlt
      && record.steps.length === seed.steps.length && record.steps.every((step, index) => step === seed.steps[index])
      && record.ingredients.length === seed.ingredients.length
      && record.ingredients.every((entry, index) => entry.ingredientId === adminSeedId('ingredient', seed.ingredients[index]!.name)
        && entry.unitId === adminSeedId('unit', seed.ingredients[index]!.unit)
        && entry.quantity === seed.ingredients[index]!.quantity)
      && record.preparationMinutes === undefined && record.cookingMinutes === undefined
    if (unchanged) record.dietaryTags = [...(seed.dietaryTags ?? [])]
  }
}
