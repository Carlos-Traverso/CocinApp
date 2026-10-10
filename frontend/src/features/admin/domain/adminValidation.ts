import { normalizePantryName } from '../../pantry/domain/pantry'
import type { AdminCategory, AdminIngredient, AdminRecipe, AdminUnit } from './adminModels'
import { normalizeQuantity } from '../../../shared/domain/units'

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
    const previous = units.find((unit) => unit.id === exceptId)
    const base = units.find((unit) => unit.id === input.baseUnitId && !unit.isDeleted && (unit.active || previous?.baseUnitId === unit.id))
    if (!base || base.dimension !== input.dimension) throw new Error('Seleccioná una unidad base compatible.')
    if (!Number.isFinite(input.equivalenceMultiplier) || (input.equivalenceMultiplier ?? 0) <= 0) throw new Error('La equivalencia debe ser un número positivo.')
    if (base.id === exceptId) throw new Error('Una unidad no puede depender de sí misma.')
    let ancestor: AdminUnit | undefined = base
    const visited = new Set<string>()
    while (ancestor) {
      if (visited.has(ancestor.id) || ancestor.id === exceptId) throw new Error('La equivalencia crea una cadena de unidades inválida.')
      visited.add(ancestor.id)
      if (!ancestor.baseUnitId) break
      const parentId: string = ancestor.baseUnitId
      const parent: AdminUnit | undefined = units.find((unit) => unit.id === parentId && unit.active && !unit.isDeleted)
      if (!parent) throw new Error('La cadena de equivalencias contiene una unidad base inactiva o inexistente.')
      if (parent.dimension !== input.dimension) throw new Error('La cadena de equivalencias debe conservar la dimensión.')
      ancestor = parent
      if (ancestor.baseUnitId && (!Number.isFinite(ancestor.equivalenceMultiplier) || (ancestor.equivalenceMultiplier ?? 0) <= 0)) throw new Error('La cadena contiene una equivalencia inválida.')
    }
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
  const previous = ingredients.find((item) => item.id === exceptId)
  if (!name || !input.categoryId || !input.baseUnitId) throw new Error('Completá nombre, categoría y unidad base.')
  if (ingredients.some((item) => item.id !== exceptId && !item.isDeleted && normalizePantryName(item.name) === normalizePantryName(name))) throw new Error('El ingrediente ya existe.')
  if (!categories.some((item) => item.id === input.categoryId && !item.isDeleted && (item.active || previous?.categoryId === item.id))) throw new Error('Seleccioná una categoría activa.')
  const unit = units.find((item) => item.id === input.baseUnitId && !item.isDeleted && (item.active || previous?.baseUnitId === item.id))
  if (!unit || unit.baseUnitId) throw new Error('Seleccioná una unidad base activa.')
  return { ...input, name }
}

export function validateRecipe(input: Omit<AdminRecipe, 'id' | 'isDeleted'>, recipes: AdminRecipe[], ingredients: AdminIngredient[], units: AdminUnit[], exceptId?: string) {
  const title = input.title.trim()
  const image = input.image?.trim() || undefined
  const imageAlt = input.imageAlt?.trim() || undefined
  if (!title || !Number.isFinite(input.portions) || input.portions <= 0 || !Number.isInteger(input.portions)) throw new Error('Ingresá un título y una cantidad de porciones válida.')
  if (!Number.isFinite(input.minutes) || input.minutes <= 0 || !Number.isInteger(input.minutes)) throw new Error('El tiempo debe ser un número entero positivo.')
  if (!Number.isFinite(input.calories) || input.calories < 0) throw new Error('Las calorías de referencia deben ser cero o más.')
  if (!['Fácil', 'Intermedia', 'Avanzada'].includes(input.difficulty)) throw new Error('Elegí una dificultad válida.')
  const allowedMealShifts = ['Desayuno', 'Almuerzo', 'Merienda', 'Cena']
  const mealShifts = [...new Set(input.mealShifts ?? [input.mealShift])]
  if (!mealShifts.length || mealShifts.some((shift) => !allowedMealShifts.includes(shift))) throw new Error('Elegí al menos un turno de comida válido.')
  if (!Array.isArray(input.ingredients) || input.ingredients.length === 0) throw new Error('Agregá al menos un ingrediente.')
  if (!Array.isArray(input.steps) || input.steps.length === 0 || input.steps.some((step) => !step.trim())) throw new Error('Agregá instrucciones completas y ordenadas.')
  if (input.stepMeta !== undefined && (!Array.isArray(input.stepMeta) || input.stepMeta.length > input.steps.length)) throw new Error('Los datos de los pasos no son válidos.')
  const stepMeta = (input.stepMeta ?? []).map((meta) => {
    const minutes = meta?.durationMinutes ?? meta?.minutes
    const tip = meta?.tip?.trim() ?? ''
    const warning = meta?.warning?.trim() ?? ''
    const temperature = meta?.temperature?.trim() ?? ''
    const specialInstructions = meta?.specialInstructions?.trim() ?? ''
    const utensils = [...new Set((meta?.utensils ?? []).map((item) => item.trim()).filter(Boolean))]
    const ingredientIds = [...new Set(meta?.ingredientIds ?? [])]
    if (minutes !== undefined && (!Number.isInteger(minutes) || minutes < 1 || minutes > 240)) throw new Error('El tiempo de cada paso debe estar entre 1 y 240 minutos.')
    if (tip.length > 240) throw new Error('Cada consejo debe tener hasta 240 caracteres.')
    if (warning.length > 240 || temperature.length > 80 || specialInstructions.length > 400) throw new Error('Revisá la longitud de las indicaciones de cada paso.')
    if (utensils.some((item) => item.length > 80)) throw new Error('Cada utensilio debe tener hasta 80 caracteres.')
    if (ingredientIds.some((id) => !input.ingredients.some((entry) => entry.ingredientId === id))) throw new Error('Los ingredientes de cada paso deben pertenecer a la receta.')
    return {
      ...(minutes !== undefined ? { durationMinutes: minutes } : {}),
      ...(ingredientIds.length ? { ingredientIds } : {}),
      ...(utensils.length ? { utensils } : {}),
      ...(tip ? { tip } : {}),
      ...(warning ? { warning } : {}),
      ...(temperature ? { temperature } : {}),
      ...(specialInstructions ? { specialInstructions } : {}),
    }
  })
  if (!['draft', 'published'].includes(input.status)) throw new Error('Elegí si la receta queda como borrador o publicada.')
  if (typeof input.active !== 'boolean') throw new Error('Elegí un estado válido para la receta.')
  if (image && (!image.startsWith('/assets/recipes/') || !/\.(avif|webp|png|jpe?g)$/i.test(image))) throw new Error('La imagen debe usar un archivo local de /assets/recipes/.')
  if (image && !imageAlt) throw new Error('Ingresá el texto alternativo de la imagen.')
  if (input.featured !== undefined && typeof input.featured !== 'boolean') throw new Error('La marca destacada debe ser válida.')
  if (recipes.some((item) => item.id !== exceptId && !item.isDeleted && normalizePantryName(item.title) === normalizePantryName(title))) throw new Error('Ya existe una receta con ese título.')
  const previousRecipe = recipes.find((item) => item.id === exceptId)
  for (const entry of input.ingredients) {
    if (!Number.isFinite(entry.quantity) || entry.quantity <= 0) throw new Error('Cada ingrediente debe tener una cantidad positiva.')
    const retainedReference = previousRecipe?.ingredients.some((previous) => previous.ingredientId === entry.ingredientId && previous.unitId === entry.unitId) ?? false
    const ingredient = ingredients.find((item) => item.id === entry.ingredientId && !item.isDeleted)
    const unit = units.find((item) => item.id === entry.unitId && !item.isDeleted)
    const base = ingredient && units.find((item) => item.id === ingredient.baseUnitId && !item.isDeleted)
    const normalizedUnit = unit && normalizeQuantity(1, unit.id, units)
    const normalizedBase = base && normalizeQuantity(1, base.id, units)
    if (!ingredient || !unit || !base || (!retainedReference && (!ingredient.active || !unit.active || !base.active))
      || !normalizedUnit || !normalizedBase || normalizedUnit.dimension !== normalizedBase.dimension || normalizedUnit.baseUnit !== normalizedBase.baseUnit) {
      throw new Error('Cada receta debe usar ingredientes activos y unidades compatibles con su dimensión.')
    }
  }
  return { ...input, title, image, imageAlt, mealShifts, mealShift: mealShifts[0], category: mealShifts[0], steps: input.steps.map((step) => step.trim()), stepMeta, dietaryTags: input.dietaryTags.map((tag) => tag.trim()).filter(Boolean) }
}
