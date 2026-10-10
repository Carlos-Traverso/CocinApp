import type { ProfileDraft } from '../domain/profile'
import { readLocalProfile, saveLocalProfile } from './localProfileStore'

export interface ProfileRepository {
  getProfile(): Promise<ProfileDraft>
  saveProfile(profile: ProfileDraft): Promise<void>
}

export const profileRepository: ProfileRepository = {
  async getProfile() { await Promise.resolve(); return readLocalProfile() },
  async saveProfile(profile) { await Promise.resolve(); saveLocalProfile(profile) },
}
