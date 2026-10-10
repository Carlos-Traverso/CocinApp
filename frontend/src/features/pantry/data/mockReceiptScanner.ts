export interface ReceiptScanLine {
  id: string
  name: string
  quantity: number
  unit: string
}

export interface ReceiptScanner {
  scan(image: File, signal?: AbortSignal): Promise<ReceiptScanLine[]>
}

export const receiptImageLimitBytes = 5 * 1024 * 1024
export const receiptImageMimeTypes = ['image/jpeg', 'image/png', 'image/webp', 'image/heic', 'image/heif'] as const

export function isValidReceiptImage(image: Pick<File, 'type' | 'size'>): boolean {
  return receiptImageMimeTypes.some((type) => type === image.type) && image.size > 0 && image.size <= receiptImageLimitBytes
}

// Local demo contract. It receives no upload or storage access; replace with an external service later.
export const mockReceiptScanner: ReceiptScanner = {
  async scan(_image, signal) {
    await new Promise<void>((resolve, reject) => {
      if (signal?.aborted) { reject(new DOMException('Scan cancelled', 'AbortError')); return }
      const onAbort = () => { clearTimeout(timeout); reject(new DOMException('Scan cancelled', 'AbortError')) }
      const timeout = setTimeout(() => { signal?.removeEventListener('abort', onAbort); resolve() }, 700)
      signal?.addEventListener('abort', onAbort, { once: true })
    })
    return [
      { id: crypto.randomUUID(), name: 'Leche', quantity: 1, unit: 'l' },
      { id: crypto.randomUUID(), name: 'Arroz', quantity: 1, unit: 'kg' },
      { id: crypto.randomUUID(), name: 'Producto del ticket', quantity: 1, unit: 'u' },
    ]
  },
}
