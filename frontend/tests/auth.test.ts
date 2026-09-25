const mockStorage = new Map()
global.localStorage = {
  getItem: (k) => mockStorage.get(k) || null,
  setItem: (k, v) => mockStorage.set(k, v),
  clear: () => mockStorage.clear(),
  removeItem: (k) => mockStorage.delete(k)
} as any
global.window = { dispatchEvent: () => {}, addEventListener: () => {}, removeEventListener: () => {} } as any

import assert from 'node:assert'
import test, { describe, beforeEach } from 'node:test'
import { getSession, startSession, endSession } from '../src/features/auth/data/localAuthStore'

describe('Auth Stores', () => {
  beforeEach(() => {
    localStorage.clear()
  })

  test('starts a session with ADMIN role', () => {
    startSession('ADMIN', 'admin@cocinapp.local', 'Administrador')
    const session = getSession()
    assert.strictEqual(session?.role, 'ADMIN')
    assert.strictEqual(session?.email, 'admin@cocinapp.local')
  })

  test('starts a session with USER role', () => {
    startSession('USER', 'user@cocinapp.local', 'Demo User')
    const session = getSession()
    assert.strictEqual(session?.role, 'USER')
  })

  test('ends session', () => {
    startSession('USER', 'user@cocinapp.local', 'Demo User')
    endSession()
    assert.strictEqual(getSession(), null)
  })

  test('handles corrupt session data gracefully', () => {
    localStorage.setItem('cocinapp.auth.v1', '{ invalid json')
    assert.strictEqual(getSession(), null)
  })
})

