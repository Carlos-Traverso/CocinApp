import { useEffect, useMemo, useRef, useState } from 'react'
import { Pencil, Plus, UserRoundX, UserRoundCheck, X } from 'lucide-react'
import { SearchFeedback } from '../../../shared/search/SearchFeedback'
import { useDebouncedSearch } from '../../../shared/search/useDebouncedSearch'
import { useNotifications } from '../../../shared/notifications/NotificationProvider'
import { adminUsersRepository } from '../data/AdminUsersRepository'
import type { ManagedUser } from '../data/AdminUsersRepository'
import './UsersTab.css'
import { isSupabaseConfigured } from '../../../shared/data/supabaseClient'

type UserDraft = { mode: 'create'; name: string; email: string; password: string } | { mode: 'edit'; name: string; email: string }

export function UsersTab() {
  const { notify } = useNotifications()
  const [users, setUsers] = useState<ManagedUser[]>([])
  const [loading, setLoading] = useState(true)
  const [loadError, setLoadError] = useState(false)
  const [search, setSearch] = useState('')
  const [statusFilter, setStatusFilter] = useState<'all' | 'active' | 'inactive'>('all')
  const [draft, setDraft] = useState<UserDraft | null>(null)
  const [pending, setPending] = useState(false)
  const busyRef = useRef(false)
  const openerRef = useRef<HTMLElement | null>(null)
  const debouncedSearch = useDebouncedSearch(search)

  const reload = async () => {
    const rows = await adminUsersRepository.list()
    setUsers(rows)
    setLoadError(false)
  }

  useEffect(() => {
    let mounted = true
    void adminUsersRepository.list().then((rows) => {
      if (mounted) { setUsers(rows); setLoadError(false) }
    }).catch(() => {
      if (mounted) {
        setLoadError(true)
        void notify({ type: 'error', title: 'No se pudieron cargar los usuarios', message: 'Intentá volver a cargar la lista de usuarios.' })
      }
    }).finally(() => { if (mounted) setLoading(false) })
    return () => { mounted = false }
  }, [notify])

  const retryLoad = async () => {
    setLoading(true)
    try {
      await reload()
      setLoadError(false)
    } catch {
      setLoadError(true)
      void notify({ type: 'error', title: 'No se pudieron cargar los usuarios', message: 'Intentá volver a cargar la lista de usuarios.' })
    } finally {
      setLoading(false)
    }
  }

  const closeEditor = () => {
    setDraft(null)
    requestAnimationFrame(() => {
      const opener = openerRef.current
      if (opener?.isConnected && !opener.matches(':disabled')) opener.focus()
    })
  }

  const visibleUsers = useMemo(() => {
    const query = debouncedSearch.query.trim().toLocaleLowerCase()
    return users.filter((user) => debouncedSearch.status !== 'waiting'
      && (!query || `${user.name} ${user.email}`.toLocaleLowerCase().includes(query))
      && (statusFilter === 'all' || (statusFilter === 'active') === user.active))
  }, [users, debouncedSearch, statusFilter])

  const reportRefreshFailure = () => void notify({ type: 'error', title: 'Cambios guardados, lista desactualizada', message: 'La acción se completó, pero no se pudo actualizar la lista. Volvé a cargar la pantalla.' })

  const saveUser = async (event: React.FormEvent<HTMLFormElement>) => {
    event.preventDefault()
    if (!draft || busyRef.current) return
    const form = event.currentTarget
    const invalid = form.querySelector<HTMLElement>(':invalid')
    if (invalid || !draft.name.trim() || (draft.mode === 'create' && !draft.password)) {
      const target = invalid ?? form.querySelector<HTMLElement>('input')
      await notify({ type: 'error', title: 'Revisá los datos', message: 'Completá los campos obligatorios con valores válidos.' })
      target?.focus()
      return
    }
    busyRef.current = true
    setPending(true)
    try {
      if (draft.mode === 'create') await adminUsersRepository.create(draft.name.trim(), draft.email.trim(), draft.password)
      else await adminUsersRepository.updateName(draft.email, draft.name.trim())
    } catch (cause) {
      void notify({ type: 'error', title: 'No se pudo guardar el usuario', message: cause instanceof Error ? cause.message : 'Ocurrió un error al guardar los cambios.' })
      busyRef.current = false
      setPending(false)
      return
    }
    closeEditor()
    try {
      await reload()
      void notify({ type: 'success', title: draft.mode === 'create' ? 'Usuario creado' : 'Nombre actualizado', message: 'Los cambios se guardaron.' })
    } catch {
      reportRefreshFailure()
    } finally {
      busyRef.current = false
      setPending(false)
    }
  }

  const toggleActive = async (user: ManagedUser) => {
    if (user.isDemoAdmin || busyRef.current) return
    busyRef.current = true
    setPending(true)
    try {
      if (user.active) {
        const confirmed = await notify({ type: 'warning', title: 'Desactivar usuario', message: `¿Desactivar la cuenta de ${user.name} (${user.email})? Sus datos se conservarán.`, confirmLabel: 'Desactivar', cancelLabel: 'Cancelar' })
        if (!confirmed) return
      }
      try {
        await adminUsersRepository.setActive(user.email, !user.active)
      } catch (cause) {
        void notify({ type: 'error', title: 'No se pudo actualizar el usuario', message: cause instanceof Error ? cause.message : 'Ocurrió un error al actualizar el estado.' })
        return
      }
      try {
        await reload()
        void notify({ type: 'success', title: user.active ? 'Usuario desactivado' : 'Usuario activado', message: 'El estado del usuario se actualizó.' })
      } catch {
        reportRefreshFailure()
      }
    } finally {
      busyRef.current = false
      setPending(false)
    }
  }

  const changeRole = async (user: ManagedUser, role: 'USER' | 'ADMIN') => {
    if (user.isDemoAdmin || role === user.role || busyRef.current) return
    const nextRole = role === 'ADMIN' ? 'administrador' : 'usuario'
    const confirmed = await notify({
      type: 'warning',
      title: role === 'ADMIN' ? 'Dar acceso de administrador' : 'Quitar acceso de administrador',
      message: `¿Cambiar el rol de ${user.name} (${user.email}) a ${nextRole}? El cambio se aplicará cuando esa persona vuelva a iniciar sesión.`,
      confirmLabel: 'Cambiar rol',
      cancelLabel: 'Cancelar',
    })
    if (!confirmed) return
    busyRef.current = true
    setPending(true)
    try {
      await adminUsersRepository.setRole(user.email, role)
      await reload()
      void notify({ type: 'success', title: 'Rol actualizado', message: `La cuenta ahora tiene el rol ${role === 'ADMIN' ? 'Administrador' : 'Usuario'}.` })
    } catch (cause) {
      void notify({ type: 'error', title: 'No se pudo cambiar el rol', message: cause instanceof Error ? cause.message : 'Ocurrió un error al cambiar el rol.' })
    } finally {
      busyRef.current = false
      setPending(false)
    }
  }

  return <div className="panel users-tab">
    <div className="section-header">
      <div><h2>Usuarios</h2><p className="panel-intro"><SearchFeedback resultCount={visibleUsers.length} status={debouncedSearch.status} /> · {users.length} usuarios totales</p></div>
      <button className="button button-primary" disabled={loading || pending} onClick={(event) => { openerRef.current = event.currentTarget; setDraft({ mode: 'create', name: '', email: '', password: '' }) }} type="button"><Plus size={16} /> Nuevo usuario</button>
    </div>
    {isSupabaseConfigured && <p className="panel-intro">Las cuentas nuevas se crean con correo confirmado y la contraseña inicial que definas. El usuario podrá cambiarla después desde su cuenta.</p>}
    <div className="admin-catalog-filters users-filters">
      <label className="field admin-filter-search"><span>Buscar por nombre o email</span><input onChange={(event) => setSearch(event.currentTarget.value)} type="search" value={search} /></label>
      <label className="field"><span>Estado</span><select onChange={(event) => setStatusFilter(event.currentTarget.value as typeof statusFilter)} value={statusFilter}><option value="all">Todos</option><option value="active">Activos</option><option value="inactive">Inactivos</option></select></label>
    </div>
    {loading ? <p role="status">Cargando usuarios…</p> : loadError ? <div className="users-load-error"><button className="button button-quiet" disabled={pending} onClick={() => void retryLoad()} type="button">Reintentar carga de usuarios</button></div> : <div className="records">
      {visibleUsers.map((user) => <article className="record users-record" key={user.email}>
        <div className="record-main"><strong>{user.name}</strong><small className="users-email">{user.email}</small><span className={`admin-entity-status ${user.active ? 'active' : 'inactive'}`}>{user.active ? 'Activo' : 'Inactivo'}</span><small>Rol: {user.role === 'ADMIN' ? 'Administrador' : 'Usuario'}{user.isDemoAdmin ? ' · Cuenta de demostración' : ''}</small></div>
        <div className="record-actions">
          {user.isDemoAdmin ? <span className="users-readonly">Solo lectura</span> : <>
            {isSupabaseConfigured && <label className="users-role-control"><span className="sr-only">Rol de {user.name}</span><select aria-label={`Rol de ${user.name}`} disabled={pending} onChange={(event) => void changeRole(user, event.currentTarget.value as 'USER' | 'ADMIN')} value={user.role}><option value="USER">Usuario</option><option value="ADMIN">Administrador</option></select></label>}
            <button aria-label={`Editar nombre de ${user.name}`} className="pantry-icon-button" disabled={pending} onClick={(event) => { openerRef.current = event.currentTarget; setDraft({ mode: 'edit', name: user.name, email: user.email }) }} type="button"><Pencil size={17} /></button>
            <button aria-label={`${user.active ? 'Desactivar' : 'Activar'} usuario ${user.name}`} className="button button-quiet users-status-button" disabled={pending} onClick={() => void toggleActive(user)} type="button">{user.active ? <><UserRoundX size={16} /> Desactivar</> : <><UserRoundCheck size={16} /> Activar</>}</button>
          </>}
        </div>
      </article>)}
      {debouncedSearch.status !== 'waiting' && visibleUsers.length === 0 && <p className="empty">No hay usuarios que coincidan con los filtros.</p>}
    </div>}

    {draft && <dialog aria-labelledby="user-editor-title" className="shopping-editor surface" onCancel={(event) => { event.preventDefault(); if (!pending) closeEditor() }} ref={(node) => { if (node && !node.open) { node.showModal(); node.querySelector<HTMLElement>('input:not(:disabled)')?.focus() } }}>
      <div className="shopping-editor-heading"><h2 id="user-editor-title">{draft.mode === 'create' ? 'Nuevo usuario' : 'Editar nombre'}</h2><button aria-label="Cerrar formulario de usuario" className="pantry-icon-button" disabled={pending} onClick={closeEditor} type="button"><X size={19} /></button></div>
      <form noValidate onSubmit={saveUser}>
        <label className="field"><span>Nombre</span><input autoComplete="name" disabled={pending} maxLength={80} onChange={(event) => setDraft({ ...draft, name: event.currentTarget.value })} required value={draft.name} /></label>
        {draft.mode === 'create' ? <>
          <label className="field"><span>Email</span><input autoComplete="email" disabled={pending} maxLength={254} onChange={(event) => setDraft({ ...draft, email: event.currentTarget.value })} required type="email" value={draft.email} /></label>
          <label className="field"><span>Contraseña inicial (8 a 72 caracteres)</span><input autoComplete="new-password" disabled={pending} maxLength={72} minLength={8} onChange={(event) => setDraft({ ...draft, password: event.currentTarget.value })} required type="password" value={draft.password} /></label>
        </> : <label className="field"><span>Email</span><input readOnly value={draft.email} /></label>}
        <div className="pantry-dialog-actions"><button className="button button-quiet" disabled={pending} onClick={closeEditor} type="button">Cancelar</button><button className="button button-primary" disabled={pending} type="submit">{pending ? 'Guardando…' : 'Guardar'}</button></div>
      </form>
    </dialog>}
  </div>
}
