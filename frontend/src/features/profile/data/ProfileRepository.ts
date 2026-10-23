import type { ProfileDraft } from '../domain/profile'
import { readLocalProfile, saveLocalProfile, parseProfileDraft } from './localProfileStore'
import { loadPersonalData, savePersonalData } from '../../../shared/data/personalDataRepository'
import { isSupabaseConfigured } from '../../../shared/data/supabaseClient'

export interface ProfileRepository {
  getProfile(): Promise<ProfileDraft>
  saveProfile(profile: ProfileDraft): Promise<void>
}

export const profileRepository: ProfileRepository = {
  async getProfile() {
    if (!isSupabaseConfigured) return readLocalProfile()
    const remote = await loadPersonalData('profile')
    if (remote !== null) {
      const profile = parseProfileDraft(remote)
      saveLocalProfile(profile)
      return profile
    }
    const local = readLocalProfile()
    if (Object.keys(local).length) await savePersonalData('profile', local)
    return local
  },
  async saveProfile(profile) {
    if (isSupabaseConfigured) await savePersonalData('profile', profile)
    saveLocalProfile(profile)
  },
}
