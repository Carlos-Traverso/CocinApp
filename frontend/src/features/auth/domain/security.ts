/** A production deployment must never fall back to browser-only demo accounts. */
export function assertAuthenticationConfigured(production: boolean, configured: boolean): void {
  if (production && !configured) {
    throw new Error('El acceso no está disponible: falta configurar la conexión segura con Supabase.')
  }
}
