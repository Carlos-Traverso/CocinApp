import { PencilLine, Save, LogOut } from 'lucide-react'
import { type FormEvent, useEffect, useState } from 'react'
import { Link } from 'react-router-dom'
import { authRepository } from '../features/auth/data/AuthRepository'
import { profileRepository } from '../features/profile/data/ProfileRepository'
import { calculateAge, estimateForProfile, profileIsComplete, type ProfileDraft } from '../features/profile/domain/profile'
import { EnergySummary } from '../features/profile/ui/EnergySummary'
import { ProfileFields } from '../features/profile/ui/ProfileFields'
import { profileHeaderActions } from '../features/profile/ui/profileHeaderActions'
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
  const [loggingOut, setLoggingOut] = useState(false)
  const { notify } = useNotifications()
  useEffect(() => { void profileRepository.getProfile().then(setProfile).catch(() => { void notify({ type: 'error', title: 'No se pudo cargar el perfil', message: 'No se pudo cargar el perfil.' }) }).finally(() => setLoading(false)) }, [notify])
  const age = profile.birthDate ? calculateAge(profile.birthDate) : undefined
  const estimate = estimateForProfile(profile)

  async function logout() {
    setLoggingOut(true)
    try { await authRepository.logout() }
    catch { await notify({ type: 'error', title: 'No se pudo cerrar la sesión', message: 'Intentá de nuevo.' }) }
    finally { setLoggingOut(false) }
  }

  async function save(event: FormEvent<HTMLFormElement>) {
    event.preventDefault()
    const form = event.currentTarget
    if (!form.checkValidity()) {
      const invalidField = form.querySelector<HTMLInputElement | HTMLSelectElement>(':invalid')
      invalidField?.focus()
      await notify({ type: 'warning', title: 'Revisá los datos del perfil', message: invalidField ? profileFieldValidationMessage(invalidField) : 'Revisá los datos ingresados.' })
      return
    }
    if (!profileIsComplete(profile) || age === undefined || age < 18 || age > 100) {
      form.querySelector<HTMLInputElement>('[name="birthDate"]')?.focus()
      await notify({ type: 'warning', title: 'Revisá los datos del perfil', message: 'Completá los datos requeridos con valores válidos antes de guardar el perfil.' })
      return
    }
    setSaving(true)
    try { await profileRepository.saveProfile(profile); await notify({ type: 'success', title: 'Perfil guardado', message: 'Tus datos y preferencias se guardaron correctamente.' }) }
    catch { await notify({ type: 'error', title: 'No se pudo guardar el perfil', message: 'Revisá el espacio disponible del navegador e intentá de nuevo.' }) }
    finally { setSaving(false) }
  }

  return <div className="page profile-page">
    <header className="page-heading">
      <div><p className="eyebrow">CONFIGURACIÓN PERSONAL</p><h1>Mi perfil y preferencias</h1><p className="page-lead">Actualizá tus datos para que CocinAPP pueda priorizar recetas más útiles para vos.</p></div>
      <div className="profile-head-actions" aria-label="Acciones de perfil">
        {profileHeaderActions.map((action) => action.id === 'recipes'
          ? <Link className="button button-quiet" key={action.id} to={action.href}><PencilLine aria-hidden="true" size={17} /> {action.label}</Link>
          : <button className="button button-signout" disabled={loggingOut} key={action.id} onClick={() => void logout()} type="button"><LogOut aria-hidden="true" size={17} /> {loggingOut ? 'Cerrando…' : action.label}</button>)}
      </div>
    </header>
    <div className="profile-layout">
      <form className="profile-form surface" noValidate onSubmit={save}>
        <div className="section-heading"><div><h2>Datos y objetivos</h2><p>Guardados solo en este navegador durante esta etapa.</p></div></div>
        {loading ? <p role="status">Cargando perfil…</p> : <><ProfileFields profile={profile} showEmail onChange={(changes) => { setProfile({ ...profile, ...changes }) }} />
        <p className="medical-note compact">Las etiquetas dietéticas son informativas y no garantizan ausencia de contaminación cruzada.</p></>}
        <div className="profile-save-row"><button className="button button-primary" disabled={loading || saving} type="submit"><Save size={17} /> {saving ? 'Guardando…' : 'Guardar perfil'}</button></div>
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
        <p className="medical-note compact">Las referencias son estimativas y no reemplazan indicaciones profesionales.</p>
      </aside>
    </div>
  </div>
}

