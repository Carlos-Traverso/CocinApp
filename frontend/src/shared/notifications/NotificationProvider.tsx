import {
  createContext,
  useCallback,
  useContext,
  useEffect,
  useId,
  useRef,
  useState,
  type ReactNode,
  type SyntheticEvent,
} from 'react'

export type NotificationType = 'success' | 'info' | 'warning' | 'error'

export interface NotificationRequest {
  type: NotificationType
  title: string
  message: string
  confirmLabel?: string
  cancelLabel?: string
}

interface PendingNotification {
  id: number
  request: NotificationRequest
  resolve: (confirmed: boolean) => void
}

interface NotificationContextValue {
  notify: (request: NotificationRequest) => Promise<boolean>
}

const NotificationContext = createContext<NotificationContextValue | null>(null)

const typeLabels: Record<NotificationType, string> = {
  success: 'Éxito',
  info: 'Información',
  warning: 'Advertencia',
  error: 'Error',
}

const isConfirmation = (pending: PendingNotification) => Boolean(pending.request.cancelLabel)

export function NotificationProvider({ children }: { children: ReactNode }) {
  const [active, setActive] = useState<PendingNotification | null>(null)
  const activeRef = useRef<PendingNotification | null>(null)
  const queueRef = useRef<PendingNotification[]>([])
  const nextIdRef = useRef(0)

  const activateNext = useCallback(() => {
    const next = queueRef.current.shift() ?? null
    activeRef.current = next
    setActive(next)
  }, [])

  const notify = useCallback((request: NotificationRequest) => {
    return new Promise<boolean>((resolve) => {
      const pending: PendingNotification = {
        id: ++nextIdRef.current,
        request,
        resolve,
      }

      const active = activeRef.current
      if (!active) {
        queueRef.current.push(pending)
        activateNext()
        return
      }

      if (isConfirmation(pending)) {
        // Passive notices are obsolete once a user has requested a decision.
        // Resolve them as dismissed so callers waiting on notify() do not hang.
        queueRef.current = queueRef.current.filter((queued) => {
          if (isConfirmation(queued)) return true
          queued.resolve(false)
          return false
        })
        if (!isConfirmation(active)) {
          active.resolve(false)
          activeRef.current = pending
          setActive(pending)
        } else {
          // Decisions are never silently replaced: keep them in order until
          // the user explicitly confirms or cancels each one.
          queueRef.current.push(pending)
        }
        return
      }

      if (isConfirmation(active) || queueRef.current.some(isConfirmation)) {
        resolve(false)
        return
      }

      // Keep only the most recent passive notice instead of stacking old
      // success or information messages behind the one currently visible.
      active.resolve(false)
      activeRef.current = pending
      setActive(pending)
    })
  }, [activateNext])

  const finish = useCallback((id: number, confirmed: boolean) => {
    const current = activeRef.current
    if (!current || current.id !== id) return
    current.resolve(confirmed)
    activateNext()
  }, [activateNext])

  return (
    <NotificationContext.Provider value={{ notify }}>
      {children}
      {active && <NotificationDialog pending={active} onFinish={finish} />}
    </NotificationContext.Provider>
  )
}

export function useNotifications(): NotificationContextValue {
  const context = useContext(NotificationContext)
  if (!context) throw new Error('useNotifications must be used within NotificationProvider')
  return context
}

function NotificationDialog({
  pending,
  onFinish,
}: {
  pending: PendingNotification
  onFinish: (id: number, confirmed: boolean) => void
}) {
  const titleId = useId()
  const typeId = useId()
  const messageId = useId()
  const dialogRef = useRef<HTMLDialogElement>(null)
  const confirmRef = useRef<HTMLButtonElement>(null)
  const cancelRef = useRef<HTMLButtonElement>(null)
  const { request } = pending

  useEffect(() => {
    const dialog = dialogRef.current
    if (!dialog) return
    if (!dialog.open) dialog.showModal()
    const initialFocus = request.cancelLabel ? cancelRef.current : confirmRef.current
    initialFocus?.focus()
    return () => {
      if (dialog.open) dialog.close()
    }
  }, [])

  useEffect(() => {
    const initialFocus = request.cancelLabel ? cancelRef.current : confirmRef.current
    initialFocus?.focus()
  }, [pending.id, request.cancelLabel])

  const handleCancel = (event: SyntheticEvent<HTMLDialogElement>) => {
    // Native dialog Escape requests are always treated as cancellation. They
    // can never accept a pending destructive action.
    event.preventDefault()
    onFinish(pending.id, false)
  }

  const content = (
    <dialog
      aria-describedby={`${typeId} ${messageId}`}
      aria-labelledby={titleId}
      className="notification-host"
      onCancel={handleCancel}
      ref={dialogRef}
      style={{ width: '100%', maxWidth: 'none', height: '100%', maxHeight: 'none', margin: 0, padding: 0, border: 0, background: 'transparent', overflow: 'visible' }}
    >
      <div className="notification-backdrop">
        <div className={`notification-dialog notification-${request.type}`}>
          <span className="notification-type" id={typeId}>{typeLabels[request.type]}</span>
          <h2 className="notification-title" id={titleId}>{request.title}</h2>
          <p className="notification-message" id={messageId}>{request.message}</p>
          <div className="notification-actions">
            {request.cancelLabel && (
              <button className="notification-button notification-button-secondary" onClick={() => onFinish(pending.id, false)} ref={cancelRef} type="button">
                {request.cancelLabel}
              </button>
            )}
            <button
              className="notification-button notification-button-primary"
              onClick={() => onFinish(pending.id, true)}
              ref={confirmRef}
              type="button"
            >
              {request.confirmLabel ?? 'Aceptar'}
            </button>
          </div>
        </div>
      </div>
    </dialog>
  )

  return content
}
