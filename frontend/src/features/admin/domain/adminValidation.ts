import { normalizePantryName } from '../../pantry/domain/pantry'
import type { AdminCategory, AdminIngredient, AdminRecipe, AdminUnit } from './adminModels'

export function validateCategoryName(name: string, categories: AdminCategory[], exceptId?: string) {
  const clean = name.trim()
  if (!clean) throw new Error('Ingresá un nombre para la categoría.')
  if (categories.some((item) => item.id !== exceptId && !item.isDeleted && normalizePantryName(item.name) === normalizePantryName(clean))) throw new Error('La categoría ya existe.')
  return clean
}

export function validateUnit(input: Omit<AdminUnit, 'id' | 'isDeleted'>, units: AdminUnit[], exceptId?: string) {
  const name = input.name.trim()
  const abbreviation = input.abbreviation.trim()
  if (!name || !abbreviation) throw new Error('Completá el nombre y la abreviatura de la unidad.')
  if (!['masa', 'volumen', 'conteo'].includes(input.dimension)) throw new Error('Elegí una dimensión válida.')
  if (units.some((unit) => unit.id !== exceptId && !unit.isDeleted && (normalizePantryName(unit.name) === normalizePantryName(name) || unit.abbreviation.toLocaleLowerCase('es') === abbreviation.toLocaleLowerCase('es')))) throw new Error('El nombre o la abreviatura de la unidad ya existe.')
  if (input.baseUnitId) {
    const base = units.find((unit) => unit.id === input.baseUnitId && !unit.isDeleted)
    if (!base || base.dimension !== input.dimension || base.baseUnitId) throw new Error('Seleccioná una unidad base compatible.')
    if (!Number.isFinite(input.equivalenceMultiplier) || (input.equivalenceMultiplier ?? 0) <= 0) throw new Error('La equivalencia debe ser un número positivo.')
  } else {
    const baseAbbreviation = { masa: 'g', volumen: 'ml', conteo: 'u' }[input.dimension]
    if (abbreviation.toLocaleLowerCase('es') !== baseAbbreviation) throw new Error(`La unidad base de ${input.dimension} debe ser ${baseAbbreviation}.`)
    if (units.some((unit) => unit.id !== exceptId && !unit.isDeleted && unit.dimension === input.dimension && !unit.baseUnitId)) throw new Error('Esta dimensión ya tiene una unidad base.')
    if (input.equivalenceMultiplier !== undefined) throw new Error('Una unidad base no lleva equivalencia.')
  }
  return { ...input, name, abbreviation }
}

export function validateIngredient(input: Omit<AdminIngredient, 'id' | 'isDeleted'>, ingredients: AdminIngredient[], categories: AdminCategory[], units: AdminUnit[], exceptId?: string) {
  const name = input.name.trim()
  if (!name || !input.categoryId || !input.baseUnitId) throw new Error('Completá nombre, categoría y unidad base.')
  if (ingredients.some((item) => item.id !== exceptId && !item.isDeleted && normalizePantryName(item.name) === normalizePantryName(name))) throw new Error('El ingrediente ya existe.')
  if (!categories.some((item) => item.id === input.categoryId && !item.isDeleted)) throw new Error('Seleccioná una categoría activa.')
  const unit = units.find((item) => item.id === input.baseUnitId && !item.isDeleted)
  if (!unit || unit.baseUnitId) throw new Error('Seleccioná una unidad base activa.')
  return { ...input, name }
}

export function validateRecipe(input: Omit<AdminRecipe, 'id' | 'isDeleted'>, recipes: AdminRecipe[], ingredients: AdminIngredient[], units: AdminUnit[], exceptId?: string) {
  const title = input.title.trim()
  if (!title || !Number.isFinite(input.portions) || input.portions <= 0 || !Number.isInteger(input.portions)) throw new Error('Ingresá un título y una cantidad de porciones válida.')
  if (!Number.isFinite(input.minutes) || input.minutes <= 0 || !Number.isInteger(input.minutes)) throw new Error('El tiempo debe ser un número entero positivo.')
  if (!Number.isFinite(input.calories) || input.calories < 0) throw new Error('Las calorías de referencia deben ser cero o más.')
  if (!['Fácil', 'Intermedia', 'Avanzada'].includes(input.difficulty)) throw new Error('Elegí una dificultad válida.')
  if (!['Desayuno', 'Almuerzo', 'Merienda', 'Cena'].includes(input.mealShift)) throw new Error('Elegí un turno de comida válido.')
  if (!Array.isArray(input.ingredients) || input.ingredients.length === 0) throw new Error('Agregá al menos un ingrediente.')
  if (!Array.isArray(input.steps) || input.steps.length === 0 || input.steps.some((step) => !step.trim())) throw new Error('Agregá instrucciones completas y ordenadas.')
  if (input.stepMeta !== undefined && (!Array.isArray(input.stepMeta) || input.stepMeta.length > input.steps.length)) throw new Error('Los datos de los pasos no son válidos.')
  const stepMeta = (input.stepMeta ?? []).map((meta) => {
    const minutes = meta?.minutes
    const tip = meta?.tip?.trim() ?? ''
    if (minutes !== undefined && (!Number.isInteger(minutes) || minutes < 1 || minutes > 240)) throw new Error('El tiempo de cada paso debe estar entre 1 y 240 minutos.')
    if (tip.length > 240) throw new Error('Cada consejo debe tener hasta 240 caracteres.')
    return { ...(minutes !== undefined ? { minutes } : {}), ...(tip ? { tip } : {}) }
  })
  if (!['draft', 'published'].includes(input.status)) throw new Error('Elegí si la receta queda como borrador o publicada.')
  if (recipes.some((item) => item.id !== exceptId && !item.isDeleted && normalizePantryName(item.title) === normalizePantryName(title))) throw new Error('Ya existe una receta con ese título.')
  for (const entry of input.ingredients) {
    if (!Number.isFinite(entry.quantity) || entry.quantity <= 0) throw new Error('Cada ingrediente debe tener una cantidad positiva.')
    const ingredient = ingredients.find((item) => item.id === entry.ingredientId && !item.isDeleted)
    const unit = units.find((item) => item.id === entry.unitId && !item.isDeleted)
    const base = ingredient && units.find((item) => item.id === ingredient.baseUnitId && !item.isDeleted)
    if (!ingredient || !unit || !base || unit.dimension !== base.dimension) throw new Error('Cada receta debe usar ingredientes activos y unidades compatibles con su dimensión.')
  }
  return { ...input, title, steps: input.steps.map((step) => step.trim()), stepMeta, dietaryTags: input.dietaryTags.map((tag) => tag.trim()).filter(Boolean) }
}
