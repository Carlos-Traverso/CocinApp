import { useState } from 'react'
import { Link, useNavigate } from 'react-router-dom'
import { ArrowRight, Refrigerator, ShieldCheck, Sparkles, UtensilsCrossed } from 'lucide-react'
import { authRepository } from '../features/auth/data/AuthRepository'
import { handleTabListKeyDown } from '../components/tabKeyboard'
import { BrandLogo } from '../components/BrandLogo'
import { useNotifications } from '../shared/notifications/NotificationProvider'
import { isSupabaseConfigured } from '../shared/data/supabaseClient'
import { roleHome } from '../features/auth/domain/routeAccess'

type AccessMode = 'login' | 'register'

function validationMessage(field: HTMLInputElement): string {
  if (field.validity.valueMissing) return 'Completá este campo.'
  if (field.validity.typeMismatch) return 'Ingresá un correo electrónico válido.'
  if (field.validity.tooShort) return `La contraseña debe tener al menos ${field.minLength} caracteres.`
  if (field.validity.tooLong) return `El nombre no puede superar ${field.maxLength} caracteres.`
  return 'Revisá el dato ingresado.'
}

export function WelcomePage() {
  const [mode, setMode] = useState<AccessMode>('login')
  const [name, setName] = useState('')
  const [email, setEmail] = useState('')
  const [password, setPassword] = useState('')
  const [busy, setBusy] = useState(false)
  const [validationError, setValidationError] = useState('')
  const [invalidFieldName, setInvalidFieldName] = useState('')
  const { notify } = useNotifications()
  const navigate = useNavigate()

  async function submit(event: React.FormEvent<HTMLFormElement>) {
    event.preventDefault()
    const form = event.currentTarget
    setValidationError('')
    setInvalidFieldName('')
    if (!form.checkValidity()) {
      const invalidField = form.querySelector<HTMLInputElement>(':invalid')
      invalidField?.focus()
      setInvalidFieldName(invalidField?.name ?? '')
      setValidationError(invalidField ? validationMessage(invalidField) : 'Revisá los datos ingresados.')
      return
    }
    setBusy(true)
    try {
      if (mode === 'register') {
        await authRepository.register(name, email, password)
      } else {
        await authRepository.login(email, password)
      }
      const session = await authRepository.session()
      if (session) navigate(roleHome(session.role), { replace: true })
    } catch (cause) {
      await notify({ type: 'error', title: mode === 'register' ? 'No se pudo crear la cuenta' : 'No se pudo iniciar sesión', message: cause instanceof Error ? cause.message : 'No se pudo completar el acceso.' })
    } finally { setBusy(false) }
  }

  return (
    <main className="access-page access-page-login">
      <div aria-hidden="true" className="access-decoration access-decoration-one" />
      <div aria-hidden="true" className="access-decoration access-decoration-two" />
      <header className="access-header">
        <div className="access-login-brand">
          <BrandLogo className="access-primary-logo" />
          <small>COCINA &amp; DESPENSA</small>
        </div>
      </header>
      <div className="access-layout">
        <section className="access-intro" aria-labelledby="access-title">
          <div className="access-kicker">
            <p className="eyebrow">TU COCINA, MÁS ORGANIZADA</p>
            <span>Ahorrá tiempo y dinero cada semana</span>
          </div>
          <h1 id="access-title">Planeá tus comidas y aprovechá lo que ya tenés.</h1>
          <p>Recetas, despensa, menú semanal y compras en un único lugar, pensado para el ritmo de todos los días.</p>
          <div className="access-highlights">
            <div><span className="highlight-icon"><Refrigerator size={20} /></span><span><strong>Despensa clara</strong><small>Stock, vencimientos y faltantes siempre al día sin esfuerzo.</small></span><span aria-hidden="true" className="access-highlight-number">01</span></div>
            <div><span className="highlight-icon warm"><UtensilsCrossed size={20} /></span><span><strong>Recetas óptimas</strong><small>Sugerencias al instante según ingredientes disponibles.</small></span><span aria-hidden="true" className="access-highlight-number">02</span></div>
            <div><span className="highlight-icon mint"><Sparkles size={20} /></span><span><strong>Semana resuelta</strong><small>Menú equilibrado para comprar justo y evitar desperdicios.</small></span><span aria-hidden="true" className="access-highlight-number">03</span></div>
          </div>
          <figure className="access-visual">
            <img alt="Bowl de quinoa con verduras frescas" src="/assets/recipes/quinoa-bowl.webp" />
            <div aria-hidden="true" className="access-visual-chips">
              <span>Tomates cherry</span><span>Zucchini asado</span><span>Palta</span>
            </div>
            <figcaption>
              <strong>Comé rico. Organizate mejor.</strong>
              <span>Todo lo que necesitás para decidir el próximo plato.</span>
            </figcaption>
          </figure>
        </section>
        <section className="access-card" aria-labelledby="access-form-title">
          <p className="eyebrow">{mode === 'register' || isSupabaseConfigured ? 'TU CUENTA DE COCINAPP' : 'CUENTA LOCAL DE DEMOSTRACIÓN'}</p>
          <h2 id="access-form-title">{mode === 'login' ? 'Ingresá a tu cocina' : 'Creá tu cuenta'}</h2>
          <p className="field-help">{mode === 'register' ? 'Completá tus datos para empezar a planificar tus comidas.' : isSupabaseConfigured ? 'Ingresá con tu cuenta de CocinAPP para continuar.' : 'Las cuentas y los permisos se simulan en este navegador. No es autenticación segura.'}</p>
          <div className="tabs access-tabs" role="tablist" aria-label="Tipo de acceso" onKeyDown={(event) => { handleTabListKeyDown(event); if (event.key === 'ArrowLeft' || event.key === 'ArrowRight' || event.key === 'Home' || event.key === 'End') { setValidationError(''); setInvalidFieldName('') } }}>
            <button id="access-tab-login" aria-controls="access-panel" type="button" role="tab" aria-selected={mode === 'login'} tabIndex={mode === 'login' ? 0 : -1} onClick={() => { setMode('login'); setValidationError(''); setInvalidFieldName('') }}>Iniciar sesión</button>
            <button id="access-tab-register" aria-controls="access-panel" type="button" role="tab" aria-selected={mode === 'register'} tabIndex={mode === 'register' ? 0 : -1} onClick={() => { setMode('register'); setValidationError(''); setInvalidFieldName('') }}>Registrarme</button>
          </div>
          <div id="access-panel" aria-labelledby={`access-tab-${mode}`} role="tabpanel" tabIndex={0}>
            <form className="access-form" noValidate onInput={() => { setValidationError(''); setInvalidFieldName('') }} onSubmit={submit}>
            {validationError && <p className="form-message error" id="access-validation-error" role="alert">{validationError}</p>}
            {mode === 'register' && <label className="field"><span>Nombre</span><input aria-describedby={validationError && invalidFieldName === 'name' ? 'access-validation-error' : undefined} autoComplete="name" maxLength={80} name="name" onChange={(event) => setName(event.currentTarget.value)} required value={name} /></label>}
            <label className="field"><span>Correo electrónico</span><input aria-describedby={validationError && invalidFieldName === 'email' ? 'access-validation-error' : undefined} autoComplete="email" name="email" onChange={(event) => setEmail(event.currentTarget.value)} required type="email" value={email} /></label>
            <label className="field"><span>Contraseña</span><input aria-describedby={validationError && invalidFieldName === 'password' ? 'access-validation-error' : undefined} autoComplete={mode === 'register' ? 'new-password' : 'current-password'} minLength={8} name="password" onChange={(event) => setPassword(event.currentTarget.value)} required type="password" value={password} /></label>
            {mode === 'login' && isSupabaseConfigured && <Link className="password-forgot-link" to="/recuperar-contrasena">¿Olvidaste tu contraseña?</Link>}
            <button className="button button-primary button-wide" disabled={busy} type="submit">{busy ? 'Procesando…' : mode === 'login' ? 'Iniciar sesión' : 'Crear cuenta'} <ArrowRight size={15} /></button>
            </form>
          </div>
          {!isSupabaseConfigured && <div className="access-demo">
            <span>Prueba administrativa</span>
            <button className="button button-quiet button-wide" disabled={busy} onClick={async () => { setBusy(true); try { await authRepository.loginAsDemoAdmin() } catch { await notify({ type: 'error', title: 'No se pudo iniciar la sesión', message: 'No se pudo iniciar la sesión de demostración.' }) } finally { setBusy(false) } }} type="button"><ShieldCheck size={18} /> Entrar como ADMIN de demostración</button>
            <small>Los registros creados desde el formulario siempre reciben el rol USER.</small>
          </div>}
          <p className="access-disclaimer">{isSupabaseConfigured ? 'Ingresá con tu correo y contraseña. El acceso de administración depende de los permisos de tu cuenta.' : 'Los datos de la cuenta se guardan localmente en el navegador.'}</p>
        </section>
      </div>
      <footer className="access-footer">
        <span><strong>CocinAPP</strong> · © 2026 — Planificación inteligente de comidas</span>
        <span>{isSupabaseConfigured ? 'Tu cocina, organizada en un solo lugar' : 'Privacidad simulada　·　Términos de demo　·　Ayuda rápida'}</span>
      </footer>
    </main>
  )
}
