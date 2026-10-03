import type { AdminCategory, AdminUnit, AdminIngredient, AdminRecipe } from '../domain/adminModels'
import { defaultPantryCategories, defaultPantryUnits } from '../../pantry/domain/pantry'
import { normalizePantryName } from '../../pantry/domain/pantry'
import { adminCatalogVersion, createInitialAdminData } from './adminSeed'
import { adminSeedId } from './adminSeed'
import { inferIngredientCategory } from '../domain/ingredientCategory'

const ADMIN_KEY = 'cocinapp.admin.v1'

export interface AdminStorageData {
  categories: AdminCategory[]
  units: AdminUnit[]
  ingredients: AdminIngredient[]
  recipes: AdminRecipe[]
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return value !== null && typeof value === 'object' && !Array.isArray(value)
}

function isNamedRecord(value: unknown): value is Record<string, unknown> & { id: string; name: string } {
  return isRecord(value) && typeof value.id === 'string' && value.id.length > 0 && typeof value.name === 'string'
}

function readRecipe(value: unknown): AdminRecipe | undefined {
  if (!isRecord(value) || typeof value.id !== 'string' || !value.id || typeof value.title !== 'string' || !value.title) return undefined
  const shift = typeof value.mealShift === 'string' ? value.mealShift : typeof value.category === 'string' ? value.category : 'Almuerzo'
  const ingredients = Array.isArray(value.ingredients) ? value.ingredients.filter((entry) => isRecord(entry)
    && typeof entry.ingredientId === 'string' && typeof entry.unitId === 'string'
    && typeof entry.quantity === 'number' && Number.isFinite(entry.quantity) && entry.quantity > 0) : []
  const validStepIndices = Array.isArray(value.steps) ? value.steps.flatMap((step, index): number[] => typeof step === 'string' ? [index] : []) : []
  const steps = validStepIndices.map((index) => (value.steps as string[])[index])
  const stepMeta = validStepIndices.map((index) => {
    const entry = Array.isArray(value.stepMeta) ? value.stepMeta[index] : undefined
    return isRecord(entry) ? {
      minutes: typeof entry.minutes === 'number' && Number.isFinite(entry.minutes) && entry.minutes > 0 ? entry.minutes : undefined,
      durationMinutes: typeof entry.durationMinutes === 'number' && Number.isFinite(entry.durationMinutes) && entry.durationMinutes > 0 ? entry.durationMinutes : undefined,
      ingredientIds: Array.isArray(entry.ingredientIds) ? entry.ingredientIds.filter((id): id is string => typeof id === 'string') : undefined,
      utensils: Array.isArray(entry.utensils) ? entry.utensils.filter((item): item is string => typeof item === 'string' && item.trim().length > 0) : undefined,
      tip: typeof entry.tip === 'string' ? entry.tip : undefined,
      warning: typeof entry.warning === 'string' ? entry.warning : undefined,
      temperature: typeof entry.temperature === 'string' ? entry.temperature : undefined,
      specialInstructions: typeof entry.specialInstructions === 'string' ? entry.specialInstructions : undefined,
    } : {}
  })
  return {
    id: value.id, title: value.title, author: typeof value.author === 'string' ? value.author : 'CocinAPP',
    description: typeof value.description === 'string' ? value.description : '', category: shift, mealShift: shift,
    minutes: typeof value.minutes === 'number' && Number.isFinite(value.minutes) && value.minutes > 0 ? value.minutes : 30,
    portions: typeof value.portions === 'number' && Number.isFinite(value.portions) && value.portions > 0 ? value.portions : 1,
    difficulty: value.difficulty === 'Intermedia' || value.difficulty === 'Avanzada' ? value.difficulty : 'Fácil',
    calories: typeof value.calories === 'number' && Number.isFinite(value.calories) && value.calories >= 0 ? value.calories : 0,
    dietaryTags: Array.isArray(value.dietaryTags) ? value.dietaryTags.filter((tag): tag is string => typeof tag === 'string') : [],
    featured: value.featured === true, ingredients, steps, stepMeta,
    status: value.status === 'published' ? 'published' : 'draft', active: typeof value.active === 'boolean' ? value.active : value.isDeleted !== true, isDeleted: value.isDeleted === true,
    symbol: typeof value.symbol === 'string' && value.symbol ? value.symbol : value.title.slice(0, 1).toLocaleUpperCase('es'),
    color: value.color === 'gold' || value.color === 'pink' || value.color === 'blue' ? value.color : 'green',
    image: typeof value.image === 'string' && value.image.startsWith('/assets/recipes/') ? value.image : undefined,
    imageAlt: typeof value.imageAlt === 'string' && value.imageAlt.trim() ? value.imageAlt.trim() : undefined,
    preparationMinutes: typeof value.preparationMinutes === 'number' && value.preparationMinutes >= 0 ? value.preparationMinutes : undefined,
    cookingMinutes: typeof value.cookingMinutes === 'number' && value.cookingMinutes >= 0 ? value.cookingMinutes : undefined,
    createdAt: typeof value.createdAt === 'string' && !Number.isNaN(Date.parse(value.createdAt)) ? value.createdAt : undefined,
    updatedAt: typeof value.updatedAt === 'string' && !Number.isNaN(Date.parse(value.updatedAt)) ? value.updatedAt : undefined,
  }
}

function getAdminData(): AdminStorageData {
  try {
    const raw = localStorage.getItem(ADMIN_KEY)
    if (raw) {
      const data: unknown = JSON.parse(raw)
      if (!isRecord(data)) return { categories: [], units: [], ingredients: [], recipes: [] }
      const record = data as Record<string, unknown>
      const parsed: AdminStorageData = {
        categories: Array.isArray(record.categories) ? record.categories.filter(isNamedRecord).map((category) => ({ id: category.id, name: category.name, active: typeof category.active === 'boolean' ? category.active : category.isDeleted !== true, isDeleted: category.isDeleted === true })) : [],
        units: Array.isArray(record.units) ? record.units.filter(isNamedRecord).flatMap((unit): AdminUnit[] => {
          const dimension = unit.dimension === 'mass' ? 'masa' : unit.dimension === 'volume' ? 'volumen' : unit.dimension === 'count' || unit.dimension === 'unidad' ? 'conteo' : unit.dimension
          if (dimension !== 'masa' && dimension !== 'volumen' && dimension !== 'conteo' || typeof unit.abbreviation !== 'string') return []
          return [{ id: unit.id, name: unit.name, abbreviation: unit.abbreviation, dimension,
            baseUnitId: typeof unit.baseUnitId === 'string' ? unit.baseUnitId : undefined,
            equivalenceMultiplier: typeof unit.equivalenceMultiplier === 'number' && Number.isFinite(unit.equivalenceMultiplier) ? unit.equivalenceMultiplier : undefined,
            active: typeof unit.active === 'boolean' ? unit.active : unit.isDeleted !== true,
            isDeleted: unit.isDeleted === true }]
        }) : [],
        ingredients: Array.isArray(record.ingredients) ? record.ingredients.filter(isNamedRecord).flatMap((ingredient): AdminIngredient[] =>
          typeof ingredient.categoryId === 'string' && typeof ingredient.baseUnitId === 'string'
            ? [{ id: ingredient.id, name: ingredient.name, categoryId: ingredient.categoryId, baseUnitId: ingredient.baseUnitId, active: typeof ingredient.active === 'boolean' ? ingredient.active : ingredient.isDeleted !== true, isDeleted: ingredient.isDeleted === true }] : []) : [],
        recipes: Array.isArray(record.recipes) ? record.recipes.flatMap((value): AdminRecipe[] => {
          const recipe = readRecipe(value)
          return recipe ? [recipe] : []
        }) : [],
      }
      const version = typeof record.version === 'number' ? record.version : 1
      if (version < 3) {
        for (const ingredient of parsed.ingredients) {
          if (!ingredient.id.startsWith('seed-ingredient-')) continue
          const category = inferIngredientCategory(ingredient.name)
          if (category) ingredient.categoryId = adminSeedId('category', category)
        }
      }
      if (version < adminCatalogVersion) saveAdminData(parsed)
      return parsed
    }
  } catch {
    // Ignore corrupt data
  }
  const initial = createInitialAdminData()
  saveAdminData(initial)
  return initial
}

export function saveAdminData(data: AdminStorageData): void {
  localStorage.setItem(ADMIN_KEY, JSON.stringify({ version: adminCatalogVersion, ...data }))
  window.dispatchEvent(new Event('cocinapp:admin-updated'))
}

// Helpers for merging defaults with admin data

export function getActiveCategories(): string[] {
  const data = getAdminData()
  const custom = data.categories.filter((c) => c && c.active && !c.isDeleted && typeof c.name === 'string').map((c) => c.name)
  const activeDefaults = defaultPantryCategories.filter((name) => {
    const record = data.categories.find((category) => normalizePantryName(category.name) === normalizePantryName(name))
    return !record || record.active && !record.isDeleted
  })
  const combined = new Set([...activeDefaults, ...custom])
  return Array.from(combined).sort((a, b) => a.localeCompare(b, 'es'))
}

export function getActiveUnits(): string[] {
  const data = getAdminData()
  const custom = data.units.filter((u) => u && u.active && !u.isDeleted && typeof u.abbreviation === 'string').map((u) => u.abbreviation)
  const activeDefaults = defaultPantryUnits.filter((abbreviation) => {
    const record = data.units.find((unit) => unit.abbreviation.toLocaleLowerCase('es') === abbreviation.toLocaleLowerCase('es'))
    return !record || record.active && !record.isDeleted
  })
  const combined = new Set([...activeDefaults, ...custom])
  return Array.from(combined)
}

export function getKnownCategories(): string[] {
  return [...new Set([...defaultPantryCategories, ...getAdminData().categories.filter((category) => category && typeof category.name === 'string').map((category) => category.name)])]
}

export function getKnownUnits(): string[] {
  return [...new Set([...defaultPantryUnits, ...getAdminData().units.filter((unit) => unit && typeof unit.abbreviation === 'string').map((unit) => unit.abbreviation)])]
}

export function findActiveIngredient(name: string) {
  const normalized = normalizePantryName(name)
  if (!normalized) return undefined
  return getAdminData().ingredients.find((ingredient) => ingredient.active && !ingredient.isDeleted && normalizePantryName(ingredient.name) === normalized)
}

export function resolveIngredientCategory(name: string): string {
  const data = getAdminData()
  const ingredient = data.ingredients.find((item) => normalizePantryName(item.name) === normalizePantryName(name))
  const category = data.categories.find((item) => item.id === ingredient?.categoryId)
  if (category && category.name !== 'Otros') return category.name
  return inferIngredientCategory(name) ?? category?.name ?? 'Otros'
}

export function getUnitsForIngredient(name: string): string[] {
  const data = getAdminData()
  const ingredient = findActiveIngredient(name)
  const base = data.units.find((unit) => unit.id === ingredient?.baseUnitId && unit.active && !unit.isDeleted)
  if (!base) return getActiveUnits()
  const defaultsByDimension: Record<AdminUnit['dimension'], string[]> = {
    masa: ['g', 'kg'], volumen: ['ml', 'l'], conteo: ['u'],
  }
  return [...new Set([...defaultsByDimension[base.dimension], ...data.units.filter((unit) => unit.active && !unit.isDeleted && unit.dimension === base.dimension).map((unit) => unit.abbreviation)])]
}

export { getAdminData }
