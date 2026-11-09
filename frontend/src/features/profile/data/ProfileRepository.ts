import type { ProfileDraft, DietaryPreference } from '../domain/profile'
import { readLocalProfile, saveLocalProfile, parseProfileDraft } from './localProfileStore'
import { loadPersonalData, savePersonalData } from '../../../shared/data/personalDataRepository'
import { isRelationalProfilesEnabled, isSupabaseConfigured, supabase } from '../../../shared/data/supabaseClient'
import { assertPersonalDataOwner, assertPersonalDataSessionCurrent, capturePersonalDataSession, type PersonalDataSession } from '../../../shared/data/personalDataSession'
import { getSession, updateSupabaseSessionName } from '../../auth/data/localAuthStore'
import { nutritionRepository } from './NutritionRepository'

export interface ProfileRepository {
  getProfile(): Promise<ProfileDraft>
  saveProfile(profile: ProfileDraft): Promise<void>
}

interface ProfileRepositoryDependencies {
  isSupabaseConfigured: boolean
  relationalProfiles?: boolean
  loadPersonalData(key: 'profile', session: PersonalDataSession): Promise<unknown | null>
  savePersonalData(key: 'profile', value: unknown, session: PersonalDataSession): Promise<void>
  getMyProfile?(session: PersonalDataSession): Promise<unknown>
  getCurrentNutritionConfig?(session: PersonalDataSession): Promise<import('../domain/profile').NutritionConfig | null>
  saveMyProfile?(profile: Record<string, unknown>, preferences: string[], version: string, session: PersonalDataSession): Promise<unknown>
}

interface ProfileRow extends Record<string, unknown> { version?: string | number | bigint }

const preferenceKeys = {
  'gluten-free': 'gluten-free', vegetarian: 'vegetarian', vegan: 'vegan',
  'lactose-free': 'lactose-free', 'nut-free': 'nut-free',
} satisfies Record<DietaryPreference, string>

function parseVersion(value: unknown): string {
  if (value === undefined || value === null) return '0'
  try {
    if (typeof value === 'number' && !Number.isSafeInteger(value)) throw new Error()
    const parsed = BigInt(value as string | number | bigint)
    if (parsed < 0n) throw new Error()
    return parsed.toString()
  } catch { throw new Error('El servidor devolvió una versión de perfil inválida.') }
}

export function mapRowToDraft(row: ProfileRow | null, keys: string[]): ProfileDraft {
  if (!row) return {}
  const keyToPreference = new Map(Object.entries(preferenceKeys).map(([preference, key]) => [key, preference as DietaryPreference]))
  const preferences = keys.map((key) => keyToPreference.get(key)).filter((item): item is DietaryPreference => item !== undefined)
  return parseProfileDraft({
    name: row.display_name, birthDate: row.birth_date,
    weightKg: row.weight_kg === null ? undefined : Number(row.weight_kg),
    heightCm: row.height_cm === null ? undefined : Number(row.height_cm),
    metabolicSex: row.metabolic_sex, activityLevel: row.activity_level, goal: row.goal,
    preferences,
  })
}

function mapDraftToRow(profile: ProfileDraft): Record<string, unknown> {
  return {
    display_name: profile.name ?? '', birth_date: profile.birthDate ?? null,
    weight_kg: profile.weightKg ?? null, height_cm: profile.heightCm ?? null,
    metabolic_sex: profile.metabolicSex ?? null, activity_level: profile.activityLevel ?? null,
    goal: profile.goal ?? null,
  } satisfies Record<string, unknown>
}

function isConflict(error: unknown): boolean {
  if (!error || typeof error !== 'object') return false
  const candidate = error as { code?: unknown; message?: unknown }
  return candidate.code === '40001' || typeof candidate.message === 'string' && /40001|perfil cambió|perfil cambio/i.test(candidate.message)
}

export function createProfileRepository(dependencies: ProfileRepositoryDependencies = {
  isSupabaseConfigured, relationalProfiles: isRelationalProfilesEnabled, loadPersonalData, savePersonalData,
  async getCurrentNutritionConfig(session) {
    assertPersonalDataSessionCurrent(session)
    const config = await nutritionRepository.getCurrent()
    assertPersonalDataSessionCurrent(session)
    return config
  },
  async getMyProfile(session) {
    assertPersonalDataSessionCurrent(session)
    const { data: { user }, error: userError } = await supabase!.auth.getUser()
    if (userError) throw userError
    if (!user) throw new Error('Iniciá sesión para consultar tu perfil.')
    assertPersonalDataOwner(session, user.id)
    const { data, error } = await supabase!.rpc('get_my_profile')
    if (error) throw error
    assertPersonalDataOwner(session, user.id)
    return data
  },
  async saveMyProfile(profile, preferences, version, session) {
    assertPersonalDataSessionCurrent(session)
    const { data: { user }, error: userError } = await supabase!.auth.getUser()
    if (userError) throw userError
    if (!user) throw new Error('Iniciá sesión para guardar tu perfil.')
    assertPersonalDataOwner(session, user.id)
    const { data, error } = await supabase!.rpc('save_my_profile', {
      p_profile: profile, p_preference_keys: preferences, p_expected_version: version,
    })
    if (error) throw error
    assertPersonalDataOwner(session, user.id)
    return data
  },
}) {
  let versionIdentity: string | null = null
  let loadedVersion = '0'
  let hasLoadedBaseline = false
  let conflictNeedsReload = false
  let preservedPreferenceKeys: string[] = []
  let profileReadSequence = 0
  const relational = dependencies.relationalProfiles === true

  async function readRelational(session: PersonalDataSession): Promise<{ draft: ProfileDraft; version: string; preferenceKeys: string[]; exists: boolean }> {
    if (!dependencies.getMyProfile) throw new Error('No está disponible el repositorio relacional de perfiles.')
    const result = await dependencies.getMyProfile(session)
    assertPersonalDataSessionCurrent(session)
    if (!result || typeof result !== 'object') throw new Error('El servidor devolvió un perfil inválido.')
    const envelope = result as Record<string, unknown>
    if (!Array.isArray(envelope.preference_keys) || envelope.preference_keys.some((key) => typeof key !== 'string')) {
      throw new Error('El servidor devolvió preferencias inválidas.')
    }
    if (envelope.profile !== null && (!envelope.profile || typeof envelope.profile !== 'object' || Array.isArray(envelope.profile))) {
      throw new Error('El servidor devolvió un perfil inválido.')
    }
    const row = envelope.profile as ProfileRow | null
    const ownerId = session.token?.startsWith('supabase-user:') ? session.token.slice('supabase-user:'.length) : null
    if (row && typeof row.user_id === 'string' && ownerId !== row.user_id) throw new Error('La cuenta cambió mientras se procesaban tus datos. Volvé a intentarlo.')
    const version = row === null ? parseVersion(undefined) : parseVersion(row.version)
    if (row && BigInt(version) < 1n) throw new Error('El servidor devolvió una versión de perfil inválida.')
    const nutritionConfig = dependencies.getCurrentNutritionConfig ? await dependencies.getCurrentNutritionConfig(session) : null
    assertPersonalDataSessionCurrent(session)
    return { draft: { ...mapRowToDraft(row, envelope.preference_keys as string[]), nutritionConfig }, version, preferenceKeys: envelope.preference_keys as string[], exists: row !== null }
  }

  function identityFor(session: PersonalDataSession): string {
    return `${session.token ?? ''}|${session.localRevision}|${session.supabaseRevision}`
  }

  function resetIdentity(session: PersonalDataSession): void {
    const identity = identityFor(session)
    if (identity !== versionIdentity) {
      versionIdentity = identity
      loadedVersion = '0'
      hasLoadedBaseline = false
      conflictNeedsReload = false
      preservedPreferenceKeys = []
    }
  }

  function bindVersion(session: PersonalDataSession, version: string): void {
    resetIdentity(session)
    loadedVersion = version
  }

  return {
    async getProfile() {
      const session = capturePersonalDataSession()
      resetIdentity(session)
      if (!dependencies.isSupabaseConfigured) return readLocalProfile()
      if (relational) {
        const readSequence = ++profileReadSequence
        const { draft, version, preferenceKeys: keys } = await readRelational(session)
        assertPersonalDataSessionCurrent(session)
        if (readSequence !== profileReadSequence) throw new Error('El perfil se actualizó mientras se cargaba. Volvé a consultar tus datos.')
        bindVersion(session, version)
        hasLoadedBaseline = true
        conflictNeedsReload = false
        // Unknown keys may represent inactive tags. Keep them in the next
        // full snapshot so the server can reject the save instead of deleting them.
        const known: Set<string> = new Set(Object.values(preferenceKeys))
        preservedPreferenceKeys = keys.filter((key) => !known.has(key))
        return { ...draft, email: getSession()?.email }
      }
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
    async saveProfile(profile: ProfileDraft) {
      const session = capturePersonalDataSession()
      if (relational) resetIdentity(session)
      if (dependencies.isSupabaseConfigured && relational) {
        profileReadSequence += 1
        if (!dependencies.saveMyProfile) throw new Error('No está disponible el guardado relacional de perfiles.')
        if (conflictNeedsReload) throw new Error('El perfil cambió en otra sesión. Recargá el perfil antes de volver a guardar.')
        let version: string
        if (versionIdentity === identityFor(session) && hasLoadedBaseline) version = loadedVersion
        else {
          // Resolve a version without applying the fetched values to the user's draft.
          const latest = await readRelational(session)
          if (latest.exists) throw new Error('El perfil ya existe en el servidor. Recargá el perfil antes de guardar tus cambios.')
          bindVersion(session, latest.version)
          version = latest.version
        }
        const requestedKeys = [...new Set([...(profile.preferences ?? []).map((preference: DietaryPreference) => preferenceKeys[preference]), ...preservedPreferenceKeys])]
        try {
          const saved = await dependencies.saveMyProfile(mapDraftToRow(profile), requestedKeys, version, session)
          assertPersonalDataSessionCurrent(session)
          const row = saved && typeof saved === 'object' ? saved as ProfileRow : null
          if (!row || row.version === undefined) throw new Error('El servidor no devolvió la nueva versión del perfil. Recargá el perfil antes de volver a guardar.')
          const savedVersion = parseVersion(row.version)
          if (BigInt(savedVersion) < 1n) throw new Error('El servidor no devolvió una versión válida del perfil.')
          bindVersion(session, savedVersion)
          hasLoadedBaseline = true
          if (typeof row.display_name === 'string' && session.token?.startsWith('supabase-user:')) {
            updateSupabaseSessionName(session.token.slice('supabase-user:'.length), row.display_name)
          }
        } catch (error) {
          assertPersonalDataSessionCurrent(session)
          if (isConflict(error)) {
            const latest = await readRelational(session)
            bindVersion(session, latest.version)
            const known: Set<string> = new Set(Object.values(preferenceKeys))
            preservedPreferenceKeys = latest.preferenceKeys.filter((key) => !known.has(key))
            conflictNeedsReload = true
            throw new Error('El perfil cambió en otra sesión. Recargá el perfil y volvé a aplicar tus cambios antes de guardar.')
          }
          if (error instanceof Error && /preferencias.*no disponibles/i.test(error.message)) {
            throw new Error('Una preferencia seleccionada ya no está disponible. Actualizá la selección antes de guardar.')
          }
          throw error
        }
        return
      }
      if (dependencies.isSupabaseConfigured) await dependencies.savePersonalData('profile', profile, session)
      assertPersonalDataSessionCurrent(session)
      saveLocalProfile(profile)
    },
  }
}

export const profileRepository = createProfileRepository()
