export const SEARCH_DEBOUNCE_MS = 500

export type SearchStatus = 'empty' | 'waiting' | 'ready' | 'error' | 'selected'

export interface DebouncedValueScheduler<T> {
  schedule: (value: T) => void
  cancel: () => void
  dispose: () => void
}

export function createDebouncedValueScheduler<T>(
  onValue: (value: T) => void,
  delay = SEARCH_DEBOUNCE_MS,
): DebouncedValueScheduler<T> {
  let timer: ReturnType<typeof setTimeout> | undefined
  let disposed = false

  const cancel = () => {
    if (timer !== undefined) clearTimeout(timer)
    timer = undefined
  }

  return {
    schedule(value) {
      if (disposed) return
      cancel()
      timer = setTimeout(() => {
        timer = undefined
        if (!disposed) onValue(value)
      }, delay)
    },
    cancel,
    dispose() {
      disposed = true
      cancel()
    },
  }
}

export function searchFeedback(status: SearchStatus, resultCount: number): string {
  if (status === 'empty') return 'Escribí para buscar'
  if (status === 'waiting') return 'Buscando…'
  if (status === 'error') return 'Ocurrió un error. Intentá nuevamente'
  if (status === 'selected') return 'Resultado seleccionado'
  if (resultCount === 0) return 'No encontramos resultados'
  return `${resultCount} ${resultCount === 1 ? 'resultado' : 'resultados'}`
}
