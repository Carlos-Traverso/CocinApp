export type SessionDevice = 'desktop' | 'mobile'

export interface SessionPolicyStorage {
  getItem(key: string): string | null
  setItem(key: string, value: string): void
  removeItem(key: string): void
}

interface SessionPolicyRecord {
  signedInAt: number
  lastActivityAt: number
}

const storageKeyPrefix = 'cocinapp.session-policy.v1.'
const activityWriteIntervalMs = 60_000

export const sessionTimeouts = {
  desktopIdleMs: 8 * 60 * 60 * 1000,
  mobileIdleMs: 7 * 24 * 60 * 60 * 1000,
  maximumLifetimeMs: 30 * 24 * 60 * 60 * 1000,
} as const

function keyFor(identity: string): string {
  return `${storageKeyPrefix}${encodeURIComponent(identity)}`
}

function readRecord(identity: string, storage: SessionPolicyStorage): SessionPolicyRecord | null {
  try {
    const value: unknown = JSON.parse(storage.getItem(keyFor(identity)) ?? 'null')
    if (!value || typeof value !== 'object') return null
    const record = value as Record<string, unknown>
    if (typeof record.signedInAt !== 'number' || !Number.isFinite(record.signedInAt)
      || typeof record.lastActivityAt !== 'number' || !Number.isFinite(record.lastActivityAt)) return null
    return { signedInAt: record.signedInAt, lastActivityAt: record.lastActivityAt }
  } catch {
    return null
  }
}

export function detectSessionDevice(userAgent = typeof navigator === 'undefined' ? '' : navigator.userAgent): SessionDevice {
  const navigatorInfo = typeof navigator === 'undefined' ? null : navigator as Navigator & { userAgentData?: { mobile?: boolean } }
  const isTouchIPad = navigatorInfo?.platform === 'MacIntel' && navigatorInfo.maxTouchPoints > 1
  return navigatorInfo?.userAgentData?.mobile === true
    || isTouchIPad
    || /Android|iPhone|iPad|iPod|Mobile|Windows Phone/i.test(userAgent)
    ? 'mobile'
    : 'desktop'
}

export function startSessionPolicy(identity: string, now = Date.now(), storage: SessionPolicyStorage = localStorage): void {
  storage.setItem(keyFor(identity), JSON.stringify({ signedInAt: now, lastActivityAt: now } satisfies SessionPolicyRecord))
}

export function clearSessionPolicy(identity: string, storage: SessionPolicyStorage = localStorage): void {
  storage.removeItem(keyFor(identity))
}

export function hasSessionExpired(
  identity: string,
  device: SessionDevice,
  now = Date.now(),
  storage: SessionPolicyStorage = localStorage,
): boolean {
  let record = readRecord(identity, storage)
  if (!record) {
    // Preserve sessions that were already active when this policy was introduced.
    startSessionPolicy(identity, now, storage)
    record = { signedInAt: now, lastActivityAt: now }
  }
  const idleLimit = device === 'mobile' ? sessionTimeouts.mobileIdleMs : sessionTimeouts.desktopIdleMs
  return now - record.lastActivityAt >= idleLimit || now - record.signedInAt >= sessionTimeouts.maximumLifetimeMs
}

export function recordSessionActivity(
  identity: string,
  now = Date.now(),
  storage: SessionPolicyStorage = localStorage,
  device: SessionDevice = detectSessionDevice(),
): boolean {
  if (hasSessionExpired(identity, device, now, storage)) return false
  const record = readRecord(identity, storage)
  if (!record) return false
  storage.setItem(keyFor(identity), JSON.stringify({ ...record, lastActivityAt: Math.max(now, record.lastActivityAt) } satisfies SessionPolicyRecord))
  return true
}

export function monitorSessionPolicy(
  identity: string,
  onExpired: () => void,
  targetWindow: Window = window,
  storage: SessionPolicyStorage = localStorage,
  now: () => number = Date.now,
  device: SessionDevice = detectSessionDevice(),
): () => void {
  let stopped = false
  let lastActivityWriteAt = now()
  let interval = 0

  const stop = () => {
    if (stopped) return
    stopped = true
    targetWindow.clearInterval(interval)
    for (const event of ['pointerdown', 'keydown', 'touchstart', 'wheel', 'focus', 'pageshow', 'storage']) {
      targetWindow.removeEventListener(event, check)
    }
  }
  const expireIfNeeded = () => {
    if (stopped || !hasSessionExpired(identity, device, now(), storage)) return false
    stop()
    onExpired()
    return true
  }
  const check = () => { expireIfNeeded() }
  const activity = () => {
    if (expireIfNeeded()) return
    const currentTime = now()
    if (currentTime - lastActivityWriteAt >= activityWriteIntervalMs) {
      recordSessionActivity(identity, currentTime, storage, device)
      lastActivityWriteAt = currentTime
    }
  }

  for (const event of ['pointerdown', 'keydown', 'touchstart', 'wheel']) {
    targetWindow.addEventListener(event, activity, { passive: true })
  }
  for (const event of ['focus', 'pageshow', 'storage']) targetWindow.addEventListener(event, check)
  interval = targetWindow.setInterval(check, 30_000)
  check()
  return stop
}
