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

describe('local access flows', () => {
  beforeEach(() => localStorage.clear())

  test('registration validates identity, duplicate email and password', () => {
    const account = registerAccount(' Ana ', 'ANA@example.com', 'clave-segura')
    assert.deepEqual(account, { name: 'Ana', email: 'ana@example.com', password: 'clave-segura', role: 'USER' })
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

  test('route access is isolated by role and redirects to the role home', () => {
    assert.equal(canAccessPath('USER', '/recipes/one'), true)
    assert.equal(canAccessPath('USER', '/admin'), false)
    assert.equal(canAccessPath('ADMIN', '/admin/recipes'), true)
    assert.equal(canAccessPath('ADMIN', '/pantry'), false)
    assert.equal(roleHome('USER'), '/recipes')
    assert.equal(roleHome('ADMIN'), '/admin')
  })
})
