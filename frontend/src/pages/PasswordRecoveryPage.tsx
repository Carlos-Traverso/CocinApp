import { useEffect, useState, type FormEvent, type ReactNode } from 'react'
import { ArrowLeft, ArrowRight, CheckCircle2, KeyRound, MailCheck } from 'lucide-react'
import { Link, useNavigate } from 'react-router-dom'
import { BrandLogo } from '../components/BrandLogo'
import { hasPasswordRecoveryMarker, supabase } from '../shared/data/supabaseClient'
import { requestPasswordRecovery, saveRecoveredPassword } from '../features/auth/data/passwordRecovery'
import { authRepository } from '../features/auth/data/AuthRepository'
import { roleHome } from '../features/auth/domain/routeAccess'
import { useNotifications } from '../shared/notifications/NotificationProvider'
import './PasswordRecoveryPage.css'

export function RequestPasswordRecoveryPage() {
  const [email, setEmail] = useState('')
  const [busy, setBusy] = useState(false)
  const [sent, setSent] = useState(false)
  const [error, setError] = useState('')

  async function submit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault()
    setError('')
    setBusy(true)
    try {
      await requestPasswordRecovery(email)
      setSent(true)
    } catch (cause) {
      setError(cause instanceof Error ? cause.message : 'No se pudo enviar el correo de recuperación.')
    } finally {
      setBusy(false)
    }
  }

  return <RecoveryLayout>
    <p className="eyebrow">RECUPERAR ACCESO</p>
    {sent ? <>
      <span className="recovery-success-icon"><MailCheck aria-hidden="true" size={24} /></span>
      <h1>Revisá tu correo</h1>
      <p className="field-help">Si existe una cuenta asociada a <strong>{email.trim()}</strong>, vas a recibir un enlace para crear una contraseña nueva. Revisá también la carpeta de spam.</p>
      <Link className="button button-primary button-wide" to="/">Volver al inicio <ArrowRight size={16} /></Link>
    </> : <>
      <h1>¿Olvidaste tu contraseña?</h1>
      <p className="field-help">Ingresá el correo de tu cuenta y te enviaremos un enlace para elegir una contraseña nueva.</p>
      <form className="access-form recovery-form" noValidate onSubmit={(event) => void submit(event)}>
        {error && <p className="form-message error" role="alert">{error}</p>}
        <label className="field"><span>Correo electrónico</span><input autoComplete="email" maxLength={254} onChange={(event) => setEmail(event.currentTarget.value)} required type="email" value={email} /></label>
        <button className="button button-primary button-wide" disabled={busy} type="submit">{busy ? 'Enviando…' : 'Enviar enlace'} <ArrowRight size={16} /></button>
      </form>
      <Link className="recovery-back-link" to="/"><ArrowLeft size={15} /> Volver al inicio de sesión</Link>
    </>}
  </RecoveryLayout>
}

export function ResetPasswordPage() {
  const [recoveryCallbackDetected] = useState(() => hasPasswordRecoveryMarker()
    || new URLSearchParams(window.location.hash.slice(1)).get('type') === 'recovery')
  const [checking, setChecking] = useState(Boolean(supabase && recoveryCallbackDetected))
  const [authorized, setAuthorized] = useState(false)
  const [complete, setComplete] = useState(false)
  const [password, setPassword] = useState('')
  const [confirmPassword, setConfirmPassword] = useState('')
  const [error, setError] = useState(!supabase
    ? 'La recuperación por correo requiere una conexión con Supabase.'
    : recoveryCallbackDetected ? '' : 'Abrí el enlace de recuperación que recibiste por correo.')
  const [busy, setBusy] = useState(false)
  const navigate = useNavigate()
  const { notify } = useNotifications()

  useEffect(() => {
    let mounted = true
    if (!supabase) {
      return () => { mounted = false }
    }

    const { data: { subscription } } = supabase.auth.onAuthStateChange((event, session) => {
      if (event === 'PASSWORD_RECOVERY' && session && mounted) {
        setAuthorized(true)
        setChecking(false)
      }
    })

    if (!recoveryCallbackDetected) {
      return () => { mounted = false; subscription.unsubscribe() }
    }

    void supabase.auth.getSession().then(({ data, error: sessionError }) => {
      if (!mounted) return
      if (!sessionError && data.session) setAuthorized(true)
      else setError('El enlace venció o ya se usó. Solicitá uno nuevo para continuar.')
      setChecking(false)
    }).catch(() => {
      if (mounted) {
        setError('No se pudo validar el enlace. Solicitá uno nuevo para continuar.')
        setChecking(false)
      }
    })

    return () => { mounted = false; subscription.unsubscribe() }
  }, [recoveryCallbackDetected])

  async function submit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault()
    setError('')
    if (password !== confirmPassword) {
      setError('Las contraseñas no coinciden.')
      return
    }
    setBusy(true)
    try {
      await saveRecoveredPassword(password)
      setComplete(true)
      const session = await authRepository.session()
      if (session) {
        await notify({ type: 'success', title: 'Contraseña actualizada', message: 'Ya podés seguir usando CocinAPP con tu nueva contraseña.' })
        navigate(roleHome(session.role), { replace: true })
      }
    } catch (cause) {
      setError(cause instanceof Error ? cause.message : 'No se pudo actualizar la contraseña.')
    } finally {
      setBusy(false)
    }
  }

  return <RecoveryLayout>
    <p className="eyebrow">SEGURIDAD DE TU CUENTA</p>
    {checking ? <><h1>Validando enlace…</h1><p className="field-help" role="status">Esperá un momento.</p></>
      : complete ? <>
        <span className="recovery-success-icon"><CheckCircle2 aria-hidden="true" size={24} /></span>
        <h1>Contraseña actualizada</h1>
        <p className="field-help">Tu cuenta ya tiene una contraseña nueva.</p>
        <Link className="button button-primary button-wide" to="/">Ir a CocinAPP <ArrowRight size={16} /></Link>
      </>
      : !authorized ? <>
        <h1>El enlace no está disponible</h1>
        <p className="form-message error" role="alert">{error || 'Abrí el enlace de recuperación que recibiste por correo.'}</p>
        <Link className="button button-primary button-wide recovery-action-link" to="/recuperar-contrasena">Solicitar otro enlace <ArrowRight size={16} /></Link>
        <Link className="recovery-back-link" to="/">Volver al inicio de sesión</Link>
      </>
      : <>
        <span className="recovery-success-icon"><KeyRound aria-hidden="true" size={23} /></span>
        <h1>Elegí una contraseña nueva</h1>
        <p className="field-help">Usá al menos 8 caracteres. Después vas a entrar a CocinAPP con esa contraseña.</p>
        <form className="access-form recovery-form" noValidate onSubmit={(event) => void submit(event)}>
          {error && <p className="form-message error" role="alert">{error}</p>}
          <label className="field"><span>Nueva contraseña</span><input autoComplete="new-password" maxLength={72} minLength={8} onChange={(event) => setPassword(event.currentTarget.value)} required type="password" value={password} /></label>
          <label className="field"><span>Repetí la contraseña</span><input autoComplete="new-password" maxLength={72} minLength={8} onChange={(event) => setConfirmPassword(event.currentTarget.value)} required type="password" value={confirmPassword} /></label>
          <button className="button button-primary button-wide" disabled={busy} type="submit">{busy ? 'Guardando…' : 'Guardar contraseña'} <ArrowRight size={16} /></button>
        </form>
      </>}
  </RecoveryLayout>
}

function RecoveryLayout({ children }: { children: ReactNode }) {
  return <main className="access-page password-recovery-page">
    <div aria-hidden="true" className="access-decoration access-decoration-one" />
    <div aria-hidden="true" className="access-decoration access-decoration-two" />
    <header className="access-header"><Link aria-label="CocinAPP, volver al inicio" to="/"><BrandLogo className="access-primary-logo" /></Link></header>
    <section aria-live="polite" className="access-card password-recovery-card">{children}</section>
    <footer className="access-footer"><span><strong>CocinAPP</strong> · Recuperación segura de cuenta</span><span>Tu cocina, organizada en un solo lugar</span></footer>
  </main>
}
