import type { Meal } from '../domain/planner'

export const mealBadgeDetails = {
  Desayuno: { label: 'Desayuno', icon: 'coffee', tone: 'morning' },
  Almuerzo: { label: 'Almuerzo', icon: 'sun', tone: 'midday' },
  Merienda: { label: 'Merienda', icon: 'apple', tone: 'afternoon' },
  Cena: { label: 'Cena', icon: 'moon', tone: 'evening' },
} as const satisfies Record<Meal, { label: string; icon: 'coffee' | 'sun' | 'apple' | 'moon'; tone: string }>

export function plannerSlotPresentation(hasRecipe: boolean) {
  return hasRecipe
    ? { state: 'Receta asignada', primaryAction: 'Cambiar receta', actions: ['Ver receta', 'Quitar receta'] }
    : { state: 'Sin receta planificada', primaryAction: 'Agregar receta', actions: [] }
}
