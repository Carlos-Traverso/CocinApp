import { useState } from 'react'
import { ArrowRight, Refrigerator, ShieldCheck, Sparkles, UtensilsCrossed } from 'lucide-react'
import { authenticateUser, registerAccount, startDemoAdminSession, startUserSession } from '../features/auth/data/localAuthStore'
import { handleTabListKeyDown } from '../components/tabKeyboard'
import { BrandLogo } from '../components/BrandLogo'

type AccessMode = 'login' | 'register'

export function WelcomePage() {
  const [mode, setMode] = useState<AccessMode>('login')
  const [name, setName] = useState('')
  const [email, setEmail] = useState('')
  const [password, setPassword] = useState('')
  const [error, setError] = useState('')
  const errorField = error.includes('nombre')
    ? 'name'
    : error.includes('correo') || error.includes('cuenta')
      ? 'email'
      : error.includes('contraseña')
        ? 'password'
        : null

  function submit(event: React.FormEvent<HTMLFormElement>) {
    event.preventDefault()
    setError('')
    try {
      if (mode === 'register') {
        const account = registerAccount(name, email, password)
        startUserSession(account)
      } else {
        startUserSession(authenticateUser(email, password))
      }
    } catch (cause) {
      setError(cause instanceof Error ? cause.message : 'No se pudo completar el acceso.')
    }
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
          <p className="eyebrow">{mode === 'register' ? 'TU CUENTA DE COCINAPP' : 'CUENTA LOCAL DE DEMOSTRACIÓN'}</p>
          <h2 id="access-form-title">{mode === 'login' ? 'Ingresá a tu cocina' : 'Creá tu cuenta'}</h2>
          <p className="field-help">{mode === 'register' ? 'Completá tus datos para empezar a planificar tus comidas.' : 'Las cuentas y los permisos se simulan en este navegador. No es autenticación segura.'}</p>
          <div className="tabs access-tabs" role="tablist" aria-label="Tipo de acceso" onKeyDown={handleTabListKeyDown}>
            <button id="access-tab-login" aria-controls="access-panel" type="button" role="tab" aria-selected={mode === 'login'} tabIndex={mode === 'login' ? 0 : -1} onClick={() => { setMode('login'); setError('') }}>Iniciar sesión</button>
            <button id="access-tab-register" aria-controls="access-panel" type="button" role="tab" aria-selected={mode === 'register'} tabIndex={mode === 'register' ? 0 : -1} onClick={() => { setMode('register'); setError('') }}>Registrarme</button>
          </div>
          <div id="access-panel" aria-labelledby={`access-tab-${mode}`} role="tabpanel" tabIndex={0}>
            <form className="access-form" onSubmit={submit}>
            {mode === 'register' && <label className="field"><span>Nombre</span><input aria-describedby={errorField === 'name' ? 'access-error' : undefined} aria-invalid={errorField === 'name'} autoComplete="name" maxLength={80} onChange={(event) => setName(event.currentTarget.value)} required value={name} /></label>}
            <label className="field"><span>Correo electrónico</span><input aria-describedby={errorField === 'email' ? 'access-error' : undefined} aria-invalid={errorField === 'email'} autoComplete="email" onChange={(event) => setEmail(event.currentTarget.value)} required type="email" value={email} /></label>
            <label className="field"><span>Contraseña</span><input aria-describedby={errorField === 'password' ? 'access-error' : undefined} aria-invalid={errorField === 'password'} autoComplete={mode === 'register' ? 'new-password' : 'current-password'} minLength={8} onChange={(event) => setPassword(event.currentTarget.value)} required type="password" value={password} /></label>
            {error && <p className="form-message error" id="access-error" role="alert">{error}</p>}
            <button className="button button-primary button-wide" type="submit">{mode === 'login' ? 'Iniciar sesión' : 'Crear cuenta'} <ArrowRight size={15} /></button>
            </form>
          </div>
          <div className="access-demo">
            <span>Prueba administrativa</span>
            <button className="button button-quiet button-wide" onClick={startDemoAdminSession} type="button"><ShieldCheck size={18} /> Entrar como ADMIN de demostración</button>
            <small>Los registros creados desde el formulario siempre reciben el rol USER.</small>
          </div>
          <p className="access-disclaimer">Los datos de la cuenta se guardan localmente en el navegador.</p>
        </section>
      </div>
      <footer className="access-footer">
        <span><strong>CocinAPP</strong> · © 2026 — Planificación inteligente de comidas</span>
        <span>Privacidad simulada　·　Términos de demo　·　Ayuda rápida</span>
      </footer>
    </main>
  )
}
