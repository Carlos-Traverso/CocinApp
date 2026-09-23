export type ActivityLevel = 'sedentary' | 'light' | 'moderate' | 'active' | 'very-active'
export type Goal = 'lose' | 'maintain' | 'gain'
export type MetabolicSex = 'female' | 'male'
export type DietaryPreference = 'gluten-free' | 'vegetarian' | 'vegan' | 'lactose-free' | 'nut-free'

export interface ProfileDraft {
  name?: string
  email?: string
  birthDate?: string
  weightKg?: number
  heightCm?: number
  metabolicSex?: MetabolicSex
  activityLevel?: ActivityLevel
  goal?: Goal
  preferences?: DietaryPreference[]
}

export interface EnergyEstimate {
  basalCalories: number
  dailyCalories: number
  goalRange: { minimum: number; maximum: number }
}

const activityFactors = {
  sedentary: 1.2,
  light: 1.375,
  moderate: 1.55,
  active: 1.725,
  'very-active': 1.9,
} satisfies Record<ActivityLevel, number>

export function calculateAge(birthDate: string, today = new Date()): number {
  const birth = new Date(`${birthDate}T12:00:00`)
  let age = today.getFullYear() - birth.getFullYear()
  const hasHadBirthday = today.getMonth() > birth.getMonth()
    || (today.getMonth() === birth.getMonth() && today.getDate() >= birth.getDate())

  if (!hasHadBirthday) age -= 1
  return age
}

export function calculateEnergyEstimate(input: {
  weightKg: number
  heightCm: number
  age: number
  metabolicSex: MetabolicSex
  activityLevel: ActivityLevel
  goal: Goal
}): EnergyEstimate {
  const sexAdjustment = input.metabolicSex === 'male' ? 5 : -161
  const basalCaloriesExact = 10 * input.weightKg + 6.25 * input.heightCm - 5 * input.age + sexAdjustment
  const basalCalories = Math.round(basalCaloriesExact)
  const dailyCalories = Math.round(basalCaloriesExact * activityFactors[input.activityLevel])
  const goalRange = input.goal === 'lose'
    ? { minimum: dailyCalories - 600, maximum: dailyCalories - 400 }
    : input.goal === 'gain'
      ? { minimum: dailyCalories + 250, maximum: dailyCalories + 400 }
      : { minimum: dailyCalories - 100, maximum: dailyCalories + 100 }

  return { basalCalories, dailyCalories, goalRange }
}

export function profileIsComplete(profile: ProfileDraft): boolean {
  return Boolean(
    profile.name
    && profile.birthDate
    && typeof profile.weightKg === 'number'
    && profile.weightKg >= 30
    && profile.weightKg <= 300
    && typeof profile.heightCm === 'number'
    && profile.heightCm >= 100
    && profile.heightCm <= 250
    && profile.metabolicSex
    && profile.activityLevel
    && profile.goal,
  )
}
