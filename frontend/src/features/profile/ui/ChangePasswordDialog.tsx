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

  function review(event: FormEvent<HTMLFormElement>) {
    event.preventDefault()
    if (newPassword === currentPassword) {
      setError('La nueva contraseña debe ser distinta de la actual.')
      return
    }
    if (newPassword !== repeatedPassword) {
      setError('Las nuevas contraseñas no coinciden.')
      return
    }
    setError('')
    setConfirming(true)
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
      setError(failure instanceof Error ? failure.message : 'No se pudo cambiar la contraseña. Intentá de nuevo.')
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
          <input autoComplete="current-password" onChange={(event) => setCurrentPassword(event.currentTarget.value)} required type="password" value={currentPassword} />
        </label>
        <label className="field">
          <span>Nueva contraseña</span>
          <input aria-describedby="profile-password-length" autoComplete="new-password" maxLength={72} minLength={8} onChange={(event) => setNewPassword(event.currentTarget.value)} required type="password" value={newPassword} />
          <small id="profile-password-length">Usá al menos 8 caracteres.</small>
        </label>
        <label className="field">
          <span>Repetí la nueva contraseña</span>
          <input autoComplete="new-password" maxLength={72} minLength={8} onChange={(event) => setRepeatedPassword(event.currentTarget.value)} required type="password" value={repeatedPassword} />
        </label>
        <div className="pantry-dialog-actions">
          <button className="button button-quiet" onClick={cancel} type="button">Cancelar</button>
          <button className="button button-primary" type="submit">Confirmar</button>
        </div>
      </form>}
  </dialog>
}
