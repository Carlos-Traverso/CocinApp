const mockStorage = new Map<string, string>()
global.localStorage = {
  getItem: (key: string) => mockStorage.get(key) ?? null,
  setItem: (key: string, value: string) => mockStorage.set(key, value),
  clear: () => mockStorage.clear(),
  removeItem: (key: string) => mockStorage.delete(key),
  key: (index: number) => [...mockStorage.keys()][index] ?? null,
  get length() { return mockStorage.size },
} as unknown as Storage
global.window = { dispatchEvent: () => {}, addEventListener: () => {}, removeEventListener: () => {} } as unknown as Window & typeof globalThis

import assert from 'node:assert/strict'
import test, { beforeEach, describe } from 'node:test'
import { authenticateUser, demoAdminEmail, endSession, getSession, registerAccount, startDemoAdminSession, startSession, startUserSession } from '../src/features/auth/data/localAuthStore'
import { canAccessPath, roleHome } from '../src/features/auth/domain/routeAccess'
import { personalStorage } from '../src/features/auth/data/personalStorage'
import { adminUsersRepository } from '../src/features/admin/data/AdminUsersRepository'

describe('local access flows', () => {
  beforeEach(() => localStorage.clear())

  test('registration validates identity, duplicate email and password', () => {
    const account = registerAccount(' Ana ', 'ANA@example.com', 'clave-segura')
    assert.deepEqual(account, { name: 'Ana', email: 'ana@example.com', password: 'clave-segura', role: 'USER', active: true })
    assert.throws(() => registerAccount('Ana', 'ana@example.com', 'clave-segura'), /Ya existe/)
    assert.throws(() => registerAccount('Ana', 'correo-inválido', 'clave-segura'), /correo electrónico válido/)
    assert.throws(() => registerAccount('Ana', 'otra@example.com', 'corta'), /8 caracteres/)
    assert.throws(() => registerAccount('Admin', demoAdminEmail, 'clave-segura'), /Ya existe/)
  })

  test('a registered USER can sign in, retain session and sign out', () => {
    const account = registerAccount('Ana', 'ana@example.com', 'clave-segura')
    startUserSession(authenticateUser('ANA@example.com', 'clave-segura'))
    assert.equal(getSession()?.role, 'USER')
    assert.equal(getSession()?.email, account.email)
    assert.throws(() => authenticateUser(account.email, 'incorrecta'), /no son correctos/)
    endSession()
    assert.equal(getSession(), null)
  })

  test('personal records migrate to the first account and remain isolated between users', () => {
    localStorage.setItem('cocinapp.profile.v1', JSON.stringify({ name: 'Datos anteriores', email: 'ana@example.com' }))
    const first = registerAccount('Ana', 'ana@example.com', 'clave-segura')
    startUserSession(first)
    assert.equal(personalStorage.getItem('cocinapp.profile.v1'), JSON.stringify({ name: 'Datos anteriores', email: 'ana@example.com' }))
    personalStorage.setItem('cocinapp.profile.v1', JSON.stringify({ name: 'Ana' }))
    endSession()

    const second = registerAccount('Luis', 'luis@example.com', 'clave-segura')
    startUserSession(second)
    assert.equal(personalStorage.getItem('cocinapp.profile.v1'), JSON.stringify({ name: second.name, email: second.email }))
    personalStorage.setItem('cocinapp.profile.v1', JSON.stringify({ name: 'Luis' }))
    endSession()
    startUserSession(first)
    assert.equal(personalStorage.getItem('cocinapp.profile.v1'), JSON.stringify({ name: 'Ana' }))
  })

  test('unowned legacy personal data is preserved without being assigned to a new account', () => {
    const legacyProfile = JSON.stringify({ name: 'Otra persona', email: 'otra@example.com' })
    localStorage.setItem('cocinapp.profile.v1', legacyProfile)
    localStorage.setItem('cocinapp.pantry.v1', JSON.stringify([{ id: 'old', name: 'Harina' }]))
    const account = registerAccount('Nueva cuenta', 'nueva@example.com', 'clave-segura')
    startUserSession(account)
    assert.equal(personalStorage.getItem('cocinapp.profile.v1'), JSON.stringify({ name: account.name, email: account.email }))
    assert.equal(personalStorage.getItem('cocinapp.pantry.v1'), null)
    assert.equal(localStorage.getItem('cocinapp.profile.v1'), legacyProfile)
    assert.notEqual(localStorage.getItem('cocinapp.pantry.v1'), null)
  })

  test('ADMIN access is limited to the predefined local demonstration identity', () => {
    startDemoAdminSession()
    assert.equal(getSession()?.role, 'ADMIN')
    assert.throws(() => startSession('ADMIN', 'otro@cocinapp.local', 'Administrador'), /demostración/)
  })

  test('invalid, obsolete and malformed sessions are cleared', () => {
    localStorage.setItem('cocinapp.auth.v1', '{ invalid json')
    assert.equal(getSession(), null)
    assert.equal(localStorage.getItem('cocinapp.auth.v1'), null)
    localStorage.setItem('cocinapp.auth.v1', JSON.stringify({ token: 'old', role: 'SUPERADMIN', email: 'x', name: 'X' }))
    assert.equal(getSession(), null)
    localStorage.setItem('cocinapp.auth.v1', JSON.stringify({ token: 'old', role: 'USER', email: 'gone@example.com', name: 'Gone' }))
    assert.equal(getSession(), null)
  })

  test('legacy accounts default to active and inactive accounts cannot sign in or retain sessions', () => {
    localStorage.setItem('cocinapp.accounts.v1', JSON.stringify([{ name: 'Ana', email: 'ana@example.com', password: 'clave-segura', role: 'USER' }]))
    assert.equal(authenticateUser('ana@example.com', 'clave-segura').active, true)
    startSession('USER', 'ana@example.com', 'Ana')
    localStorage.setItem('cocinapp.accounts.v1', JSON.stringify([{ name: 'Ana', email: 'ana@example.com', password: 'clave-segura', role: 'USER', active: false }]))
    assert.equal(getSession(), null)
    assert.throws(() => authenticateUser('ana@example.com', 'clave-segura'), /no son correctos/)
    assert.throws(() => startSession('USER', 'ana@example.com', 'Ana'), /no está disponible/)
    assert.throws(() => startUserSession({ name: 'Ana', email: 'ana@example.com', password: 'clave-segura', role: 'USER' }), /no está disponible/)
  })

  test('admin user repository is guarded, hides passwords and keeps admin session on create', async () => {
    const user = registerAccount('Ana', 'ana@example.com', 'clave-segura')
    await assert.rejects(adminUsersRepository.list(), /administrador/)
    startUserSession(user)
    await assert.rejects(adminUsersRepository.setActive(user.email, false), /administrador/)
    startDemoAdminSession()
    localStorage.setItem('cocinapp.profile.v1', JSON.stringify({ name: 'Legacy' }))
    await adminUsersRepository.create('Luis', 'luis@example.com', 'clave-segura')
    assert.equal(getSession()?.role, 'ADMIN')
    assert.equal(personalStorage.getItem('cocinapp.profile.v1'), JSON.stringify({ name: 'Legacy' }))
    const listed = await adminUsersRepository.list()
    assert.deepEqual(listed[0], { email: demoAdminEmail, name: 'Administrador de demostración', role: 'ADMIN', active: true, isDemoAdmin: true })
    assert.equal(JSON.stringify(listed).includes('clave-segura'), false)
    await assert.rejects(adminUsersRepository.updateName(demoAdminEmail, 'Otro'), /demostración/)
    await assert.rejects(adminUsersRepository.setActive(demoAdminEmail, false), /demostración/)
    await adminUsersRepository.setActive(user.email, false)
    assert.equal((await adminUsersRepository.list()).find((entry) => entry.email === user.email)?.active, false)
    await assert.rejects(adminUsersRepository.updateName('missing@example.com', 'Nuevo'), /No existe/)
    await assert.rejects(adminUsersRepository.create('Ana', 'luis@example.com', 'clave-segura'), /Ya existe/)
  })

  test('admin can rename and toggle a user without changing credentials or personal data', async () => {
    const user = registerAccount('Ana', 'ana@example.com', 'clave-segura')
    startUserSession(user)
    personalStorage.setItem('cocinapp.profile.v1', JSON.stringify({ name: 'Ana', favorite: 'sopa' }))
    personalStorage.setItem('cocinapp.pantry.v1', JSON.stringify([{ name: 'Lentejas' }]))
    const profileKey = 'cocinapp.user.ana%40example.com.cocinapp.profile.v1'
    const pantryKey = 'cocinapp.user.ana%40example.com.cocinapp.pantry.v1'
    const originalProfile = localStorage.getItem(profileKey)
    const originalPantry = localStorage.getItem(pantryKey)

    endSession()
    startDemoAdminSession()
    await adminUsersRepository.updateName(user.email, 'Ana Pérez')
    assert.equal(getSession()?.role, 'ADMIN')
    const updatedAccount = JSON.parse(localStorage.getItem('cocinapp.accounts.v1') ?? '[]').find((entry: { email: string }) => entry.email === user.email)
    assert.deepEqual(updatedAccount, { ...user, name: 'Ana Pérez' })
    assert.equal(localStorage.getItem(profileKey), originalProfile)
    assert.equal(localStorage.getItem(pantryKey), originalPantry)

    await adminUsersRepository.setActive(user.email, false)
    assert.throws(() => authenticateUser(user.email, 'clave-segura'), /no son correctos/)
    assert.equal(localStorage.getItem(profileKey), originalProfile)
    assert.equal(localStorage.getItem(pantryKey), originalPantry)
    await adminUsersRepository.setActive(user.email, true)
    const signedIn = authenticateUser(user.email, 'clave-segura')
    assert.equal(signedIn.name, 'Ana Pérez')
    startUserSession(signedIn)
    assert.equal(personalStorage.getItem('cocinapp.profile.v1'), originalProfile)
    assert.equal(personalStorage.getItem('cocinapp.pantry.v1'), originalPantry)
  })

  test('route access is isolated by role and redirects to the role home', () => {
    assert.equal(canAccessPath('USER', '/recipes/one'), true)
    assert.equal(canAccessPath('USER', '/admin'), false)
    assert.equal(canAccessPath('ADMIN', '/admin/recipes'), true)
    assert.equal(canAccessPath('ADMIN', '/pantry'), false)
    assert.equal(roleHome('USER'), '/panel')
    assert.equal(roleHome('ADMIN'), '/admin')
  })
})
