import { useEffect, useState } from 'react'
import { Navigate, Outlet, useMatch, useOutletContext } from 'react-router-dom'
import { LoadingScreen } from '../components/LoadingScreen'
import type { SessionInfo } from '../features/auth/data/localAuthStore'
import { profileRepository } from '../features/profile/data/ProfileRepository'
import type { ProfileDraft } from '../features/profile/domain/profile'
import { OnboardingPage } from '../pages/OnboardingPage'
import { SessionError } from './SessionError'

type SetupState = { status: 'loading' | 'ready' | 'error' } | { status: 'pending'; profile: ProfileDraft }

export function RequireUserSetup() {
  const { name, email } = useOutletContext<SessionInfo>()
  const setupRoute = useMatch('/onboarding')
  const [state, setState] = useState<SetupState>({ status: 'loading' })
  const [attempt, setAttempt] = useState(0)

  useEffect(() => {
    let active = true

    async function loadSetup() {
      try {
        const required = await profileRepository.getOnboardingRequired()
        if (!active) return
        if (!required) {
          setState({ status: 'ready' })
          return
        }
        const profile = await profileRepository.getOnboardingProfile()
        if (active) setState({ status: 'pending', profile })
      } catch {
        if (active) setState({ status: 'error' })
      }
    }

    void loadSetup()
    return () => { active = false }
  }, [attempt])

  if (state.status === 'loading') return <LoadingScreen message="Preparando tu cocina…" variant="fullscreen" />
  if (state.status === 'error') return <SessionError message="No pudimos cargar tu configuración inicial." retry={() => {
    setState({ status: 'loading' })
    setAttempt((current) => current + 1)
  }} />
  if (state.status === 'pending') {
    if (!setupRoute) return <Navigate replace to="/onboarding" />
    return <OnboardingPage
      initialProfile={{ ...state.profile, name: state.profile.name?.trim() || name, email }}
      onComplete={async (profile) => {
        await profileRepository.completeOnboarding(profile)
        setState({ status: 'ready' })
      }}
    />
  }
  return <Outlet />
}
