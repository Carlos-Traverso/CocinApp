import { createClient } from '@supabase/supabase-js'

const projectUrl = import.meta.env.VITE_SUPABASE_URL?.trim()
const publishableKey = (
  import.meta.env.VITE_SUPABASE_PUBLISHABLE_KEY
  || import.meta.env.VITE_SUPABASE_ANON_KEY
)?.trim()

const hasPlaceholder = /your-project|your-publishable-key|your-public-anon-key/i.test(`${projectUrl ?? ''} ${publishableKey ?? ''}`)

export const isSupabaseConfigured = Boolean(projectUrl && publishableKey && !hasPlaceholder)

export const supabase = isSupabaseConfigured
  ? createClient(projectUrl!, publishableKey!)
  : null

const passwordRecoveryMarker = 'cocinapp.auth.password-recovery.v1'

// Record recovery callbacks during client initialization, before the router
// renders the public password reset route.
if (supabase && typeof window !== 'undefined') {
  supabase.auth.onAuthStateChange((event, session) => {
    if (event === 'SIGNED_OUT' || event === 'SIGNED_IN') clearPasswordRecoveryMarker()
    if (event !== 'PASSWORD_RECOVERY' || !session) return
    try { window.sessionStorage.setItem(passwordRecoveryMarker, 'true') } catch { /* The route also handles unavailable session storage. */ }
  })
}

export function hasPasswordRecoveryMarker(): boolean {
  try { return window.sessionStorage.getItem(passwordRecoveryMarker) === 'true' } catch { return false }
}

export function clearPasswordRecoveryMarker(): void {
  try { window.sessionStorage.removeItem(passwordRecoveryMarker) } catch { /* Ignore unavailable session storage. */ }
}
