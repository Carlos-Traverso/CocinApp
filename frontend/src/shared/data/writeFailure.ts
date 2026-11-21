export function writeFailureMessage(error: unknown, reloadInstruction: string): string | undefined {
  if (!error || typeof error !== 'object') return undefined
  const { code, message } = error as { code?: string; message?: string }
  if (code === '40001') return `Los datos cambiaron en otra sesión. ${reloadInstruction}`
  if (code === '55P03') return `Hay otra operación en curso. ${reloadInstruction}`
  if (code === '57014' || /^(?:AbortError|TimeoutError):/.test(message ?? '')) {
    return `Se agotó el tiempo de espera y no se confirmó el guardado. ${reloadInstruction}`
  }
  return undefined
}
