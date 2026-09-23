import type { Recipe } from '../features/recipes/domain/Recipe'

export const sampleRecipes = [
  {
    id: 'quinoa-bowl',
    name: 'Bowl de quinoa y verduras',
    description: 'Verduras asadas, quinoa y aderezo de limón.',
    category: 'Almuerzo',
    minutes: 30,
    portions: 2,
    symbol: 'Q',
    color: 'green',
  },
  {
    id: 'pumpkin-pasta',
    name: 'Pasta cremosa de calabaza',
    description: 'Una salsa suave con salvia y queso rallado.',
    category: 'Cena',
    minutes: 25,
    portions: 3,
    symbol: 'P',
    color: 'gold',
  },
  {
    id: 'chickpea-salad',
    name: 'Ensalada tibia de garbanzos',
    description: 'Garbanzos crocantes, hojas frescas y yogur.',
    category: 'Almuerzo',
    minutes: 20,
    portions: 2,
    symbol: 'G',
    color: 'pink',
  },
] satisfies Recipe[]
