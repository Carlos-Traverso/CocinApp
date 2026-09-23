export type Meal = 'Almuerzo' | 'Cena'
export interface PlannedMeal { date: string; meal: Meal; recipeId: string }

function localDate(date: Date): string {
  return `${date.getFullYear()}-${String(date.getMonth() + 1).padStart(2, '0')}-${String(date.getDate()).padStart(2, '0')}`
}

export function weekDates(today = new Date()): string[] {
  const monday = new Date(today.getFullYear(), today.getMonth(), today.getDate())
  monday.setDate(monday.getDate() - (monday.getDay() + 6) % 7)
  return Array.from({ length: 7 }, (_, index) => {
    const day = new Date(monday)
    day.setDate(day.getDate() + index)
    return localDate(day)
  })
}

export function setPlannedMeal(plan: PlannedMeal[], date: string, meal: Meal, recipeId: string): PlannedMeal[] {
  const remaining = plan.filter((item) => item.date !== date || item.meal !== meal)
  return recipeId ? [...remaining, { date, meal, recipeId }] : remaining
}
