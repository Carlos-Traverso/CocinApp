import { useState } from 'react'
import { Refrigerator, Sparkles, UtensilsCrossed, ShieldCheck } from 'lucide-react'
import { authenticateUser, registerAccount, startDemoAdminSession, startUserSession } from '../features/auth/data/localAuthStore'

type AccessMode = 'login' | 'register'

export function WelcomePage() {
  const [mode, setMode] = useState<AccessMode>('login')
  const [name, setName] = useState('')
  const [email, setEmail] = useState('')
  const [password, setPassword] = useState('')
  const [error, setError] = useState('')

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
    <main className="access-page">
      <header className="access-header"><div className="access-wordmark" aria-label="CocinAPP, inicio">Cocin<span>APP</span></div></header>
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
          <p className="eyebrow">CUENTA LOCAL DE DEMOSTRACIÓN</p>
          <h2 id="access-form-title">{mode === 'login' ? 'Ingresá a tu cocina' : 'Creá tu cuenta'}</h2>
          <p className="field-help">Las cuentas y los permisos se simulan en este navegador. No es autenticación segura.</p>
          <div className="tabs access-tabs" role="tablist" aria-label="Tipo de acceso">
            <button type="button" role="tab" aria-selected={mode === 'login'} onClick={() => { setMode('login'); setError('') }}>Iniciar sesión</button>
            <button type="button" role="tab" aria-selected={mode === 'register'} onClick={() => { setMode('register'); setError('') }}>Registrarme</button>
          </div>
          <form className="access-form" onSubmit={submit}>
            {mode === 'register' && <label className="field"><span>Nombre</span><input autoComplete="name" maxLength={80} onChange={(event) => setName(event.currentTarget.value)} required value={name} /></label>}
            <label className="field"><span>Correo electrónico</span><input autoComplete="email" onChange={(event) => setEmail(event.currentTarget.value)} required type="email" value={email} /></label>
            <label className="field"><span>Contraseña</span><input autoComplete={mode === 'register' ? 'new-password' : 'current-password'} minLength={8} onChange={(event) => setPassword(event.currentTarget.value)} required type="password" value={password} /></label>
            {error && <p className="form-message error" role="alert">{error}</p>}
            <button className="button button-primary button-wide" type="submit">{mode === 'login' ? 'Iniciar sesión' : 'Crear cuenta'}</button>
          </form>
          <div className="access-demo">
            <span>Prueba administrativa</span>
            <button className="button button-quiet button-wide" onClick={startDemoAdminSession} type="button"><ShieldCheck size={18} /> Entrar como ADMIN de demostración</button>
            <small>Los registros creados desde el formulario siempre reciben el rol USER.</small>
          </div>
          <p className="access-disclaimer">Los datos de la cuenta se guardan localmente en el navegador.</p>
        </section>
      </div>
    </main>
  )
}
