export type ActivityLevel = 'sedentary' | 'light' | 'moderate' | 'active' | 'very-active'
export type Goal = 'lose' | 'maintain' | 'gain' | 'gain-muscle'
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

// Product guidance, not an individual prescription. A modest +200–300 kcal/day
// for muscle gain follows the range discussed for trained adults in
// https://pmc.ncbi.nlm.nih.gov/articles/PMC6680710/ . The optimal surplus is
// uncertain and depends on the person and their resistance training.
const goalAdjustments = {
  lose: { minimum: -600, maximum: -400 },
  maintain: { minimum: -100, maximum: 100 },
  gain: { minimum: 250, maximum: 400 },
  'gain-muscle': { minimum: 200, maximum: 300 },
} satisfies Record<Goal, { minimum: number; maximum: number }>

export function calculateAge(birthDate: string, today = new Date()): number | undefined {
  if (!/^\d{4}-\d{2}-\d{2}$/.test(birthDate)) return undefined
  const birth = new Date(`${birthDate}T12:00:00`)
  const [year, month, day] = birthDate.split('-').map(Number)
  if (Number.isNaN(birth.getTime()) || birth.getFullYear() !== year || birth.getMonth() + 1 !== month || birth.getDate() !== day || birth > new Date(today.getFullYear(), today.getMonth(), today.getDate(), 12)) return undefined
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
  const adjustment = goalAdjustments[input.goal]
  const goalRange = { minimum: dailyCalories + adjustment.minimum, maximum: dailyCalories + adjustment.maximum }

  return { basalCalories, dailyCalories, goalRange }
}

export function estimateForProfile(profile: ProfileDraft, today = new Date()): EnergyEstimate | undefined {
  const age = profile.birthDate ? calculateAge(profile.birthDate, today) : undefined
  if (!profileIsComplete(profile, today) || age === undefined || age < 18 || age > 100) return undefined
  return calculateEnergyEstimate({
    weightKg: profile.weightKg!, heightCm: profile.heightCm!, age,
    metabolicSex: profile.metabolicSex!, activityLevel: profile.activityLevel!, goal: profile.goal!,
  })
}

export function recipeGoalPercentageRange(caloriesPerPortion: number, estimate: EnergyEstimate): { minimum: number; maximum: number } | undefined {
  if (!Number.isFinite(caloriesPerPortion) || caloriesPerPortion < 0 || estimate.goalRange.minimum <= 0) return undefined
  return {
    minimum: Math.round(caloriesPerPortion / estimate.goalRange.maximum * 100),
    maximum: Math.round(caloriesPerPortion / estimate.goalRange.minimum * 100),
  }
}

export function profileIsComplete(profile: ProfileDraft, today = new Date()): boolean {
  return Boolean(
    profile.name
    && profile.birthDate
    && calculateAge(profile.birthDate, today) !== undefined
    && typeof profile.weightKg === 'number'
    && Number.isFinite(profile.weightKg)
    && profile.weightKg >= 30
    && profile.weightKg <= 300
    && typeof profile.heightCm === 'number'
    && Number.isFinite(profile.heightCm)
    && profile.heightCm >= 100
    && profile.heightCm <= 250
    && (profile.metabolicSex === 'female' || profile.metabolicSex === 'male')
    && typeof profile.activityLevel === 'string'
    && profile.activityLevel in activityFactors
    && typeof profile.goal === 'string'
    && profile.goal in goalAdjustments,
  )
}
