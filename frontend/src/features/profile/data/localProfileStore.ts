import type { ProfileDraft } from '../domain/profile'
import { personalStorage } from '../../auth/data/personalStorage'

const storageKey = 'cocinapp.profile.v1'
interface StorageLike { getItem(key: string): string | null; setItem(key: string, value: string): void }

export function readLocalProfile(storage?: StorageLike): ProfileDraft {
  return parseProfileDraft(readStoredProfile(storage ?? personalStorage))
}

function readStoredProfile(storage: StorageLike): Record<string, unknown> | null {
  try {
    const value: unknown = JSON.parse(storage.getItem(storageKey) ?? '{}')
    return value && typeof value === 'object' && !Array.isArray(value) ? value as Record<string, unknown> : null
  } catch {
    return null
  }
}

export function isLocalOnboardingComplete(storage: StorageLike = personalStorage): boolean {
  return readStoredProfile(storage)?.onboardingCompleted === true
}

export function saveLocalOnboarding(profile: ProfileDraft, storage: StorageLike = personalStorage): void {
  storage.setItem(storageKey, JSON.stringify({ ...profile, onboardingCompleted: true }))
}

export function parseProfileDraft(value: unknown): ProfileDraft {
  if (!value || typeof value !== 'object' || Array.isArray(value)) return {}
  const candidate = value as Record<string, unknown>
  return {
    name: typeof candidate.name === 'string' ? candidate.name : undefined,
    email: typeof candidate.email === 'string' ? candidate.email : undefined,
    birthDate: typeof candidate.birthDate === 'string' ? candidate.birthDate : undefined,
    weightKg: typeof candidate.weightKg === 'number' && Number.isFinite(candidate.weightKg) ? candidate.weightKg : undefined,
    heightCm: typeof candidate.heightCm === 'number' && Number.isFinite(candidate.heightCm) ? candidate.heightCm : undefined,
    metabolicSex: candidate.metabolicSex === 'female' || candidate.metabolicSex === 'male' ? candidate.metabolicSex : undefined,
    activityLevel: candidate.activityLevel === 'sedentary' || candidate.activityLevel === 'light' || candidate.activityLevel === 'moderate' || candidate.activityLevel === 'active' || candidate.activityLevel === 'very-active' ? candidate.activityLevel : undefined,
    goal: candidate.goal === 'lose' || candidate.goal === 'maintain' || candidate.goal === 'gain' || candidate.goal === 'gain-muscle' ? candidate.goal : undefined,
    preferences: Array.isArray(candidate.preferences) ? candidate.preferences.filter((item): item is NonNullable<ProfileDraft['preferences']>[number] => item === 'gluten-free' || item === 'vegetarian' || item === 'vegan' || item === 'lactose-free' || item === 'nut-free') : undefined,
  }
}

export function saveLocalProfile(profile: ProfileDraft, storage: StorageLike = personalStorage): void {
  if (isLocalOnboardingComplete(storage)) {
    saveLocalOnboarding(profile, storage)
    return
  }
  storage.setItem(storageKey, JSON.stringify(profile))
}
