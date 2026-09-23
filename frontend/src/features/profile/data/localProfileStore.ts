import type { ProfileDraft } from '../domain/profile'

const storageKey = 'cocinapp.profile.v1'

export function readLocalProfile(): ProfileDraft {
  try {
    const value: unknown = JSON.parse(window.localStorage.getItem(storageKey) ?? '{}')
    if (!value || typeof value !== 'object' || Array.isArray(value)) return {}
    const candidate = value as Record<string, unknown>
    return {
      name: typeof candidate.name === 'string' ? candidate.name : undefined,
      email: typeof candidate.email === 'string' ? candidate.email : undefined,
      birthDate: typeof candidate.birthDate === 'string' ? candidate.birthDate : undefined,
      weightKg: typeof candidate.weightKg === 'number' ? candidate.weightKg : undefined,
      heightCm: typeof candidate.heightCm === 'number' ? candidate.heightCm : undefined,
      metabolicSex: candidate.metabolicSex === 'female' || candidate.metabolicSex === 'male' ? candidate.metabolicSex : undefined,
      activityLevel: candidate.activityLevel === 'sedentary' || candidate.activityLevel === 'light' || candidate.activityLevel === 'moderate' || candidate.activityLevel === 'active' || candidate.activityLevel === 'very-active' ? candidate.activityLevel : undefined,
      goal: candidate.goal === 'lose' || candidate.goal === 'maintain' || candidate.goal === 'gain' ? candidate.goal : undefined,
      preferences: Array.isArray(candidate.preferences) ? candidate.preferences.filter((item): item is NonNullable<ProfileDraft['preferences']>[number] => item === 'gluten-free' || item === 'vegetarian' || item === 'vegan' || item === 'lactose-free' || item === 'nut-free') : undefined,
    }
  } catch {
    return {}
  }
}

export function saveLocalProfile(profile: ProfileDraft): void {
  window.localStorage.setItem(storageKey, JSON.stringify(profile))
}
