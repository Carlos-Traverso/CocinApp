import { clearPasswordRecoveryMarker, createIsolatedAuthClient, getPasswordRecoveryIdentity, supabase } from '../../../shared/data/supabaseClient'
import { authSessionIdentity } from '../domain/security'

export async function requestPasswordRecovery(email: string): Promise<void> {
  if (!supabase) throw new Error('La recuperación por correo requiere una conexión con Supabase.')
  const cleanEmail = email.trim().toLocaleLowerCase('es')
  if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(cleanEmail)) throw new Error('Ingresá un correo electrónico válido.')

  const redirectTo = new URL('/restablecer-contrasena', window.location.origin).toString()
  const { error } = await supabase.auth.resetPasswordForEmail(cleanEmail, { redirectTo })
  if (!error) return

  const message = error.message.toLocaleLowerCase('en')
  if (message.includes('rate limit') || message.includes('over_email_send_rate_limit')) {
    throw new Error('Supabase limitó el envío de correos. Esperá un rato antes de volver a intentarlo.')
  }
  throw new Error('No se pudo enviar el correo de recuperación. Revisá la configuración de correo de Supabase e intentá nuevamente.')
}

export async function saveRecoveredPassword(password: string, expectedIdentity: string): Promise<void> {
  if (!supabase) throw new Error('La recuperación por correo requiere una conexión con Supabase.')
  if (password.length < 8) throw new Error('La contraseña debe tener al menos 8 caracteres.')

  const invalidLink = 'El enlace venció o la sesión cambió. Solicitá un enlace nuevo.'
  const { data: { session }, error: sessionError } = await supabase.auth.getSession()
  if (sessionError || !session || expectedIdentity !== getPasswordRecoveryIdentity() || expectedIdentity !== authSessionIdentity(session)) {
    throw new Error(invalidLink)
  }

  // Pin the Auth request to the recovery session even if the shared client switches accounts.
  const recoveryClient = createIsolatedAuthClient()
  const { data, error: restoreError } = await recoveryClient.auth.setSession(session)
  if (restoreError || expectedIdentity !== authSessionIdentity(data.session) || expectedIdentity !== getPasswordRecoveryIdentity()) {
    throw new Error(invalidLink)
  }
  const { error } = await recoveryClient.auth.updateUser({ password })
  if (error) throw new Error('No se pudo cambiar la contraseña. El enlace puede haber vencido; solicitá uno nuevo.')
  if (getPasswordRecoveryIdentity() === expectedIdentity) clearPasswordRecoveryMarker()
}
