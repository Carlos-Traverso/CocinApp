import type { AdminRecipe } from '../domain/adminModels'
import { parseAdminRecipe } from './localAdminStore'
import { supabase } from '../../../shared/data/supabaseClient'

export type SupabaseRecipesResult =
  | { status: 'unavailable'; recipes: AdminRecipe[] }
  | { status: 'empty'; recipes: AdminRecipe[] }
  | { status: 'found'; recipes: AdminRecipe[]; version: number }

function readVersion(value: unknown): number {
  if (typeof value !== 'number' || !Number.isInteger(value) || value < 1) {
    throw new Error('La versión del catálogo de recetas no es válida.')
  }
  return value
}

function parseRecipeList(value: unknown): AdminRecipe[] {
  if (!Array.isArray(value)) throw new Error('El catálogo remoto de recetas tiene un formato inválido.')

  const recipes = value.map(parseAdminRecipe)
  if (recipes.some((recipe) => recipe === undefined)) {
    throw new Error('El catálogo remoto contiene una receta con datos inválidos.')
  }

  const validRecipes = recipes.filter((recipe): recipe is AdminRecipe => recipe !== undefined)
  if (new Set(validRecipes.map((recipe) => recipe.id)).size !== validRecipes.length) {
    throw new Error('El catálogo remoto contiene recetas con identificadores repetidos.')
  }
  return validRecipes
}

/** Reads the shared catalog for authenticated users. A missing row is an empty catalog. */
export async function readSupabaseRecipes(): Promise<SupabaseRecipesResult> {
  if (!supabase) return { status: 'unavailable', recipes: [] }

  const { data, error } = await supabase
    .from('shared_recipes')
    .select('recipes, version')
    .eq('catalog_key', 'main')
    .maybeSingle()

  // The recipe catalog was added after the core catalog. If a project has not
  // applied that migration yet, keep using local recipes while core data loads.
  if (error) {
    const missingTable = error.code === 'PGRST205' || error.code === '42P01'
      || (error.message.toLocaleLowerCase('en').includes('shared_recipes')
        && (error.message.toLocaleLowerCase('en').includes('schema cache')
          || error.message.toLocaleLowerCase('en').includes('does not exist')))
    if (missingTable) return { status: 'unavailable', recipes: [] }
    throw error
  }
  if (!data) return { status: 'empty', recipes: [] }

  const recipes = parseRecipeList(data.recipes)
  return { status: 'found', recipes, version: readVersion(data.version) }
}

/** Saves only if the row still has the version observed when it was read. */
export async function writeSupabaseRecipes(recipes: AdminRecipe[], expectedVersion: number | null): Promise<number> {
  if (!supabase) throw new Error('Supabase no está configurado.')
  const validatedRecipes = parseRecipeList(recipes)
  const { data, error } = await supabase.rpc('admin_save_shared_recipes', {
    p_expected_version: expectedVersion,
    p_recipes: validatedRecipes,
  })
  if (error) throw new Error(error.code === '40001'
    ? error.message
    : 'No se pudieron guardar las recetas en Supabase.', { cause: error })
  return readVersion(data)
}
