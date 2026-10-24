import assert from 'node:assert/strict'
import test from 'node:test'
import { hasSessionExpired, monitorSessionPolicy, recordSessionActivity, startSessionPolicy, type SessionPolicyStorage } from '../src/features/auth/data/sessionTimeout'

class MemoryStorage implements SessionPolicyStorage {
  private values = new Map<string, string>()
  getItem(key: string) { return this.values.get(key) ?? null }
  setItem(key: string, value: string) { this.values.set(key, value) }
  removeItem(key: string) { this.values.delete(key) }
}

class FakeWindow {
  private listeners = new Map<string, Set<EventListener>>()
  private intervalCallback: (() => void) | null = null
  addEventListener(type: string, listener: EventListener) {
    const entries = this.listeners.get(type) ?? new Set<EventListener>()
    entries.add(listener)
    this.listeners.set(type, entries)
  }
  removeEventListener(type: string, listener: EventListener) { this.listeners.get(type)?.delete(listener) }
  setInterval(callback: TimerHandler) {
    this.intervalCallback = callback as () => void
    return 1
  }
  clearInterval() { this.intervalCallback = null }
  dispatch(type: string) { for (const listener of this.listeners.get(type) ?? []) listener(new Event(type)) }
  tick() { this.intervalCallback?.() }
}

const hour = 60 * 60 * 1000
const day = 24 * hour

test('desktop sessions expire after eight hours without activity', () => {
  const storage = new MemoryStorage()
  startSessionPolicy('user-a', 1_000, storage)

  assert.equal(hasSessionExpired('user-a', 'desktop', 1_000 + 8 * hour - 1, storage), false)
  assert.equal(hasSessionExpired('user-a', 'desktop', 1_000 + 8 * hour, storage), true)
})

test('mobile browser sessions expire after seven inactive days', () => {
  const storage = new MemoryStorage()
  startSessionPolicy('user-a', 1_000, storage)

  assert.equal(hasSessionExpired('user-a', 'mobile', 1_000 + 7 * day - 1, storage), false)
  assert.equal(hasSessionExpired('user-a', 'mobile', 1_000 + 7 * day, storage), true)
})

test('activity renews inactivity time but never extends the thirty-day maximum', () => {
  const storage = new MemoryStorage()
  startSessionPolicy('user-a', 1_000, storage)
  recordSessionActivity('user-a', 1_000 + 6 * day, storage, 'mobile')

  assert.equal(hasSessionExpired('user-a', 'mobile', 1_000 + 12 * day, storage), false)
  assert.equal(hasSessionExpired('user-a', 'mobile', 1_000 + 30 * day, storage), true)
})

test('a session already active before timeout tracking is introduced starts a fresh policy record', () => {
  const storage = new MemoryStorage()

  assert.equal(hasSessionExpired('user-a', 'desktop', 1_000, storage), false)
  assert.equal(hasSessionExpired('user-a', 'desktop', 1_000 + 8 * hour - 1, storage), false)
})

test('the active app signs out on timeout and recent activity extends only the idle deadline', () => {
  const storage = new MemoryStorage()
  const browser = new FakeWindow()
  let now = 1_000
  let expirations = 0
  startSessionPolicy('user-a', now, storage)
  monitorSessionPolicy('user-a', () => { expirations += 1 }, browser as unknown as Window, storage, () => now, 'desktop')

  now += 2 * hour
  browser.dispatch('pointerdown')
  now += 7 * hour
  browser.tick()
  assert.equal(expirations, 0)
  now += hour
  browser.tick()
  assert.equal(expirations, 1)
  browser.tick()
  assert.equal(expirations, 1)
})
