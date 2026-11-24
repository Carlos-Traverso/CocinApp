import type { ChangeEvent } from 'react'
import { FilterSelect } from '../../../components/FilterSelect'
import type {
  ActivityLevel,
  DietaryPreference,
  Goal,
  MetabolicSex,
  ProfileDraft,
} from '../domain/profile'

interface ProfileFieldsProps {
  profile: ProfileDraft
  onChange: (changes: Partial<ProfileDraft>) => void
  emailReadOnly?: boolean
}

const preferences = [
  { value: 'gluten-free', label: 'Sin TACC' },
  { value: 'vegetarian', label: 'Vegetariano' },
  { value: 'vegan', label: 'Vegano' },
  { value: 'lactose-free', label: 'Sin lactosa' },
  { value: 'nut-free', label: 'Sin frutos secos' },
] as const satisfies ReadonlyArray<{ value: DietaryPreference; label: string }>

function readNumber(event: ChangeEvent<HTMLInputElement>): number | undefined {
  return event.currentTarget.value === '' ? undefined : event.currentTarget.valueAsNumber
}

export function ProfileFields({ profile, onChange, emailReadOnly = false }: ProfileFieldsProps) {
  function togglePreference(preference: DietaryPreference) {
    const selected = profile.preferences ?? []
    onChange({
      preferences: selected.includes(preference)
        ? selected.filter((item) => item !== preference)
        : [...selected, preference],
    })
  }

  return <>
    <div className="form-grid two-columns">
      <label className="field">
        <span>Nombre</span>
        <input
          name="name"
          value={profile.name ?? ''}
          onChange={(event) => onChange({ name: event.currentTarget.value })}
          autoComplete="name"
          maxLength={60}
          required
        />
      </label>
      <label className="field">
        <span>Correo electrónico</span>
        <input
          name="email"
          value={profile.email ?? ''}
          onChange={(event) => onChange({ email: event.currentTarget.value })}
          autoComplete="email"
          inputMode="email"
          readOnly={emailReadOnly}
          type="email"
        />
        {emailReadOnly && <small className="field-help">Correo de inicio de sesión.</small>}
      </label>
      <label className="field">
        <span>Fecha de nacimiento</span>
        <input
          name="birthDate"
          value={profile.birthDate ?? ''}
          onChange={(event) => onChange({ birthDate: event.currentTarget.value })}
          type="date"
          required
        />
      </label>
      <label className="field">
        <span>Peso actual (kg)</span>
        <input
          name="weightKg"
          value={profile.weightKg ?? ''}
          onChange={(event) => onChange({ weightKg: readNumber(event) })}
          inputMode="decimal"
          max="300"
          min="30"
          step="0.1"
          type="number"
          required
        />
      </label>
      <label className="field">
        <span>Altura (cm)</span>
        <input
          name="heightCm"
          value={profile.heightCm ?? ''}
          onChange={(event) => onChange({ heightCm: readNumber(event) })}
          inputMode="decimal"
          max="250"
          min="100"
          step="0.1"
          type="number"
          required
        />
      </label>
      <FilterSelect label="Sexo para el cálculo metabólico" name="metabolicSex" onChange={(value) => onChange({ metabolicSex: value as MetabolicSex })} options={[{ value: '', label: 'Seleccionar' }, { value: 'female', label: 'Femenino' }, { value: 'male', label: 'Masculino' }]} required value={profile.metabolicSex ?? ''} />
      <FilterSelect label="Actividad habitual" name="activityLevel" onChange={(value) => onChange({ activityLevel: value as ActivityLevel })} options={[{ value: '', label: 'Seleccionar' }, { value: 'sedentary', label: 'Sedentaria' }, { value: 'light', label: 'Ligera' }, { value: 'moderate', label: 'Moderada' }, { value: 'active', label: 'Alta' }, { value: 'very-active', label: 'Muy alta' }]} required value={profile.activityLevel ?? ''} />
    </div>
    <fieldset className="choice-group">
      <legend>Objetivo principal</legend>
      <div className="choice-grid four-columns">
        {([
          ['lose', 'Perder peso'],
          ['maintain', 'Mantener peso'],
          ['gain', 'Ganar peso'],
          ['gain-muscle', 'Ganar masa muscular'],
        ] as const satisfies ReadonlyArray<readonly [Goal, string]>).map(([value, label]) => <label className="choice-card" key={value}>
          <input
            checked={profile.goal === value}
            name="goal"
            onChange={() => onChange({ goal: value })}
            required={value === 'lose'}
            type="radio"
          />
          <span>{label}</span>
        </label>)}
      </div>
    </fieldset>
    <fieldset className="choice-group">
      <legend>Preferencias y restricciones</legend>
      <p className="field-help">Las etiquetas orientan las recetas. Revisá siempre el envase si tenés alergias o una indicación profesional.</p>
      <div className="choice-grid preference-grid">
        {preferences.map(({ value, label }) => <label className="choice-card checkbox-card" key={value}>
          <input
            checked={(profile.preferences ?? []).includes(value)}
            onChange={() => togglePreference(value)}
            type="checkbox"
          />
          <span>{label}</span>
        </label>)}
      </div>
    </fieldset>
  </>
}
