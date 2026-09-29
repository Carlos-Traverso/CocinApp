export interface AdminCategory {
  id: string
  name: string
  isDeleted: boolean
}

export interface AdminUnit {
  id: string
  name: string
  abbreviation: string
  dimension: 'masa' | 'volumen' | 'conteo'
  baseUnitId?: string // if it's derived
  equivalenceMultiplier?: number
  isDeleted: boolean
}

export interface AdminIngredient {
  id: string
  name: string
  categoryId: string
  baseUnitId: string
  isDeleted: boolean
}

export interface AdminRecipe {
  id: string
  title: string
  author: string
  description: string
  category: string
  minutes: number
  portions: number
  difficulty: 'Fácil' | 'Intermedia' | 'Avanzada'
  calories: number
  mealShift: string // Desayuno, Almuerzo, etc.
  dietaryTags: string[]
  featured?: boolean
  ingredients: { ingredientId: string; quantity: number; unitId: string; note?: string }[]
  steps: string[]
  stepMeta?: { minutes?: number; tip?: string }[]
  status: 'draft' | 'published'
  isDeleted: boolean
  symbol: string
  color: 'green' | 'gold' | 'pink' | 'blue'
  image?: string
  imageAlt?: string
}
