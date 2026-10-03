import { normalizePantryName, type PantryCategory } from '../../pantry/domain/pantry'

const categoryTerms = {
  'Frutas y verduras': ['banana', 'calabaza', 'espinaca', 'hojas verdes', 'limon', 'manzana', 'palta', 'papa', 'pera', 'tomate', 'zanahoria'],
  'Carnes y pescados': ['atun', 'filet de pescado', 'pechuga de pollo', 'pescado'],
  'Lácteos': ['leche', 'queso', 'yogur'],
  'Granos y legumbres': ['arroz', 'avena', 'garbanzo', 'lenteja', 'pasta', 'quinoa'],
  'Huevos': ['huevo'],
  'Almacén': ['aceite', 'harina', 'masa para tarta', 'pan integral', 'tortilla'],
} as const satisfies Record<string, readonly string[]>

export function inferIngredientCategory(name: string): PantryCategory | undefined {
  const normalized = normalizePantryName(name)
  for (const [category, terms] of Object.entries(categoryTerms)) {
    if (terms.some((term) => normalized.includes(term))) return category
  }
  return undefined
}
