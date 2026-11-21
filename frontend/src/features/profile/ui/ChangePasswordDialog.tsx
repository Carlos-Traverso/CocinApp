import { Eye, EyeOff } from 'lucide-react'
import { type FormEvent, useEffect, useRef, useState } from 'react'
import { authRepository } from '../../auth/data/AuthRepository'

export function ChangePasswordDialog({ onClose, onChanged }: {
  onClose: () => void
  onChanged: () => void
}) {
  const dialogRef = useRef<HTMLDialogElement>(null)
  const titleRef = useRef<HTMLHeadingElement>(null)
  const savingRef = useRef(false)
  const [currentPassword, setCurrentPassword] = useState('')
  const [newPassword, setNewPassword] = useState('')
  const [repeatedPassword, setRepeatedPassword] = useState('')
  const [confirming, setConfirming] = useState(false)
  const [saving, setSaving] = useState(false)
  const [error, setError] = useState('')
  const [currentError, setCurrentError] = useState('')
  const [visible, setVisible] = useState([false, false, false])

  useEffect(() => {
    const dialog = dialogRef.current
    if (!dialog) return
    dialog.showModal()
    return () => dialog.close()
  }, [])

  useEffect(() => {
    titleRef.current?.focus()
  }, [confirming])

  function cancel() {
    dialogRef.current?.close()
    onClose()
  }

  async function review(event: FormEvent<HTMLFormElement>) {
    event.preventDefault()
    if (newPassword === currentPassword) {
      setError('La nueva contraseña debe ser distinta de la actual.')
      return
    }
    if (newPassword !== repeatedPassword) {
      setError('Las nuevas contraseñas no coinciden.')
      return
    }
    if (savingRef.current) return
    savingRef.current = true
    setSaving(true)
    setError('')
    setCurrentError('')
    try {
      await authRepository.verifyCurrentPassword(currentPassword)
      setVisible([false, false, false])
      setConfirming(true)
    } catch (failure) {
      const message = failure instanceof Error ? failure.message : 'No se pudo verificar la contraseña actual. Intentá de nuevo.'
      if (message === 'La contraseña actual es incorrecta.') {
        setCurrentError(message)
        dialogRef.current?.querySelector<HTMLInputElement>('input')?.focus()
      } else setError(message)
    } finally {
      savingRef.current = false
      setSaving(false)
    }
  }

  async function save(event: FormEvent<HTMLFormElement>) {
    event.preventDefault()
    if (savingRef.current) return
    savingRef.current = true
    setSaving(true)
    try {
      await authRepository.changePassword(currentPassword, newPassword)
      dialogRef.current?.close()
      onChanged()
    } catch (failure) {
      const message = failure instanceof Error ? failure.message : 'No se pudo cambiar la contraseña. Intentá de nuevo.'
      if (message === 'La contraseña actual es incorrecta.') setCurrentError(message)
      else setError(message)
      setConfirming(false)
    } finally {
      savingRef.current = false
      setSaving(false)
    }
  }

  return <dialog
    aria-labelledby="profile-password-title"
    className="pantry-dialog profile-password-dialog"
    onCancel={(event) => {
      event.preventDefault()
      if (savingRef.current) return
      if (confirming) setConfirming(false)
      else cancel()
    }}
    ref={dialogRef}
  >
    <h2 id="profile-password-title" ref={titleRef} tabIndex={-1}>{confirming ? '¿Estás seguro de que querés cambiar tu contraseña?' : 'Cambiar contraseña'}</h2>
    {confirming
      ? <form key="confirmation" onSubmit={save}>
        <p className="pantry-dialog-intro">Vas a usar la nueva contraseña la próxima vez que inicies sesión.</p>
        <div className="pantry-dialog-actions">
          <button className="button button-quiet" disabled={saving} onClick={() => setConfirming(false)} type="button">Volver</button>
          <button className="button button-primary" disabled={saving} type="submit">{saving ? 'Guardando…' : 'Sí, cambiar contraseña'}</button>
        </div>
      </form>
      : <form className="profile-password-form" key="password" onInput={() => setError('')} onSubmit={review}>
        {error && <p className="form-message error" role="alert">{error}</p>}
        <label className="field">
          <span>Contraseña actual</span>
          <span className="profile-password-input">
            <input disabled={saving} aria-invalid={Boolean(currentError)} aria-describedby={currentError ? 'profile-current-password-error' : undefined} autoComplete="current-password" onChange={(event) => { setCurrentPassword(event.currentTarget.value); setCurrentError('') }} required type={visible[0] ? 'text' : 'password'} value={currentPassword} />
            <button aria-label={visible[0] ? 'Ocultar contraseña actual' : 'Mostrar contraseña actual'} aria-pressed={visible[0]} className="profile-password-toggle" disabled={saving} onClick={() => setVisible((values) => values.map((value, i) => i === 0 ? !value : value))} type="button">{visible[0] ? <EyeOff aria-hidden="true" size={19} /> : <Eye aria-hidden="true" size={19} />}</button>
          </span>
          {currentError && <small className="profile-password-error" id="profile-current-password-error" role="alert">{currentError}</small>}
        </label>
        <label className="field">
          <span>Nueva contraseña</span>
          <span className="profile-password-input">
            <input disabled={saving} aria-describedby="profile-password-length" autoComplete="new-password" maxLength={72} minLength={8} onChange={(event) => setNewPassword(event.currentTarget.value)} required type={visible[1] ? 'text' : 'password'} value={newPassword} />
            <button aria-label={visible[1] ? 'Ocultar contraseña nueva' : 'Mostrar contraseña nueva'} aria-pressed={visible[1]} className="profile-password-toggle" disabled={saving} onClick={() => setVisible((values) => values.map((value, i) => i === 1 ? !value : value))} type="button">{visible[1] ? <EyeOff aria-hidden="true" size={19} /> : <Eye aria-hidden="true" size={19} />}</button>
          </span>
          <small id="profile-password-length">Usá al menos 8 caracteres.</small>
        </label>
        <label className="field">
          <span>Repetí la nueva contraseña</span>
          <span className="profile-password-input">
            <input disabled={saving} autoComplete="new-password" maxLength={72} minLength={8} onChange={(event) => setRepeatedPassword(event.currentTarget.value)} required type={visible[2] ? 'text' : 'password'} value={repeatedPassword} />
            <button aria-label={visible[2] ? 'Ocultar contraseña repetida' : 'Mostrar contraseña repetida'} aria-pressed={visible[2]} className="profile-password-toggle" disabled={saving} onClick={() => setVisible((values) => values.map((value, i) => i === 2 ? !value : value))} type="button">{visible[2] ? <EyeOff aria-hidden="true" size={19} /> : <Eye aria-hidden="true" size={19} />}</button>
          </span>
        </label>
        <div className="pantry-dialog-actions">
          <button className="button button-quiet" disabled={saving} onClick={cancel} type="button">Cancelar</button>
          <button className="button button-primary" disabled={saving} type="submit">{saving ? 'Verificando…' : 'Confirmar'}</button>
        </div>
      </form>}
  </dialog>
}
