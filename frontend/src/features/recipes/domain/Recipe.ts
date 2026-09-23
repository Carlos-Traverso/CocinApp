export interface Recipe {
  id: string
  name: string
  description: string
  category: string
  minutes: number
  portions: number
  difficulty: 'Fácil' | 'Intermedia' | 'Avanzada'
  ingredients: { name: string; quantity: number; unit: 'g' | 'ml' | 'u' }[]
  steps: string[]
  symbol: string
  color: 'green' | 'gold' | 'pink' | 'blue'
}
