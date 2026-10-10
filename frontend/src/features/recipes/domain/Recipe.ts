export interface RecipeIngredient { name: string; quantity: number; unit: string; category?: string }

export interface RecipeStepMeta {
  /** @deprecated Use durationMinutes for new recipes. */
  minutes?: number
  durationMinutes?: number
  stepIngredients?: RecipeIngredient[]
  utensils?: string[]
  tip?: string
  warning?: string
  temperature?: string
  specialInstructions?: string
}

export interface Recipe {
  id: string
  name: string
  description: string
  category: string
  minutes: number
  portions: number
  difficulty: 'Fácil' | 'Intermedia' | 'Avanzada'
  ingredients: RecipeIngredient[]
  steps: string[]
  stepMeta?: RecipeStepMeta[]
  symbol: string
  color: 'green' | 'gold' | 'pink' | 'blue'
  image?: string
  imageAlt?: string
  calories?: number
  mealShift?: string
  mealShifts?: string[]
  dietaryTags?: string[]
  /** Advisory: shared kitchens can still introduce allergens. */
  crossContaminationNote?: string
  featured?: boolean
  /** @deprecated Recommendations use only local user data. */
  popularity?: number
}
