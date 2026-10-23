import { clearPasswordRecoveryMarker, supabase } from '../../../shared/data/supabaseClient'

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

export async function saveRecoveredPassword(password: string): Promise<void> {
  if (!supabase) throw new Error('La recuperación por correo requiere una conexión con Supabase.')
  if (password.length < 8) throw new Error('La contraseña debe tener al menos 8 caracteres.')

  const { error } = await supabase.auth.updateUser({ password })
  if (error) throw new Error('No se pudo cambiar la contraseña. El enlace puede haber vencido; solicitá uno nuevo.')
  clearPasswordRecoveryMarker()
}
