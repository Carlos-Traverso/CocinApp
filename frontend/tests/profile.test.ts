import assert from 'node:assert/strict'
import test from 'node:test'
import { calculateAge, calculateEnergyEstimate, estimateForProfile, profileIsComplete, recipeGoalPercentageRange } from '../src/features/profile/domain/profile'
import { readLocalProfile, saveLocalProfile } from '../src/features/profile/data/localProfileStore'
import { createProfileRepository } from '../src/features/profile/data/ProfileRepository'
import { endSession, getSession, startSupabaseUserSession } from '../src/features/auth/data/localAuthStore'
import type { PersonalDataSession } from '../src/shared/data/personalDataSession'

test('calculates age from the birth date without adding a year before the birthday', () => {
  const today = new Date(2026, 8, 23)

  assert.equal(calculateAge('2000-09-24', today), 25)
  assert.equal(calculateAge('2000-09-23', today), 26)
  assert.equal(calculateAge('2026-02-30', today), undefined)
  assert.equal(calculateAge('2027-01-01', today), undefined)
  assert.equal(calculateAge('2000-02-29', new Date(2026, 1, 28)), 25)
  assert.equal(calculateAge('fecha vieja', today), undefined)
})

test('applies distinct goal adjustments to the same activity-adjusted daily estimate', () => {
  const base = { weightKg: 70, heightCm: 175, age: 30, metabolicSex: 'male' as const, activityLevel: 'sedentary' as const }
  const maintain = calculateEnergyEstimate({ ...base, goal: 'maintain' })
  assert.equal(maintain.basalCalories, 1649)
  assert.equal(maintain.dailyCalories, 1979)
  assert.deepEqual(maintain.goalRange, { minimum: 1879, maximum: 2079 })
  assert.deepEqual(calculateEnergyEstimate({ ...base, goal: 'lose' }).goalRange, { minimum: 1379, maximum: 1579 })
  assert.deepEqual(calculateEnergyEstimate({ ...base, goal: 'gain' }).goalRange, { minimum: 2229, maximum: 2379 })
  assert.deepEqual(calculateEnergyEstimate({ ...base, goal: 'gain-muscle' }).goalRange, { minimum: 2179, maximum: 2279 })
  assert.equal(calculateEnergyEstimate({ ...base, activityLevel: 'active', goal: 'maintain' }).dailyCalories, 2844)
})

test('updates the estimate with edited profile fields and compares one portion to the goal range', () => {
  const profile = { name: 'Carla', birthDate: '1996-09-24', weightKg: 70, heightCm: 175, metabolicSex: 'female' as const, activityLevel: 'moderate' as const, goal: 'maintain' as const }
  const today = new Date(2026, 8, 25)
  const first = estimateForProfile(profile, today)!
  const muscle = estimateForProfile({ ...profile, goal: 'gain-muscle' }, today)!
  const moreActive = estimateForProfile({ ...profile, activityLevel: 'active' }, today)!
  assert.notDeepEqual(first.goalRange, muscle.goalRange)
  assert.ok(moreActive.dailyCalories > first.dailyCalories)
  assert.deepEqual(recipeGoalPercentageRange(first.goalRange.minimum, first), {
    minimum: Math.round(first.goalRange.minimum / first.goalRange.maximum * 100), maximum: 100,
  })
  assert.equal(recipeGoalPercentageRange(-1, first), undefined)
  assert.equal(estimateForProfile({ ...profile, birthDate: '2012-01-01' }, today), undefined)
})

test('calculates an informational daily energy estimate from Mifflin-St Jeor', () => {
  const estimate = calculateEnergyEstimate({
    weightKg: 70,
    heightCm: 175,
    age: 30,
    metabolicSex: 'female',
    activityLevel: 'moderate',
    goal: 'maintain',
  })

  assert.equal(estimate.basalCalories, 1483)
  assert.equal(estimate.dailyCalories, 2298)
  assert.deepEqual(estimate.goalRange, { minimum: 2198, maximum: 2398 })
})

test('requires the essential onboarding fields before considering a profile complete', () => {
  assert.equal(profileIsComplete({}), false)
  assert.equal(profileIsComplete({
    name: 'Carla',
    birthDate: '2000-09-23',
    weightKg: 64,
    heightCm: 168,
    metabolicSex: 'female',
    activityLevel: 'light',
    goal: 'maintain',
  }), true)
  assert.equal(profileIsComplete({ name: 'Carla', birthDate: '2000-01-01', weightKg: NaN, heightCm: 168, metabolicSex: 'female', activityLevel: 'light', goal: 'gain-muscle' }), false)
})

test('profile storage survives valid data and ignores malformed older values', () => {
  const entries = new Map<string, string>()
  const storage = { getItem: (key: string) => entries.get(key) ?? null, setItem: (key: string, value: string) => { entries.set(key, value) } }
  saveLocalProfile({ name: 'Carla', goal: 'maintain' }, storage)
  assert.deepEqual(readLocalProfile(storage), { name: 'Carla', email: undefined, birthDate: undefined, weightKg: undefined, heightCm: undefined, metabolicSex: undefined, activityLevel: undefined, goal: 'maintain', preferences: undefined })
  entries.set('cocinapp.profile.v1', '{bad')
  assert.deepEqual(readLocalProfile(storage), {})
  entries.set('cocinapp.profile.v1', JSON.stringify({ name: 'Carla', goal: 'unknown', weightKg: '70' }))
  assert.equal(readLocalProfile(storage).goal, undefined)
  assert.equal(readLocalProfile(storage).weightKg, undefined)
  entries.set('cocinapp.profile.v1', JSON.stringify({ name: 'Carla', goal: 'gain', activityLevel: 'light' }))
  assert.equal(readLocalProfile(storage).goal, 'gain')
  saveLocalProfile({ name: 'Carla', goal: 'gain-muscle' }, storage)
  assert.equal(readLocalProfile(storage).goal, 'gain-muscle')
})

test('discards an in-flight profile load from account A after switching to account B', async () => {
  localStorage.clear()
  let resolveLoad!: (value: unknown | null) => void
  const requestedSessions: PersonalDataSession[] = []
  let saveCalls = 0
  const repository = createProfileRepository({
    isSupabaseConfigured: true,
    loadPersonalData: async (_key, session) => {
      requestedSessions.push(session)
      return new Promise((resolve) => { resolveLoad = resolve })
    },
    savePersonalData: async () => { saveCalls += 1 },
  })

  startSupabaseUserSession('account-a', 'ana@example.com', 'Ana')
  const pendingLoad = repository.getProfile()
  assert.equal(requestedSessions[0]?.token, 'supabase-user:account-a')

  startSupabaseUserSession('account-b', 'luis@example.com', 'Luis')
  resolveLoad({ name: 'Dato privado de Ana', goal: 'lose' })

  await assert.rejects(pendingLoad, /La sesión cambió/)
  const accountAProfile = localStorage.getItem('cocinapp.user.ana%40example.com.cocinapp.profile.v1')
  const accountBProfile = localStorage.getItem('cocinapp.user.luis%40example.com.cocinapp.profile.v1')
  assert.equal(accountAProfile?.includes('Dato privado de Ana'), false)
  assert.equal(accountBProfile?.includes('Dato privado de Ana'), false)
  assert.equal(saveCalls, 0)
  localStorage.clear()
})

test('does not import account A local data after switching accounts during the remote check', async () => {
  localStorage.clear()
  let resolveLoad!: (value: unknown | null) => void
  const saveSessions: PersonalDataSession[] = []
  const repository = createProfileRepository({
    isSupabaseConfigured: true,
    loadPersonalData: async () => new Promise((resolve) => { resolveLoad = resolve }),
    savePersonalData: async (_key, _value, session) => { saveSessions.push(session) },
  })

  startSupabaseUserSession('account-a', 'ana@example.com', 'Ana')
  saveLocalProfile({ name: 'Perfil privado de Ana', goal: 'gain' })
  const pendingLoad = repository.getProfile()
  startSupabaseUserSession('account-b', 'luis@example.com', 'Luis')
  resolveLoad(null)

  await assert.rejects(pendingLoad, /La sesión cambió/)
  assert.deepEqual(saveSessions, [])
  assert.equal(localStorage.getItem('cocinapp.user.luis%40example.com.cocinapp.profile.v1')?.includes('Perfil privado de Ana'), false)
  localStorage.clear()
})

test('discards a pending load after the same account signs out and back in', async () => {
  localStorage.clear()
  let resolveLoad!: (value: unknown | null) => void
  const repository = createProfileRepository({
    isSupabaseConfigured: true,
    loadPersonalData: async () => new Promise((resolve) => { resolveLoad = resolve }),
    savePersonalData: async () => {},
  })

  startSupabaseUserSession('account-a', 'ana@example.com', 'Ana')
  const pendingLoad = repository.getProfile()
  endSession()
  startSupabaseUserSession('account-a', 'ana@example.com', 'Ana')
  resolveLoad({ name: 'Resultado de la sesión anterior', goal: 'lose' })

  await assert.rejects(pendingLoad, /La sesión cambió/)
  assert.equal(localStorage.getItem('cocinapp.user.ana%40example.com.cocinapp.profile.v1')?.includes('Resultado de la sesión anterior'), false)
  localStorage.clear()
})

test('keeps a pending profile save bound to account A and skips its cache write after switching to B', async () => {
  localStorage.clear()
  let resolveSave!: () => void
  const saveSessions: PersonalDataSession[] = []
  const repository = createProfileRepository({
    isSupabaseConfigured: true,
    loadPersonalData: async () => null,
    savePersonalData: async (_key, _value, session) => {
      saveSessions.push(session)
      await new Promise<void>((resolve) => { resolveSave = resolve })
    },
  })

  startSupabaseUserSession('account-a', 'ana@example.com', 'Ana')
  const pendingSave = repository.saveProfile({ name: 'Dato privado de Ana' })
  assert.equal(saveSessions[0]?.token, 'supabase-user:account-a')
  startSupabaseUserSession('account-b', 'luis@example.com', 'Luis')
  resolveSave()

  await assert.rejects(pendingSave, /La sesión cambió/)
  assert.equal(localStorage.getItem('cocinapp.user.luis%40example.com.cocinapp.profile.v1')?.includes('Dato privado de Ana'), false)
  localStorage.clear()
})

test('maps relational rows and stable preference keys without importing browser profile data', async () => {
  localStorage.clear()
  startSupabaseUserSession('relational-user', 'rel@example.com', 'Metadata name')
  saveLocalProfile({ name: 'Legacy local profile', goal: 'lose' })
  const repository = createProfileRepository({
    isSupabaseConfigured: true, relationalProfiles: true,
    loadPersonalData: async () => { throw new Error('legacy profile path used') },
    savePersonalData: async () => { throw new Error('legacy profile path used') },
    getMyProfile: async () => ({
      profile: { user_id: 'relational-user', display_name: 'Perfil oficial', birth_date: '1992-04-03', weight_kg: '72.50', height_cm: '171.00', metabolic_sex: 'female', activity_level: 'very-active', goal: 'gain-muscle', version: '9007199254740993' },
      preference_keys: ['gluten-free', 'vegetarian', 'vegan', 'lactose-free', 'nut-free'],
    }),
    saveMyProfile: async () => null,
  })

  assert.deepEqual(await repository.getProfile(), {
    nutritionConfig: null, name: 'Perfil oficial', email: 'rel@example.com', birthDate: '1992-04-03', weightKg: 72.5, heightCm: 171,
    metabolicSex: 'female', activityLevel: 'very-active', goal: 'gain-muscle',
    preferences: ['gluten-free', 'vegetarian', 'vegan', 'lactose-free', 'nut-free'],
  })
  assert.match(localStorage.getItem('cocinapp.user.rel%40example.com.cocinapp.profile.v1') ?? '', /Legacy local profile/)
  localStorage.clear()
})

test('relational read returns an empty draft when profile row is missing', async () => {
  startSupabaseUserSession('empty-profile-user', 'empty@example.com', 'Auth name')
  const repository = createProfileRepository({
    isSupabaseConfigured: true, relationalProfiles: true,
    loadPersonalData: async () => null, savePersonalData: async () => {},
    getMyProfile: async () => ({ profile: null, preference_keys: [] }),
    saveMyProfile: async () => null,
  })
  assert.deepEqual(await repository.getProfile(), { email: 'empty@example.com', nutritionConfig: null })
})

test('sends a full relational snapshot with string version and stable keys', async () => {
  startSupabaseUserSession('profile-save-user', 'save@example.com', 'Metadata')
  const writes: { profile: Record<string, unknown>; preferences: string[]; version: string }[] = []
  const repository = createProfileRepository({
    isSupabaseConfigured: true, relationalProfiles: true,
    loadPersonalData: async () => null, savePersonalData: async () => {},
    getMyProfile: async () => ({ profile: { version: '7' }, preference_keys: [] }),
    saveMyProfile: async (profile, preferences, version) => {
      writes.push({ profile, preferences, version })
      return { version: '8' }
    },
  })
  await repository.getProfile()
  await repository.saveProfile({ name: 'Nombre', birthDate: '2000-01-02', weightKg: 65, heightCm: 166, metabolicSex: 'male', activityLevel: 'light', goal: 'lose', preferences: ['vegan', 'nut-free'] })
  assert.deepEqual(writes, [{
    profile: { display_name: 'Nombre', birth_date: '2000-01-02', weight_kg: 65, height_cm: 166, metabolic_sex: 'male', activity_level: 'light', goal: 'lose' },
    preferences: ['vegan', 'nut-free'], version: '7',
  }])
})

test('refreshes after a relational version conflict and blocks another save until a user reloads', async () => {
  let reads = 0
  let writes = 0
  const repository = createProfileRepository({
    isSupabaseConfigured: true, relationalProfiles: true,
    loadPersonalData: async () => null, savePersonalData: async () => {},
    getMyProfile: async () => { reads += 1; return { profile: { version: String(reads) }, preference_keys: [] } },
    saveMyProfile: async () => { writes += 1; throw Object.assign(new Error('serialization failure'), { code: '40001' }) },
  })
  await repository.getProfile()
  await assert.rejects(repository.saveProfile({ name: 'Mi borrador' }), /Recargá el perfil/)
  assert.equal(reads, 2)
  assert.equal(writes, 1)
  await assert.rejects(repository.saveProfile({ name: 'Mi borrador' }), /Recargá el perfil/)
  assert.equal(writes, 1)
  await repository.getProfile()
  await assert.rejects(repository.saveProfile({ name: 'Mi borrador' }), /Recargá el perfil/)
  assert.equal(writes, 2)
})

test('does not send a relational read result across accounts', async () => {
  let resolveRead!: (value: unknown) => void
  const repository = createProfileRepository({
    isSupabaseConfigured: true, relationalProfiles: true,
    loadPersonalData: async () => null, savePersonalData: async () => {},
    getMyProfile: async () => new Promise((resolve) => { resolveRead = resolve }),
    saveMyProfile: async () => null,
  })
  startSupabaseUserSession('read-account-a', 'read-a@example.com', 'A')
  const pending = repository.getProfile()
  startSupabaseUserSession('read-account-b', 'read-b@example.com', 'B')
  resolveRead({ profile: { display_name: 'Private A', version: '2' }, preference_keys: [] })
  await assert.rejects(pending, /La sesión cambió/)
})

test('does not permit repeated saves from a stale draft without explicitly loading an existing profile', async () => {
  let saves = 0
  const repository = createProfileRepository({
    isSupabaseConfigured: true, relationalProfiles: true,
    loadPersonalData: async () => null, savePersonalData: async () => {},
    getMyProfile: async () => ({ profile: { display_name: 'Server value', version: '9' }, preference_keys: [] }),
    saveMyProfile: async () => { saves += 1; return { version: '10' } },
  })
  for (let attempt = 0; attempt < 2; attempt += 1) {
    await assert.rejects(repository.saveProfile({ name: 'Possibly stale value' }), /Recargá el perfil/)
  }
  assert.equal(saves, 0)
})

test('rejects an existing relational profile without a valid bigint version', async () => {
  const repository = createProfileRepository({
    isSupabaseConfigured: true, relationalProfiles: true,
    loadPersonalData: async () => null, savePersonalData: async () => {},
    getMyProfile: async () => ({ profile: { display_name: 'Existing', version: null }, preference_keys: [] }),
    saveMyProfile: async () => null,
  })
  await assert.rejects(repository.getProfile(), /versión de perfil inválida/)
})

test('clears conflict and inactive preference state when changing accounts', async () => {
  let readsA = 0
  const writes: { preferences: string[]; version: string }[] = []
  const repository = createProfileRepository({
    isSupabaseConfigured: true, relationalProfiles: true,
    loadPersonalData: async () => null, savePersonalData: async () => {},
    getMyProfile: async (session) => {
      if (session.token === 'supabase-user:conflict-a') {
        readsA += 1
        return { profile: { user_id: 'conflict-a', version: String(readsA) }, preference_keys: readsA > 1 ? ['inactive-a'] : [] }
      }
      return { profile: null, preference_keys: [] }
    },
    saveMyProfile: async (_profile, preferences, version, session) => {
      writes.push({ preferences, version })
      if (session.token === 'supabase-user:conflict-a') throw Object.assign(new Error('version mismatch'), { code: '40001' })
      return { version: '1' }
    },
  })
  startSupabaseUserSession('conflict-a', 'a@example.com', 'A')
  await repository.getProfile()
  await assert.rejects(repository.saveProfile({ name: 'A' }), /Recargá el perfil/)
  startSupabaseUserSession('conflict-b', 'b@example.com', 'B')
  await repository.saveProfile({ name: 'B' })
  assert.deepEqual(writes, [{ preferences: [], version: '1' }, { preferences: [], version: '0' }])
})

test('keeps a loaded version usable after updating the canonical displayed name', async () => {
  startSupabaseUserSession('name-update-user', 'name@example.com', 'Old metadata name')
  const expectedVersions: string[] = []
  const repository = createProfileRepository({
    isSupabaseConfigured: true, relationalProfiles: true,
    loadPersonalData: async () => null, savePersonalData: async () => {},
    getMyProfile: async () => ({ profile: { user_id: 'name-update-user', display_name: 'Old name', version: '1' }, preference_keys: [] }),
    saveMyProfile: async (profile, _preferences, version) => {
      expectedVersions.push(version)
      return { ...profile, user_id: 'name-update-user', version: String(BigInt(version) + 1n) }
    },
  })
  await repository.getProfile()
  await repository.saveProfile({ name: 'Canonical new name' })
  assert.equal(getSession()?.name, 'Canonical new name')
  await repository.saveProfile({ name: 'Next edit' })
  assert.deepEqual(expectedVersions, ['1', '2'])
})
