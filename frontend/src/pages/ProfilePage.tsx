import { Check, PencilLine, Save, LogOut } from 'lucide-react'
import { type FormEvent, useState } from 'react'
import { Link } from 'react-router-dom'
import { endSession } from '../features/auth/data/localAuthStore'
import { readLocalProfile, saveLocalProfile } from '../features/profile/data/localProfileStore'
import { calculateAge, estimateForProfile, profileIsComplete, type ProfileDraft } from '../features/profile/domain/profile'
import { EnergySummary } from '../features/profile/ui/EnergySummary'
import { ProfileFields } from '../features/profile/ui/ProfileFields'
import { profileHeaderActions } from '../features/profile/ui/profileHeaderActions'

export function ProfilePage() {
  const [profile, setProfile] = useState<ProfileDraft>(() => readLocalProfile())
  const [saved, setSaved] = useState(false)
  const [error, setError] = useState('')
  const age = profile.birthDate ? calculateAge(profile.birthDate) : undefined
  const estimate = estimateForProfile(profile)

  function save(event: FormEvent<HTMLFormElement>) {
    event.preventDefault()
    if (!profileIsComplete(profile) || age === undefined || age < 18 || age > 100) {
      setError('Completá los datos requeridos con valores válidos antes de guardar el perfil.')
      setSaved(false)
      return
    }
    try { saveLocalProfile(profile); setError(''); setSaved(true) }
    catch { setError('No se pudo guardar el perfil en este navegador.'); setSaved(false) }
  }

  return <div className="page profile-page">
    <header className="page-heading">
      <div><p className="eyebrow">CONFIGURACIÓN PERSONAL</p><h1>Mi perfil y preferencias</h1><p className="page-lead">Actualizá tus datos para que CocinAPP pueda priorizar recetas más útiles para vos.</p></div>
      <div className="profile-head-actions" aria-label="Acciones de perfil">
        {profileHeaderActions.map((action) => action.id === 'recipes'
          ? <Link className="button button-quiet" key={action.id} to={action.href}><PencilLine aria-hidden="true" size={17} /> {action.label}</Link>
          : <button className="button button-signout" key={action.id} onClick={endSession} type="button"><LogOut aria-hidden="true" size={17} /> {action.label}</button>)}
      </div>
    </header>
    <div className="profile-layout">
      <form className="profile-form surface" onSubmit={save}>
        <div className="section-heading"><div><h2>Datos y objetivos</h2><p>Guardados solo en este navegador durante esta etapa.</p></div></div>
        <ProfileFields profile={profile} showEmail onChange={(changes) => { setProfile({ ...profile, ...changes }); setSaved(false); setError('') }} />
        {error && <p className="form-message error" role="alert">{error}</p>}
        <div className="profile-save-row">{saved && <span className="saved-state" role="status"><Check size={17} /> Perfil guardado</span>}<button className="button button-primary" type="submit"><Save size={17} /> Guardar perfil</button></div>
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

