import { LoadingScreen } from '../components/LoadingScreen'
import { KeyRound, PencilLine, Save, LogOut } from 'lucide-react'
import { type FormEvent, useEffect, useRef, useState } from 'react'
import { Link } from 'react-router-dom'
import { authRepository } from '../features/auth/data/AuthRepository'
import { profileRepository } from '../features/profile/data/ProfileRepository'
import { calculateAge, estimateForProfile, profileIsComplete, type ProfileDraft } from '../features/profile/domain/profile'
import { EnergySummary } from '../features/profile/ui/EnergySummary'
import { ChangePasswordDialog } from '../features/profile/ui/ChangePasswordDialog'
import { ProfileFields } from '../features/profile/ui/ProfileFields'
import { profileHeaderActions } from '../features/profile/ui/profileHeaderActions'
import { isRelationalProfilesEnabled, isSupabaseConfigured } from '../shared/data/supabaseClient'
import { writeFailureMessage } from '../shared/data/writeFailure'
import { useNotifications } from '../shared/notifications/NotificationProvider'

function profileFieldValidationMessage(field: HTMLInputElement | HTMLSelectElement): string {
  if (field.validity.valueMissing) return 'Completá los campos obligatorios del perfil.'
  if (field.validity.typeMismatch) return 'Ingresá un correo electrónico válido.'
  if (field.validity.rangeUnderflow || field.validity.rangeOverflow || field.validity.stepMismatch || field.validity.badInput) return 'Revisá el rango y el formato de las medidas.'
  return 'Revisá el dato ingresado.'
}

export function ProfilePage() {
  const [profile, setProfile] = useState<ProfileDraft>({})
  const [loading, setLoading] = useState(true)
  const [saving, setSaving] = useState(false)
  const [reloadRequired, setReloadRequired] = useState(false)
  const [loadAttempt, setLoadAttempt] = useState(0)
  const [loggingOut, setLoggingOut] = useState(false)
  const [changingPassword, setChangingPassword] = useState(false)
  const [passwordChanged, setPasswordChanged] = useState(false)
  const [savedProfile, setSavedProfile] = useState<ProfileDraft>()
  const [validationError, setValidationError] = useState('')
  const invalidFieldRef = useRef<HTMLInputElement | HTMLSelectElement | null>(null)
  const { notify } = useNotifications()
  useEffect(() => {
    let current = true
    void profileRepository.getProfile()
      .then((loadedProfile) => { if (current) { setProfile(loadedProfile); setReloadRequired(false) } })
      .catch(() => {
        if (!current) return
        setReloadRequired(true)
        void notify({ type: 'error', title: 'No se pudo cargar el perfil', message: 'Recargá el perfil para volver a intentarlo.' })
      })
      .finally(() => { if (current) setLoading(false) })
    return () => { current = false }
  }, [loadAttempt, notify])
  const age = profile.birthDate ? calculateAge(profile.birthDate) : undefined
  const estimate = estimateForProfile(profile)
  const relationalProfile = isSupabaseConfigured && isRelationalProfilesEnabled

  async function logout() {
    setLoggingOut(true)
    try { await authRepository.logout() }
    catch { await notify({ type: 'error', title: 'No se pudo cerrar la sesión', message: 'Intentá de nuevo.' }) }
    finally { setLoggingOut(false) }
  }

  async function save(event: FormEvent<HTMLFormElement>) {
    event.preventDefault()
    if (loading || saving || reloadRequired) return
    const form = event.currentTarget
    clearValidationError()
    if (!form.checkValidity()) {
      const invalidField = form.querySelector<HTMLInputElement | HTMLSelectElement>(':invalid')
      if (invalidField instanceof HTMLSelectElement && window.matchMedia('(max-width: 760px)').matches) {
        invalidField.closest('.filter-select')?.querySelector<HTMLButtonElement>('.filter-select-trigger')?.click()
      } else invalidField?.focus()
      showValidationError(invalidField, invalidField ? profileFieldValidationMessage(invalidField) : 'Revisá los datos ingresados.')
      return
    }
    if (!profile.name?.trim() || age === undefined || age < 18 || age > 100) {
      const emptyName = !profile.name?.trim()
      const field = form.querySelector<HTMLInputElement>(emptyName ? '[name="name"]' : '[name="birthDate"]')
      field?.focus()
      showValidationError(field, emptyName ? 'Ingresá tu nombre.' : 'Ingresá una fecha de nacimiento que corresponda a una edad entre 18 y 100 años.')
      return
    }
    if (!profileIsComplete(profile)) {
      showValidationError(null, 'Completá los datos requeridos con valores válidos antes de guardar el perfil.')
      return
    }
    setSaving(true)
    try {
      await profileRepository.saveProfile(profile)
      setSavedProfile(profile)
    }
    catch (error) {
      const message = writeFailureMessage(error, 'Recargá el perfil antes de volver a guardar.')
        ?? (error instanceof Error && /Recargá el perfil/.test(error.message) ? error.message : 'No se confirmó el guardado. Recargá el perfil antes de volver a intentar.')
      setReloadRequired(true)
      void notify({ type: 'error', title: 'No se pudo guardar el perfil', message })
    }
    finally { setSaving(false) }
  }

  function showValidationError(field: HTMLInputElement | HTMLSelectElement | null, message: string) {
    invalidFieldRef.current = field
    if (field) {
      const ids = field.getAttribute('aria-describedby')?.split(/\s+/).filter(Boolean) ?? []
      if (!ids.includes('profile-validation-error')) field.setAttribute('aria-describedby', [...ids, 'profile-validation-error'].join(' '))
    }
    setValidationError(message)
  }

  function clearValidationError() {
    const field = invalidFieldRef.current
    if (field) {
      const ids = field.getAttribute('aria-describedby')?.split(/\s+/).filter((id) => id && id !== 'profile-validation-error') ?? []
      if (ids.length) field.setAttribute('aria-describedby', ids.join(' '))
      else field.removeAttribute('aria-describedby')
    }
    invalidFieldRef.current = null
    setValidationError('')
  }

  return <div className="page profile-page">
    <header className="page-heading">
      <div><p className="eyebrow">CONFIGURACIÓN PERSONAL</p><h1>Mi perfil y preferencias</h1><p className="page-lead">Actualizá tus datos para que CocinAPP pueda priorizar recetas más útiles para vos.</p></div>
      <div className="profile-head-actions" aria-label="Acciones de perfil">
        {profileHeaderActions.map((action) => {
          if (action.id === 'recipes') return <Link className="button button-quiet" key={action.id} to={action.href}><PencilLine aria-hidden="true" size={17} /> {action.label}</Link>
          if (action.id === 'password') return <button aria-haspopup="dialog" className="button button-quiet" disabled={loggingOut} key={action.id} onClick={() => { setPasswordChanged(false); setChangingPassword(true) }} type="button"><KeyRound aria-hidden="true" size={17} /> {action.label}</button>
          return <button className="button button-signout" disabled={loggingOut} key={action.id} onClick={() => void logout()} type="button"><LogOut aria-hidden="true" size={17} /> {loggingOut ? 'Cerrando…' : action.label}</button>
        })}
      </div>
    </header>
    <div role="status">{passwordChanged && <p className="form-message success">Cambiaste tu contraseña correctamente.</p>}</div>
    {changingPassword && <ChangePasswordDialog
      onClose={() => setChangingPassword(false)}
      onChanged={() => { setChangingPassword(false); setPasswordChanged(true) }}
    />}
    <div className="profile-layout">
      <form className="profile-form surface" noValidate onInput={clearValidationError} onChange={clearValidationError} onSubmit={save}>
        {validationError && <p className="form-message error" id="profile-validation-error" role="alert">{validationError}</p>}
        <div className="section-heading"><div><h2>Datos y objetivos</h2><p>{isSupabaseConfigured ? 'Guardados en tu cuenta.' : 'Guardados en este navegador.'}</p></div></div>
        {loading ? <LoadingScreen message="Cargando perfil…" variant="section" /> : <><ProfileFields profile={profile} emailReadOnly={relationalProfile} onChange={(changes) => { setProfile((current) => ({ ...current, ...changes })); clearValidationError() }} />
        <p className="medical-note compact">Las etiquetas dietéticas son informativas y no garantizan ausencia de contaminación cruzada.</p></>}
        <div role="status">{savedProfile === profile && !reloadRequired && !saving && <p className="form-message success">Perfil guardado.</p>}</div>
        <div className="profile-save-row">
          {reloadRequired && <button className="button button-quiet" disabled={loading} onClick={() => { setLoading(true); setLoadAttempt((attempt) => attempt + 1) }} type="button">Recargar perfil</button>}
          <button className="button button-primary" disabled={loading || saving || reloadRequired} type="submit"><Save size={17} /> {saving ? 'Guardando…' : 'Guardar perfil'}</button>
        </div>
      </form>
      <aside className="profile-summary surface" aria-label="Resumen de perfil">
        <p className="eyebrow">TU PERFIL</p><h2>{profile.name || 'Tu cocina'}</h2>
        <p>Usamos esta información para mostrar referencias y recetas compatibles.</p>
        <dl>
          <div><dt>Objetivo</dt><dd>{profile.goal === 'lose' ? 'Perder peso' : profile.goal === 'gain' ? 'Ganar peso' : profile.goal === 'gain-muscle' ? 'Ganar masa muscular' : profile.goal === 'maintain' ? 'Mantener peso' : 'Sin definir'}</dd></div>
          <div><dt>Medidas</dt><dd>{profile.weightKg && profile.heightCm ? `${profile.weightKg} kg · ${profile.heightCm} cm` : 'Sin datos'}</dd></div>
          <div><dt>Preferencias</dt><dd>{profile.preferences?.length ? `${profile.preferences.length} seleccionadas` : 'Sin definir'}</dd></div>
        </dl>
        {age !== undefined && <p className="summary-detail">Edad calculada: <strong>{age} años</strong></p>}
        {estimate && <EnergySummary estimate={estimate} />}
        {relationalProfile && profile.nutritionConfig === null && <p className="medical-note compact">Estimación nutricional no disponible: todavía no hay una configuración publicada vigente.</p>}
        <p className="medical-note compact">Las referencias son estimativas y no reemplazan indicaciones profesionales.</p>
      </aside>
    </div>
  </div>
}

