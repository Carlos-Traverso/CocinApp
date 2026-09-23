import { Eye, EyeOff, Refrigerator, Sparkles, UtensilsCrossed } from 'lucide-react'
import { type FormEvent, type KeyboardEvent, useState } from 'react'
import { Link, useNavigate } from 'react-router-dom'
import { readLocalProfile, saveLocalProfile } from '../features/profile/data/localProfileStore'

type AccessMode = 'login' | 'register'

export function WelcomePage() {
  const navigate = useNavigate()
  const [mode, setMode] = useState<AccessMode>('login')
  const [showPassword, setShowPassword] = useState(false)
  const [error, setError] = useState('')

  function changeMode(nextMode: AccessMode) {
    setMode(nextMode)
    setError('')
  }

  function handleTabKeyDown(event: KeyboardEvent<HTMLButtonElement>) {
    const modes: AccessMode[] = ['login', 'register']
    const currentIndex = modes.indexOf(mode)
    const direction = event.key === 'ArrowRight' || event.key === 'ArrowDown' ? 1 : event.key === 'ArrowLeft' || event.key === 'ArrowUp' ? -1 : 0
    const nextMode = event.key === 'Home' ? 'login' : event.key === 'End' ? 'register' : direction ? modes[(currentIndex + direction + modes.length) % modes.length] : undefined

    if (!nextMode) return
    event.preventDefault()
    changeMode(nextMode)
    document.getElementById(`access-tab-${nextMode}`)?.focus()
  }

  function submit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault()
    const data = new FormData(event.currentTarget)
    const email = String(data.get('email') ?? '').trim()
    const password = String(data.get('password') ?? '')
    const name = String(data.get('name') ?? '').trim()

    if (!email.includes('@') || password.length < 8) {
      setError('Ingresá un correo válido y una contraseña de al menos 8 caracteres.')
      return
    }
    if (mode === 'register' && (!name || password !== String(data.get('confirmPassword') ?? ''))) {
      setError('Revisá tu nombre y que ambas contraseñas coincidan.')
      return
    }

    try {
      const previous = readLocalProfile()
      saveLocalProfile({ ...previous, email, ...(name ? { name } : {}) })
      navigate(mode === 'register' ? '/onboarding' : '/panel')
    } catch { setError('No se pudo guardar el acceso en este navegador.') }
  }

  return <main className="access-page">
    <header className="access-header">
      <Link className="access-wordmark" to="/" aria-label="CocinAPP, inicio">Cocin<span>APP</span></Link>
    </header>
    <div className="access-layout">
      <section className="access-intro" aria-labelledby="access-title">
        <p className="eyebrow">TU COCINA, MÁS ORGANIZADA</p>
        <h1 id="access-title">Planeá tus comidas y aprovechá lo que ya tenés.</h1>
        <p>Recetas, despensa, menú semanal y compras en un único lugar, pensado para el ritmo de todos los días.</p>
        <div className="access-highlights">
          <div><span className="highlight-icon"><Refrigerator size={20} /></span><span><strong>Despensa clara</strong><small>Stock, vencimientos y faltantes.</small></span></div>
          <div><span className="highlight-icon warm"><UtensilsCrossed size={20} /></span><span><strong>Recetas útiles</strong><small>Elegí según tiempo y preferencias.</small></span></div>
          <div><span className="highlight-icon mint"><Sparkles size={20} /></span><span><strong>Semana resuelta</strong><small>Planificá antes de hacer las compras.</small></span></div>
        </div>
      </section>
      <section className="access-card" aria-labelledby="access-form-title">
        <div className="access-tabs" role="tablist" aria-label="Tipo de acceso">
          <button aria-controls="access-panel" aria-selected={mode === 'login'} id="access-tab-login" onClick={() => changeMode('login')} onKeyDown={handleTabKeyDown} role="tab" tabIndex={mode === 'login' ? 0 : -1} type="button">Iniciar sesión</button>
          <button aria-controls="access-panel" aria-selected={mode === 'register'} id="access-tab-register" onClick={() => changeMode('register')} onKeyDown={handleTabKeyDown} role="tab" tabIndex={mode === 'register' ? 0 : -1} type="button">Registrarse</button>
        </div>
        <div aria-labelledby={`access-tab-${mode}`} id="access-panel" role="tabpanel">
          <p className="eyebrow">{mode === 'login' ? 'QUÉ BUENO VERTE' : 'EMPECEMOS'}</p>
          <h2 id="access-form-title">{mode === 'login' ? 'Ingresá a tu cocina' : 'Creá tu espacio personal'}</h2>
          <p className="field-help">{mode === 'login' ? 'Usá datos de ejemplo para recorrer la interfaz.' : 'Vamos a usar estos datos solo en este navegador.'}</p>
        </div>
        <form className="access-form" onSubmit={submit} noValidate>
          {mode === 'register' && <label className="field"><span>Nombre</span><input autoComplete="name" name="name" required /></label>}
          <label className="field"><span>Correo electrónico</span><input autoComplete="email" inputMode="email" name="email" type="email" required /></label>
          <label className="field">
            <span>Contraseña</span>
            <span className="password-field"><input autoComplete={mode === 'login' ? 'current-password' : 'new-password'} minLength={8} name="password" type={showPassword ? 'text' : 'password'} required /><button aria-label={showPassword ? 'Ocultar contraseña' : 'Mostrar contraseña'} onClick={() => setShowPassword(!showPassword)} type="button">{showPassword ? <EyeOff size={18} /> : <Eye size={18} />}</button></span>
          </label>
          {mode === 'register' && <label className="field"><span>Confirmar contraseña</span><input autoComplete="new-password" minLength={8} name="confirmPassword" type={showPassword ? 'text' : 'password'} required /></label>}
          {error && <p className="form-message error" role="alert">{error}</p>}
          <button className="button button-primary button-wide" type="submit">{mode === 'login' ? 'Iniciar sesión' : 'Continuar con mi perfil'}</button>
        </form>
        <p className="access-disclaimer">Esta es una simulación de frontend. No se crean cuentas ni se guardan contraseñas.</p>
      </section>
    </div>
  </main>
}
