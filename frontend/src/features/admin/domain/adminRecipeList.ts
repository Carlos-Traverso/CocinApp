import type { Recipe } from '../../recipes/domain/Recipe'
import { normalizePantryName } from '../../pantry/domain/pantry'
import type { AdminStorageData } from '../data/localAdminStore'
import type { AdminRecipe } from './adminModels'

export type ManagedAdminRecipe = {
  id: string
  title: string
  category: string
  minutes: number
  difficulty: Recipe['difficulty']
  featured: boolean
  active: boolean
  status: 'published' | 'draft' | 'inactive'
  source: 'initial' | 'admin'
  modifiedAt?: string
  recipe: Recipe
  record?: AdminRecipe
}

export type AdminRecipeFilters = {
  search: string
  category: string
  status: 'all' | 'active' | 'draft' | 'inactive'
  difficulty: 'all' | Recipe['difficulty']
  maxMinutes: number
  featured: 'all' | 'featured'
  sort: 'title-asc' | 'title-desc' | 'newest' | 'oldest'
}

export function getManagedRecipes(data: AdminStorageData, knownRecipes: Recipe[]): ManagedAdminRecipe[] {
  return knownRecipes.map((recipe) => {
    const record = data.recipes.find((entry) => entry.id === recipe.id)
    const active = !record || (record.active && !record.isDeleted && record.status === 'published')
    return {
      id: recipe.id,
      title: recipe.name,
      category: recipe.mealShift ?? recipe.category,
      minutes: recipe.minutes,
      difficulty: recipe.difficulty,
      featured: recipe.featured ?? false,
      active,
      status: record && (!record.active || record.isDeleted) ? 'inactive' : record?.status ?? 'published',
      source: record ? 'admin' : 'initial',
      modifiedAt: record?.updatedAt ?? record?.createdAt,
      recipe,
      record,
    }
  })
}

export function filterAdminRecipes(recipes: ManagedAdminRecipe[], filters: AdminRecipeFilters): ManagedAdminRecipe[] {
  const search = normalizePantryName(filters.search)
  return recipes.filter((recipe) => {
    if (search && !normalizePantryName(`${recipe.title} ${recipe.category}`).includes(search)) return false
    if (filters.category && recipe.category !== filters.category) return false
    if (filters.status === 'active' && !recipe.active) return false
    if (filters.status === 'draft' && recipe.status !== 'draft') return false
    if (filters.status === 'inactive' && recipe.status !== 'inactive') return false
    if (filters.difficulty !== 'all' && recipe.difficulty !== filters.difficulty) return false
    if (filters.maxMinutes > 0 && recipe.minutes > filters.maxMinutes) return false
    if (filters.featured === 'featured' && !recipe.featured) return false
    return true
  }).sort((first, second) => {
    if (filters.sort === 'title-desc') return second.title.localeCompare(first.title, 'es')
    if (filters.sort === 'newest') return (second.modifiedAt ?? '').localeCompare(first.modifiedAt ?? '') || first.title.localeCompare(second.title, 'es')
    if (filters.sort === 'oldest') return (first.modifiedAt ?? '').localeCompare(second.modifiedAt ?? '') || first.title.localeCompare(second.title, 'es')
    return first.title.localeCompare(second.title, 'es')
  })
}
