const LAST_ACTIVITY_KEY = 'uportal_idle_last_activity_at'
const LOGOUT_EVENT_KEY = 'uportal_idle_logout_at'
const DEFAULT_IDLE_TIMEOUT_MINUTES = 15
const MIN_ACTIVITY_WRITE_MS = 1000
const MAX_CHECK_DELAY_MS = 30000

const ACTIVITY_EVENTS = [
  'pointerdown',
  'keydown',
  'scroll',
  'touchstart',
  'mousemove',
  'focus'
]

export { DEFAULT_IDLE_TIMEOUT_MINUTES }

export function normalizeIdleTimeoutMinutes(value) {
  const number = Number(value)
  if (!Number.isFinite(number) || number <= 0) return DEFAULT_IDLE_TIMEOUT_MINUTES
  return Math.max(1, Math.floor(number))
}

export function extractIdleTimeoutMinutes(profile) {
  return normalizeIdleTimeoutMinutes(
      profile?.idle_timeout_minutes ??
      profile?.idleTimeoutMinutes ??
      profile?.idleTimeout
  )
}

export function recordIdleActivity() {
  safeSetItem(LAST_ACTIVITY_KEY, String(Date.now()))
}

export function publishIdleLogout(reason = 'logout') {
  safeSetItem(LOGOUT_EVENT_KEY, JSON.stringify({
    reason,
    at: Date.now()
  }))
}

export function startIdleLogout({ timeoutMinutes, onTimeout, onRemoteLogout }) {
  const timeoutMs = normalizeIdleTimeoutMinutes(timeoutMinutes) * 60 * 1000
  let stopped = false
  let timer = null
  let lastActivityWriteAt = 0
  let timeoutStarted = false

  function writeActivity() {
    const now = Date.now()
    if (now - lastActivityWriteAt < MIN_ACTIVITY_WRITE_MS) return
    lastActivityWriteAt = now
    safeSetItem(LAST_ACTIVITY_KEY, String(now))
  }

  function lastActivityAt() {
    const value = Number(safeGetItem(LAST_ACTIVITY_KEY) || 0)
    return Number.isFinite(value) && value > 0 ? value : Date.now()
  }

  function scheduleCheck() {
    if (stopped) return
    clearTimeout(timer)

    const elapsed = Date.now() - lastActivityAt()
    const remaining = timeoutMs - elapsed
    if (remaining <= 0) {
      runTimeout()
      return
    }

    timer = setTimeout(scheduleCheck, Math.min(Math.max(remaining, 1000), MAX_CHECK_DELAY_MS))
  }

  function runTimeout() {
    if (timeoutStarted || stopped) return
    timeoutStarted = true
    publishIdleLogout('idle')
    Promise.resolve(onTimeout?.()).catch(() => {})
  }

  function handleActivity() {
    if (stopped || timeoutStarted) return
    writeActivity()
    scheduleCheck()
  }

  function handleStorage(event) {
    if (event.key === LAST_ACTIVITY_KEY) {
      scheduleCheck()
      return
    }

    if (event.key === LOGOUT_EVENT_KEY && event.newValue) {
      Promise.resolve(onRemoteLogout?.()).catch(() => {})
    }
  }

  writeActivity()
  scheduleCheck()
  ACTIVITY_EVENTS.forEach((eventName) => {
    window.addEventListener(eventName, handleActivity, { capture: true, passive: true })
  })
  window.addEventListener('storage', handleStorage)

  return () => {
    stopped = true
    clearTimeout(timer)
    ACTIVITY_EVENTS.forEach((eventName) => {
      window.removeEventListener(eventName, handleActivity, { capture: true })
    })
    window.removeEventListener('storage', handleStorage)
  }
}

function safeGetItem(key) {
  try {
    return globalThis.localStorage?.getItem?.(key) || ''
  } catch {
    return ''
  }
}

function safeSetItem(key, value) {
  try {
    globalThis.localStorage?.setItem?.(key, value)
  } catch {
    // localStorage may be unavailable in hardened browser contexts.
  }
}
