export interface Recipe {
  id: string
  name: string
  description: string
  category: string
  minutes: number
  portions: number
  difficulty: 'Fácil' | 'Intermedia' | 'Avanzada'
  ingredients: { name: string; quantity: number; unit: string }[]
  steps: string[]
  symbol: string
  color: 'green' | 'gold' | 'pink' | 'blue'
  calories?: number
  mealShift?: string
  dietaryTags?: string[]
}
