import type { ProfileDraft } from '../domain/profile'
import { readLocalProfile, saveLocalProfile, parseProfileDraft } from './localProfileStore'
import { loadPersonalData, savePersonalData } from '../../../shared/data/personalDataRepository'
import { isSupabaseConfigured } from '../../../shared/data/supabaseClient'
import { assertPersonalDataSessionCurrent, capturePersonalDataSession, type PersonalDataSession } from '../../../shared/data/personalDataSession'

export interface ProfileRepository {
  getProfile(): Promise<ProfileDraft>
  saveProfile(profile: ProfileDraft): Promise<void>
}

interface ProfileRepositoryDependencies {
  isSupabaseConfigured: boolean
  loadPersonalData(key: 'profile', session: PersonalDataSession): Promise<unknown | null>
  savePersonalData(key: 'profile', value: unknown, session: PersonalDataSession): Promise<void>
}

export function createProfileRepository(dependencies: ProfileRepositoryDependencies = {
  isSupabaseConfigured,
  loadPersonalData,
  savePersonalData,
}): ProfileRepository {
  return {
    async getProfile() {
      const session = capturePersonalDataSession()
      if (!dependencies.isSupabaseConfigured) return readLocalProfile()
      const remote = await dependencies.loadPersonalData('profile', session)
      assertPersonalDataSessionCurrent(session)
      if (remote !== null) {
        const profile = parseProfileDraft(remote)
        saveLocalProfile(profile)
        return profile
      }
      const local = readLocalProfile()
      if (Object.keys(local).length) await dependencies.savePersonalData('profile', local, session)
      assertPersonalDataSessionCurrent(session)
      return local
    },
    async saveProfile(profile) {
      const session = capturePersonalDataSession()
      if (dependencies.isSupabaseConfigured) await dependencies.savePersonalData('profile', profile, session)
      assertPersonalDataSessionCurrent(session)
      saveLocalProfile(profile)
    },
  }
}

export const profileRepository = createProfileRepository()
