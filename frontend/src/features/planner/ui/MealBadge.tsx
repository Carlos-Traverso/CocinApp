import { Apple, Coffee, MoonStar, SunMedium } from 'lucide-react'
import type { Meal } from '../domain/planner'
import { mealBadgeDetails } from './plannerPresentation'

const icons = { coffee: Coffee, sun: SunMedium, apple: Apple, moon: MoonStar }

export function MealBadge({ meal }: { meal: Meal }) {
  const detail = mealBadgeDetails[meal]
  const Icon = icons[detail.icon]
  return <span className={`meal-badge ${detail.tone}`}><Icon aria-hidden="true" size={14} /><span>{detail.label}</span></span>
}
