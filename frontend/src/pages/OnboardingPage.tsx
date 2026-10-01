import { ArrowLeft, ArrowRight, CircleAlert } from 'lucide-react'
import { type FormEvent, useRef, useState } from 'react'
import { useNavigate } from 'react-router-dom'
import { BrandLogo } from '../components/BrandLogo'
import { readLocalProfile, saveLocalProfile } from '../features/profile/data/localProfileStore'
import { calculateAge, estimateForProfile, profileIsComplete, type ProfileDraft } from '../features/profile/domain/profile'
import { EnergySummary } from '../features/profile/ui/EnergySummary'
import { ProfileFields } from '../features/profile/ui/ProfileFields'

export function OnboardingPage() {
  const navigate = useNavigate()
  const [profile, setProfile] = useState<ProfileDraft>(() => readLocalProfile())
  const [error, setError] = useState('')
  const formRef = useRef<HTMLFormElement>(null)

  const age = profile.birthDate ? calculateAge(profile.birthDate) : undefined
  const estimate = estimateForProfile(profile)

  function saveAndContinue(event: FormEvent<HTMLFormElement>) {
    event.preventDefault()
    if (!profileIsComplete(profile) || age === undefined || age < 18 || age > 100) {
      setError('Completá los datos requeridos. La configuración inicial está orientada a personas adultas.')
      formRef.current?.querySelector<HTMLInputElement>('[name="birthDate"]')?.focus()
      return
    }
    try { saveLocalProfile(profile); navigate('/profile') }
    catch { setError('No se pudo guardar el perfil en este navegador.') }
  }

  return <main className="setup-page">
    <header className="setup-header"><a aria-label="CocinAPP, inicio" className="access-wordmark" href="/"><BrandLogo /></a><span>Configuración inicial</span></header>
    <section className="setup-card" aria-labelledby="setup-title">
      <div className="setup-progress"><span>Configuración inicial</span><strong>Perfil y preferencias</strong><div><i /></div></div>
      <p className="eyebrow">PRIMEROS PASOS</p>
      <h1 id="setup-title">Organicemos tu perfil</h1>
      <p className="setup-lead">Estos datos permiten mostrar una referencia de energía y priorizar recetas compatibles. Podés modificarlos cuando quieras.</p>
      <form onSubmit={saveAndContinue} ref={formRef}>
        <ProfileFields profile={profile} onChange={(changes) => { setProfile({ ...profile, ...changes }); setError('') }} />
        {age !== undefined && <p className="calculated-age">Edad calculada: <strong>{age} años</strong></p>}
        {estimate && <EnergySummary estimate={estimate} />}
        <p className="medical-note"><CircleAlert size={17} /> Esta estimación es informativa; no reemplaza el asesoramiento de un profesional de nutrición.</p>
        {error && <p className="form-message error" role="alert">{error}</p>}
        <div className="setup-actions"><button className="button button-quiet" onClick={() => navigate('/')} type="button"><ArrowLeft size={17} /> Volver</button><button className="button button-primary" type="submit">Guardar y continuar <ArrowRight size={17} /></button></div>
      </form>
    </section>
  </main>
}
