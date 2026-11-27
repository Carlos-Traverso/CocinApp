import { ArrowLeft, ArrowRight, Check, ChevronDown, Droplets, Dumbbell, Info, Leaf, NutOff, Scale, Sprout, Target, TrendingDown, TrendingUp, UserRound, Utensils, WheatOff } from 'lucide-react'
import { type FormEvent, useEffect, useRef, useState } from 'react'
import { BrandLogo } from '../components/BrandLogo'
import { FilterSelect } from '../components/FilterSelect'
import { calculateAge, type ActivityLevel, type DietaryPreference, type Goal, type MetabolicSex, type ProfileDraft } from '../features/profile/domain/profile'
import './OnboardingPage.css'

const steps = [
  { label: 'Tus datos', icon: UserRound, title: 'Personalizá tu cocina', description: 'Confirmá tu nombre para empezar.' },
  { label: 'Objetivo', icon: Target, title: '¿Cuál es tu objetivo?', description: 'Elegí el objetivo que querés guardar en tu perfil.' },
  { label: 'Preferencias', icon: Utensils, title: '¿Qué preferís comer?', description: 'Podés elegir varias opciones. Las vamos a usar para filtrar el recetario.' },
]

const goals = [
  { value: 'lose', label: 'Perder peso', icon: TrendingDown },
  { value: 'maintain', label: 'Mantener mi peso', icon: Scale },
  { value: 'gain', label: 'Ganar peso', icon: TrendingUp },
  { value: 'gain-muscle', label: 'Aumentar masa muscular', icon: Dumbbell },
] as const satisfies ReadonlyArray<{ value: Goal; label: string; icon: typeof Scale }>

const preferences = [
  { value: 'gluten-free', label: 'Sin TACC', icon: WheatOff },
  { value: 'vegetarian', label: 'Vegetariano', icon: Leaf },
  { value: 'vegan', label: 'Vegano', icon: Sprout },
  { value: 'lactose-free', label: 'Sin lactosa', icon: Droplets },
  { value: 'nut-free', label: 'Sin frutos secos', icon: NutOff },
] as const satisfies ReadonlyArray<{ value: DietaryPreference; label: string; icon: typeof Scale }>

const metabolicSexOptions = [
  { value: '', label: 'Seleccionar' },
  { value: 'female', label: 'Femenino' },
  { value: 'male', label: 'Masculino' },
]

const activityOptions = [
  { value: '', label: 'Seleccionar' },
  { value: 'sedentary', label: 'Sedentaria' },
  { value: 'light', label: 'Ligera' },
  { value: 'moderate', label: 'Moderada' },
  { value: 'active', label: 'Alta' },
  { value: 'very-active', label: 'Muy alta' },
]

interface OnboardingPageProps {
  initialProfile: ProfileDraft
  onComplete(profile: ProfileDraft): Promise<void>
}

export function OnboardingPage({ initialProfile, onComplete }: OnboardingPageProps) {
  const [step, setStep] = useState(0)
  const [profile, setProfile] = useState(initialProfile)
  const [error, setError] = useState('')
  const [saving, setSaving] = useState(false)
  const [detailsExpanded, setDetailsExpanded] = useState(true)
  const [invalidBirthDate, setInvalidBirthDate] = useState(false)
  const heading = useRef<HTMLHeadingElement>(null)
  const formContent = useRef<HTMLDivElement>(null)
  const currentStep = steps[step]
  const isLastStep = step === steps.length - 1

  useEffect(() => {
    heading.current?.focus({ preventScroll: true })
    formContent.current?.scrollTo(0, 0)
    window.scrollTo(0, 0)
  }, [step])

  function updateProfile(changes: Partial<ProfileDraft>) {
    setError('')
    setProfile((current) => ({ ...current, ...changes }))
  }

  function togglePreference(preference: DietaryPreference) {
    const selected = profile.preferences ?? []
    updateProfile({ preferences: selected.includes(preference)
      ? selected.filter((value) => value !== preference)
      : [...selected, preference] })
  }

  function goBack() {
    setError('')
    setStep(step - 1)
  }

  async function submit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault()
    if (saving) return
    setError('')

    if (step === 0) {
      const name = profile.name?.trim()
      const age = profile.birthDate ? calculateAge(profile.birthDate) : undefined
      if (!name) {
        setError('Ingresá tu nombre.')
        event.currentTarget.querySelector<HTMLInputElement>('[name="name"]')?.focus()
        return
      }
      if (profile.birthDate && (age === undefined || age < 18 || age > 100)) {
        const field = event.currentTarget.querySelector<HTMLInputElement>('[name="birthDate"]')
        setDetailsExpanded(true)
        setInvalidBirthDate(true)
        requestAnimationFrame(() => field?.focus())
        return
      }
      updateProfile({ name })
    }

    if (!isLastStep) {
      setStep(step + 1)
      return
    }

    setSaving(true)
    try {
      await onComplete({ ...profile, preferences: profile.preferences ?? [] })
    } catch {
      setError('No se pudo confirmar el guardado de tu perfil. Volvé a intentarlo.')
    } finally {
      setSaving(false)
    }
  }

  return <div className="onboarding-page">
    <header className="onboarding-header">
      <div className="onboarding-header-content">
        <BrandLogo />
      </div>
    </header>

    <main className="onboarding-main">
      <div className="onboarding-card">
        <div aria-hidden="true" className="onboarding-photo">
          <picture>
            <source height="387" media="(max-width: 760px)" srcSet="/assets/branding/cocinapp-onboarding-mobile.webp" width="1160" />
            <img alt="" fetchPriority="high" height="1350" src="/assets/branding/cocinapp-onboarding.webp" width="900" />
          </picture>
        </div>
        <form className="onboarding-form" onSubmit={(event) => void submit(event)}>
          <div className="onboarding-form-content" ref={formContent}>
            <ol aria-label={`Configuración inicial, paso ${step + 1} de ${steps.length}`} className="onboarding-steps" role="list">
              {steps.map(({ label, icon: Icon }, index) => <li aria-current={index === step ? 'step' : undefined} className={index < step ? 'onboarding-step-done' : undefined} key={label}>
                <span className="onboarding-step-icon" aria-hidden="true">{index < step ? <Check size={15} /> : <Icon size={15} />}</span>
                <span>{label}</span>
              </li>)}
            </ol>

            <div className="onboarding-heading">
              <h1 ref={heading} tabIndex={-1}>{currentStep.title}</h1>
              <p>{currentStep.description}</p>
            </div>

            {step === 0 && <fieldset aria-label="Datos personales" className="onboarding-fieldset" disabled={saving}>
              <label className="onboarding-field">
                <span>Nombre</span>
                <input autoComplete="name" maxLength={60} name="name" onChange={(event) => updateProfile({ name: event.currentTarget.value })} required value={profile.name ?? ''} />
              </label>
              <div className="onboarding-details" onInvalid={(event) => {
                const field = event.target
                if (!(field instanceof HTMLInputElement) || field.getClientRects().length) return
                event.preventDefault()
                setDetailsExpanded(true)
                requestAnimationFrame(() => field.reportValidity())
              }}>
                <p className="onboarding-details-title"><strong>Datos para tu estimación</strong> <span>Opcionales</span></p>
                <button aria-controls="onboarding-estimate-fields" aria-expanded={detailsExpanded} className="onboarding-details-toggle" onClick={() => setDetailsExpanded((expanded) => !expanded)} type="button">
                  <span>
                    <strong>Datos opcionales</strong>
                    <span>Para estimar tu gasto energético.</span>
                  </span>
                  <ChevronDown aria-hidden="true" size={21} />
                </button>
                <div className="onboarding-fields" data-expanded={detailsExpanded} id="onboarding-estimate-fields" role="group" aria-label="Datos opcionales para estimar tu gasto energético">
                  <label className="onboarding-field onboarding-birth-date">
                    <span>Fecha de nacimiento</span>
                    <input aria-describedby={invalidBirthDate ? 'onboarding-birth-date-error' : undefined} aria-invalid={invalidBirthDate || undefined} autoComplete="bday" name="birthDate" onChange={(event) => {
                      setInvalidBirthDate(false)
                      updateProfile({ birthDate: event.currentTarget.value || undefined })
                    }} type="date" value={profile.birthDate ?? ''} />
                    {invalidBirthDate && <small className="onboarding-field-error" id="onboarding-birth-date-error" role="alert">Ingresá una fecha de nacimiento que corresponda a una edad entre 18 y 100 años.</small>}
                  </label>
                  <div className="onboarding-field onboarding-metabolic-sex">
                    <FilterSelect label="Sexo para el cálculo" name="metabolicSex" onChange={(value) => updateProfile({ metabolicSex: (value || undefined) as MetabolicSex | undefined })} options={metabolicSexOptions} value={profile.metabolicSex ?? ''} />
                  </div>
                  <label className="onboarding-field">
                    <span>Peso (kg)</span>
                    <input inputMode="decimal" max={300} min={30} name="weightKg" onChange={(event) => updateProfile({ weightKg: event.currentTarget.value === '' ? undefined : event.currentTarget.valueAsNumber })} step="0.1" type="number" value={profile.weightKg ?? ''} />
                  </label>
                  <label className="onboarding-field">
                    <span>Altura (cm)</span>
                    <input inputMode="decimal" max={250} min={100} name="heightCm" onChange={(event) => updateProfile({ heightCm: event.currentTarget.value === '' ? undefined : event.currentTarget.valueAsNumber })} step="0.1" type="number" value={profile.heightCm ?? ''} />
                  </label>
                  <div className="onboarding-field onboarding-activity">
                    <FilterSelect label="Actividad física habitual" name="activityLevel" onChange={(value) => updateProfile({ activityLevel: (value || undefined) as ActivityLevel | undefined })} options={activityOptions} value={profile.activityLevel ?? ''} />
                  </div>
                </div>
              </div>
            </fieldset>}

            {step === 1 && <fieldset aria-label="Objetivo principal" className="onboarding-fieldset onboarding-options onboarding-goals" disabled={saving}>
              {goals.map(({ value, label, icon: Icon }) => <label className="onboarding-choice" key={value}>
                <input checked={profile.goal === value} name="goal" onChange={() => updateProfile({ goal: value })} required type="radio" value={value} />
                <span className="onboarding-choice-body" data-choice={value}>
                  <span className="onboarding-choice-icon"><Icon aria-hidden="true" size={24} /></span>
                  <span>{label}</span>
                  <Check aria-hidden="true" className="onboarding-choice-check" size={17} />
                </span>
              </label>)}
            </fieldset>}

            {isLastStep && <fieldset aria-label="Preferencias alimentarias" className="onboarding-fieldset" disabled={saving}>
              <div className="onboarding-options onboarding-preferences">
                {preferences.map(({ value, label, icon: Icon }) => <label className="onboarding-choice" key={value}>
                  <input checked={profile.preferences?.includes(value) ?? false} name="preferences" onChange={() => togglePreference(value)} type="checkbox" value={value} />
                  <span className="onboarding-choice-body" data-choice={value}>
                    <span className="onboarding-choice-icon"><Icon aria-hidden="true" size={23} /></span>
                    <span>{label}</span>
                    <Check aria-hidden="true" className="onboarding-choice-check" size={17} />
                  </span>
                </label>)}
                <button aria-pressed={profile.preferences?.length === 0} className="onboarding-choice-body onboarding-no-preferences" onClick={() => updateProfile({ preferences: [] })} type="button">
                  <span className="onboarding-choice-icon"><Utensils aria-hidden="true" size={22} /></span>
                  <span>Sin restricciones</span>
                  <Check aria-hidden="true" className="onboarding-choice-check" size={17} />
                </button>
              </div>
              <p className="onboarding-diet-note"><Info aria-hidden="true" size={17} /> Si tenés alergias, revisá los ingredientes y las advertencias sobre trazas de cada producto.</p>
            </fieldset>}

            {error && <p className="form-message error onboarding-error" role="alert">{error}</p>}
          </div>
          <div className="onboarding-actions">
            {step > 0 && <button className="button onboarding-back" disabled={saving} onClick={goBack} type="button">
              <ArrowLeft aria-hidden="true" size={17} /> Volver
            </button>}
            <button className="button button-primary" disabled={saving} type="submit">
              {saving ? 'Guardando…' : isLastStep ? 'Guardar y entrar' : 'Continuar'} <ArrowRight aria-hidden="true" size={17} />
            </button>
          </div>
        </form>
      </div>
    </main>
  </div>
}
