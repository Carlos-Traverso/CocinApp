import { Refrigerator, Sparkles, UtensilsCrossed, User, ShieldCheck } from 'lucide-react'

import { startSession } from '../features/auth/data/localAuthStore'
import { readLocalProfile, saveLocalProfile } from '../features/profile/data/localProfileStore'

export function WelcomePage() {

  function loginAs(role: 'USER' | 'ADMIN') {
    const email = role === 'ADMIN' ? 'admin@cocinapp.local' : 'user@cocinapp.local'
    const name = role === 'ADMIN' ? 'Administrador' : 'Usuario Demo'
    
    // Ensure profile exists for the app to not force onboarding unless desired
    const previous = readLocalProfile()
    if (!previous.name) {
      saveLocalProfile({ ...previous, email, name })
    }

    startSession(role, email, name)
    // AuthGuards will handle the redirect because the session state changes
  }

  return (
    <main className="access-page">
      <header className="access-header">
        <div className="access-wordmark" aria-label="CocinAPP, inicio">Cocin<span>APP</span></div>
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
          <div id="access-panel">
            <p className="eyebrow">ACCESO DE DEMOSTRACIÓN</p>
            <h2 id="access-form-title">Seleccioná un perfil</h2>
            <p className="field-help">Esta es una versión local sin backend. Seleccioná el rol con el que querés probar la aplicación.</p>
          </div>
          <div className="access-form" style={{ display: 'flex', flexDirection: 'column', gap: '1rem', marginTop: '1.5rem' }}>
            <button 
              className="button button-primary button-wide" 
              onClick={() => loginAs('USER')}
              style={{ display: 'flex', justifyContent: 'center', gap: '0.5rem' }}
            >
              <User size={18} /> Entrar como Usuario
            </button>
            <button 
              className="button button-wide" 
              onClick={() => loginAs('ADMIN')}
              style={{ display: 'flex', justifyContent: 'center', gap: '0.5rem', backgroundColor: '#333', color: 'white' }}
            >
              <ShieldCheck size={18} /> Entrar como Administrador
            </button>
          </div>
          <p className="access-disclaimer">No se requieren contraseñas. Los datos se guardan en el localStorage del navegador.</p>
        </section>
      </div>
    </main>
  )
}

