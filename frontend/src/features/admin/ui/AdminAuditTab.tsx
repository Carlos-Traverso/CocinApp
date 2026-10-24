import { useEffect, useState } from 'react'
import { RefreshCw, Search } from 'lucide-react'
import { adminAuditRepository, type AdminAuditEvent } from '../data/AdminAuditRepository'
import { useDebouncedSearch } from '../../../shared/search/useDebouncedSearch'

const actionLabels: Record<string, string> = {
  'user.created': 'Creó una cuenta',
  'user.name_updated': 'Cambió el nombre de una cuenta',
  'user.role_changed': 'Cambió el rol de una cuenta',
  'user.activated': 'Activó una cuenta',
  'user.deactivated': 'Desactivó una cuenta',
  'catalog.core_saved': 'Guardó cambios en ingredientes, categorías o unidades',
  'catalog.recipes_saved': 'Guardó cambios en recetas',
}

function describeDetails(event: AdminAuditEvent): string | null {
  if (event.action === 'user.role_changed') {
    const oldRole = event.details.old_role
    const newRole = event.details.new_role
    if (typeof newRole === 'string') return `${oldRole === 'ADMIN' ? 'Administrador' : 'Usuario'} → ${newRole === 'ADMIN' ? 'Administrador' : 'Usuario'}`
  }
  if (event.action === 'user.activated' || event.action === 'user.deactivated') return event.details.active === true ? 'Estado: activo' : 'Estado: inactivo'
  if (typeof event.details.version === 'number') return `Versión ${event.details.version}`
  return null
}

export function AdminAuditTab() {
  const [events, setEvents] = useState<AdminAuditEvent[]>([])
  const [loading, setLoading] = useState(true)
  const [failed, setFailed] = useState(false)
  const [refresh, setRefresh] = useState(0)
  const [search, setSearch] = useState('')
  const debouncedSearch = useDebouncedSearch(search)

  useEffect(() => {
    let current = true
    setLoading(true)
    void adminAuditRepository.list(debouncedSearch.query).then((rows) => {
      if (current) { setEvents(rows); setFailed(false) }
    }).catch(() => {
      if (current) setFailed(true)
    }).finally(() => {
      if (current) setLoading(false)
    })
    return () => { current = false }
  }, [refresh, debouncedSearch.query])

  return <div className="admin-audit-tab">
    <div className="section-header">
      <div><h2>Actividad administrativa</h2><p className="panel-intro">{search.trim() ? 'Hasta 100 resultados que coinciden con la búsqueda.' : 'Últimos 100 cambios realizados por administradores.'}</p></div>
      <div className="admin-audit-actions">
        <label className="field admin-audit-search">
          <span className="sr-only">Buscar por correo, usuario o cambio</span>
          <Search aria-hidden="true" size={16} />
          <input aria-label="Buscar por correo, usuario o cambio" onChange={(event) => setSearch(event.currentTarget.value)} placeholder="Buscar por mail, usuario o cambio" type="search" value={search} />
        </label>
        <button aria-label="Actualizar historial" className="button button-quiet" disabled={loading} onClick={() => setRefresh((value) => value + 1)} type="button"><RefreshCw aria-hidden="true" size={16} /> Actualizar</button>
      </div>
    </div>
    {loading || debouncedSearch.status === 'waiting' ? <p role="status">Buscando en el historial…</p> : failed ? <div className="users-load-error"><p>No se pudo cargar el historial. Confirmá que la migración esté aplicada y volvé a intentarlo.</p><button className="button button-quiet" onClick={() => setRefresh((value) => value + 1)} type="button">Reintentar</button></div> : events.length === 0 ? <p className="empty">{search.trim() ? 'No hay cambios que coincidan con la búsqueda.' : 'Todavía no hay cambios administrativos registrados.'}</p> : <ol aria-label="Cambios administrativos recientes" className="admin-audit-list">
      {events.map((event) => <li className="admin-audit-event" key={event.id}>
        <div className="admin-audit-event-main">
          <strong>{actionLabels[event.action] ?? 'Acción administrativa'}</strong>
          <span className="admin-audit-actor-name">{event.actorName ?? 'Sistema o cambio realizado desde SQL Editor'}</span>
          {event.actorEmail && <small>{event.actorEmail}</small>}
          {event.targetEmail && <span>Cuenta afectada: {event.targetName ?? event.targetEmail}{event.targetName && event.targetName !== event.targetEmail ? ` (${event.targetEmail})` : ''}</span>}
          {describeDetails(event) && <small>{describeDetails(event)}</small>}
        </div>
        <time dateTime={event.occurredAt}>{new Date(event.occurredAt).toLocaleString('es-AR', { dateStyle: 'medium', timeStyle: 'short' })}</time>
      </li>)}
    </ol>}
  </div>
}
