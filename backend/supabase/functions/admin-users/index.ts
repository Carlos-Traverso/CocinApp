import { createClient, type SupabaseClient } from 'https://esm.sh/@supabase/supabase-js@2'

type AdminAction =
  | { action: 'create'; name: string; email: string; password: string }
  | { action: 'update_name'; email: string; name: string }
  | { action: 'set_active'; email: string; active: boolean }
  | { action: 'set_role'; email: string; role: 'USER' | 'ADMIN' }

type AdminAuditAction = 'user.created' | 'user.name_updated'

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
}

function response(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  })
}

function firstSecret(name: string, collectionName: string): string | undefined {
  const direct = Deno.env.get(name)
  if (direct) return direct
  const collection = Deno.env.get(collectionName)
  if (!collection) return undefined
  try {
    const values = Object.values(JSON.parse(collection) as Record<string, unknown>)
    return values.find((value): value is string => typeof value === 'string' && value.length > 0)
  } catch {
    return undefined
  }
}

function cleanName(value: unknown): string {
  if (typeof value !== 'string') throw new Error('Ingresá un nombre válido.')
  const name = value.trim()
  if (!name || name.length > 80) throw new Error('El nombre debe tener entre 1 y 80 caracteres.')
  return name
}

function cleanEmail(value: unknown): string {
  if (typeof value !== 'string') throw new Error('Ingresá un correo válido.')
  const email = value.trim().toLocaleLowerCase('en')
  if (email.length > 254 || !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) throw new Error('Ingresá un correo electrónico válido.')
  return email
}

async function findUserByEmail(admin: SupabaseClient, email: string) {
  for (let page = 1; page <= 1000; page += 1) {
    const { data, error } = await admin.auth.admin.listUsers({ page, perPage: 100 })
    if (error) throw error
    const user = data.users.find((candidate) => candidate.email?.toLocaleLowerCase('en') === email)
    if (user) return user
    if (data.users.length < 100) return undefined
  }
  throw new Error('La búsqueda de usuarios superó el límite permitido.')
}

async function recordAdminAction(admin: SupabaseClient, actorUserId: string, action: AdminAuditAction, targetUserId: string) {
  return admin.from('admin_audit_log').insert({
    actor_user_id: actorUserId,
    action,
    target_user_id: targetUserId,
  })
}

async function isCurrentAdministrator(caller: SupabaseClient): Promise<boolean> {
  const { data: role, error } = await caller.rpc('current_app_role')
  return !error && role === 'ADMIN'
}

Deno.serve(async (request) => {
  if (request.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders })
  if (request.method !== 'POST') return response({ error: 'Método no permitido.' }, 405)

  try {
    const authorization = request.headers.get('Authorization')
    const token = authorization?.match(/^Bearer\s+(.+)$/i)?.[1]
    if (!token) return response({ error: 'Iniciá sesión para continuar.' }, 401)

    const url = Deno.env.get('SUPABASE_URL')
    const publishableKey = firstSecret('SUPABASE_ANON_KEY', 'SUPABASE_PUBLISHABLE_KEYS')
      ?? Deno.env.get('SUPABASE_PUBLISHABLE_KEY')
    const secretKey = firstSecret('SUPABASE_SERVICE_ROLE_KEY', 'SUPABASE_SECRET_KEYS')
    if (!url || !publishableKey || !secretKey) {
      return response({ error: 'La función no tiene configuradas las credenciales de Supabase.' }, 500)
    }

    const caller = createClient(url, publishableKey, {
      auth: { autoRefreshToken: false, persistSession: false },
      global: { headers: { Authorization: `Bearer ${token}` } },
    })
    const { data: userData, error: userError } = await caller.auth.getUser(token)
    if (userError || !userData.user) return response({ error: 'La sesión no es válida. Volvé a iniciar sesión.' }, 401)

    const { data: role, error: roleError } = await caller.rpc('current_app_role')
    if (roleError) return response({ error: 'No se pudo verificar el rol de administrador.' }, 403)
    if (role !== 'ADMIN') return response({ error: 'Solo una cuenta administradora puede gestionar usuarios.' }, 403)
    const admin = createClient(url, secretKey, {
      auth: { autoRefreshToken: false, persistSession: false },
    })
    const input = await request.json() as Partial<AdminAction>

    if (input.action === 'create') {
      const name = cleanName(input.name)
      const email = cleanEmail(input.email)
      if (typeof input.password !== 'string' || input.password.length < 8 || input.password.length > 72) {
        return response({ error: 'La contraseña inicial debe tener entre 8 y 72 caracteres.' }, 400)
      }
      // This final role check admits the whole operation. Once it succeeds,
      // the Auth request may finish if a role change happens while it is in
      // flight; Auth and SQL writes cannot share one atomic transaction.
      if (!await isCurrentAdministrator(caller)) {
        return response({ error: 'Se revocó tu permiso de administrador antes de crear la cuenta.' }, 403)
      }
      const { data: created, error } = await admin.auth.admin.createUser({
        email,
        password: input.password,
        email_confirm: true,
        user_metadata: { name },
      })
      if (error) return response({ error: error.message }, 400)
      if (!created.user) return response({ error: 'La cuenta se creó, pero Supabase no devolvió su identificador.' }, 502)
      const { error: auditError } = await recordAdminAction(admin, userData.user.id, 'user.created', created.user.id)
      if (auditError) return response({ error: 'La cuenta se creó, pero no se pudo registrar la acción en el historial. No vuelvas a crearla; actualizá el historial y verificá la cuenta.' }, 502)
      return response({ success: true })
    }

    if (input.action === 'update_name') {
      const email = cleanEmail(input.email)
      const name = cleanName(input.name)
      const user = await findUserByEmail(admin, email)
      if (!user) return response({ error: 'No existe una cuenta con ese correo.' }, 404)

      const { data: profileRow, error: profileReadError } = await admin
        .from('personal_data')
        .select('value')
        .eq('user_id', user.id)
        .eq('data_key', 'profile')
        .maybeSingle()
      if (profileReadError) return response({ error: 'No se pudo leer el perfil actual del usuario.' }, 500)
      const currentProfile = profileRow?.value && typeof profileRow.value === 'object' && !Array.isArray(profileRow.value)
        ? profileRow.value as Record<string, unknown>
        : {}
      // This check admits the profile and Auth updates as one logical action.
      // A later role change cannot cancel an Auth request already in flight.
      if (!await isCurrentAdministrator(caller)) {
        return response({ error: 'Se revocó tu permiso de administrador antes de actualizar el nombre.' }, 403)
      }
      const { error: profileWriteError } = await admin.from('personal_data').upsert({
        user_id: user.id,
        data_key: 'profile',
        value: { ...currentProfile, name },
        updated_at: new Date().toISOString(),
      }, { onConflict: 'user_id,data_key' })
      if (profileWriteError) return response({ error: 'No se pudo actualizar el nombre en el perfil del usuario.' }, 500)

      const { error } = await admin.auth.admin.updateUserById(user.id, {
        user_metadata: { ...user.user_metadata, name },
      })
      if (error) return response({ error: error.message }, 400)
      const { error: auditError } = await recordAdminAction(admin, userData.user.id, 'user.name_updated', user.id)
      if (auditError) return response({ error: 'El nombre se actualizó, pero no se pudo registrar la acción en el historial. Recargá la lista y verificá el cambio.' }, 502)
      return response({ success: true })
    }

    if (input.action === 'set_active') {
      const email = cleanEmail(input.email)
      if (typeof input.active !== 'boolean') return response({ error: 'El estado de la cuenta no es válido.' }, 400)
      const user = await findUserByEmail(admin, email)
      if (!user) return response({ error: 'No existe una cuenta con ese correo.' }, 404)
      if (user.id === userData.user.id && !input.active) {
        return response({ error: 'No podés desactivar la cuenta con la que estás usando el panel.' }, 400)
      }
      // Authorization, the last-admin check and the state change share one
      // database transaction and lock with admin_set_user_role. Do not ban via
      // Auth here: a second, delayed HTTP write would reintroduce the race.
      const { error } = await caller.rpc('admin_set_user_active', {
        target_user_id: user.id,
        new_active: input.active,
      })
      if (error) return response({ error: error.message }, 400)

      // Old releases used Auth bans. Only remove a legacy ban after the database
      // accepts activation. A concurrent disable still wins through RLS state.
      if (input.active && user.banned_until && Date.parse(user.banned_until) > Date.now()) {
        const { error: unbanError } = await admin.auth.admin.updateUserById(user.id, { ban_duration: 'none' })
        if (unbanError) {
          return response({ error: 'El estado se guardó, pero no se pudo quitar el bloqueo anterior de Supabase. Volvé a activar la cuenta para reintentar.' }, 502)
        }
      }
      return response({ success: true })
    }

    if (input.action === 'set_role') {
      const email = cleanEmail(input.email)
      if (input.role !== 'USER' && input.role !== 'ADMIN') return response({ error: 'El rol solicitado no es válido.' }, 400)
      const user = await findUserByEmail(admin, email)
      if (!user) return response({ error: 'No existe una cuenta con ese correo.' }, 404)
      if (user.id === userData.user.id) {
        return response({ error: 'No podés cambiar tu propio rol desde esta cuenta.' }, 400)
      }

      const { error } = await caller.rpc('admin_set_user_role', {
        target_user_id: user.id,
        new_role: input.role,
      })
      if (error) return response({ error: error.message }, 400)
      return response({ success: true })
    }

    return response({ error: 'La acción solicitada no es válida.' }, 400)
  } catch (error) {
    const message = error instanceof Error ? error.message : 'Ocurrió un error al gestionar la cuenta.'
    return response({ error: message }, 400)
  }
})
