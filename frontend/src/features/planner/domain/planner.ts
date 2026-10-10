export const meals = ['Desayuno', 'Almuerzo', 'Merienda', 'Cena'] as const
export type Meal = typeof meals[number]
export interface PlannedMeal { date: string; meal: Meal; recipeId: string; portions: number }

export function localDateKey(date: Date): string {
  return `${date.getFullYear()}-${String(date.getMonth() + 1).padStart(2, '0')}-${String(date.getDate()).padStart(2, '0')}`
}

export function getPlannedMealsForDate(plan: PlannedMeal[], date = new Date()): PlannedMeal[] {
  const dateKey = localDateKey(date)
  return plan
    .filter((entry) => entry.date === dateKey)
    .sort((left, right) => meals.indexOf(left.meal) - meals.indexOf(right.meal))
}

export function weekDates(today = new Date()): string[] {
  const monday = new Date(today.getFullYear(), today.getMonth(), today.getDate())
  monday.setDate(monday.getDate() - (monday.getDay() + 6) % 7)
  return Array.from({ length: 7 }, (_, index) => {
    const day = new Date(monday)
    day.setDate(day.getDate() + index)
    return localDateKey(day)
  })
}

export function setPlannedMeal(plan: PlannedMeal[], date: string, meal: Meal, recipeId: string, portions?: number): PlannedMeal[] {
  const remaining = plan.filter((item) => item.date !== date || item.meal !== meal)
  if (!recipeId) return remaining
  const previous = plan.find((item) => item.date === date && item.meal === meal && item.recipeId === recipeId)
  return [...remaining, { date, meal, recipeId, portions: Math.max(1, Math.min(20, Math.round(portions ?? previous?.portions ?? 2))) }]
}

export function movePlannedMeal(plan: PlannedMeal[], from: Pick<PlannedMeal, 'date' | 'meal'>, to: Pick<PlannedMeal, 'date' | 'meal'>): PlannedMeal[] {
  const moving = plan.find((item) => item.date === from.date && item.meal === from.meal)
  if (!moving) return plan
  const displaced = plan.find((item) => item.date === to.date && item.meal === to.meal)
  const cleared = plan.filter((item) => !(item.date === from.date && item.meal === from.meal) && !(item.date === to.date && item.meal === to.meal))
  return [...cleared, { ...moving, date: to.date, meal: to.meal }, ...(displaced ? [{ ...displaced, date: from.date, meal: from.meal }] : [])]
}
