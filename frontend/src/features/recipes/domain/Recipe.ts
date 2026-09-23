export interface Recipe {
  id: string
  name: string
  description: string
  category: string
  minutes: number
  portions: number
  symbol: string
  color: 'green' | 'gold' | 'pink' | 'blue'
}
