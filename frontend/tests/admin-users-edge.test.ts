import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import test from 'node:test'
import { runInNewContext } from 'node:vm'
import ts from 'typescript'

// Execute the actual Edge handler with fake Supabase transports. These tests
// verify integration and failure handling; database concurrency has SQL tests.
const source = readFileSync(new URL('../../backend/supabase/functions/admin-users/index.ts', import.meta.url), 'utf8')
const compiled = ts.transpileModule(source, {
  compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2023 },
}).outputText

function setup(options: { role?: string; rejectRpc?: boolean; legacyBan?: boolean; rejectUnban?: boolean } = {}) {
  const calls: string[] = []
  let handler: ((request: Request) => Promise<Response>) | undefined
  const caller = {
    auth: { getUser: async () => ({ data: { user: { id: 'actor' } }, error: null }) },
    rpc: async (name: string, args?: Record<string, unknown>) => {
      calls.push(`${name}:${JSON.stringify(args ?? {})}`)
      if (name === 'current_app_role') return { data: options.role ?? 'ADMIN', error: null }
      return { data: null, error: options.rejectRpc ? { message: 'Operación rechazada por permisos.' } : null }
    },
  }
  const admin = { auth: { admin: {
    listUsers: async () => ({ data: { users: [{ id: 'target', email: 'target@example.com', banned_until: options.legacyBan ? '2999-01-01T00:00:00Z' : null }] }, error: null }),
    updateUserById: async (_id: string, args: Record<string, unknown>) => {
      calls.push(`updateUserById:${JSON.stringify(args)}`)
      return { error: options.rejectUnban ? { message: 'Auth unavailable' } : null }
    },
  } } }
  let clients = 0
  runInNewContext(compiled, {
    exports: {}, Request, Response, Date,
    require: (name: string) => {
      assert.equal(name, 'https://esm.sh/@supabase/supabase-js@2')
      return { createClient: () => ++clients === 1 ? caller : admin }
    },
    Deno: {
      env: { get: (name: string) => ['SUPABASE_URL', 'SUPABASE_ANON_KEY', 'SUPABASE_SERVICE_ROLE_KEY'].includes(name) ? 'test-value' : undefined },
      serve: (callback: typeof handler) => { handler = callback },
    },
  })
  return {
    calls,
    invoke: async (active: unknown, authorized = true) => {
      assert.ok(handler)
      return handler(new Request('https://example.test/admin-users', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json', ...(authorized ? { Authorization: 'Bearer test-token' } : {}) },
        body: JSON.stringify({ action: 'set_active', email: 'target@example.com', active }),
      }))
    },
  }
}

test('deactivation delegates to atomic caller RPC and never issues a separate Auth ban', async () => {
  const { calls, invoke } = setup()
  assert.equal((await invoke(false)).status, 200)
  assert.deepEqual(calls, ['current_app_role:{}', 'admin_set_user_active:{"target_user_id":"target","new_active":false}'])
})

test('database rejection never falls through to clearing a legacy ban', async () => {
  const { calls, invoke } = setup({ rejectRpc: true, legacyBan: true })
  assert.equal((await invoke(true)).status, 400)
  assert.equal(calls.some((call) => call.startsWith('updateUserById:')), false)
})

test('legacy reactivation clears Auth ban only after atomic state change', async () => {
  const { calls, invoke } = setup({ legacyBan: true })
  assert.equal((await invoke(true)).status, 200)
  assert.deepEqual(calls.slice(1), ['admin_set_user_active:{"target_user_id":"target","new_active":true}', 'updateUserById:{"ban_duration":"none"}'])
})

test('legacy unban failure reports partial completion and permits a retry', async () => {
  const { calls, invoke } = setup({ legacyBan: true, rejectUnban: true })
  const result = await invoke(true)
  assert.equal(result.status, 502)
  assert.match((await result.json()).error, /estado se guardó.*reintentar/)
  assert.equal(calls.length, 3)
})

test('unauthenticated, non-admin and malformed requests cannot mutate account state', async () => {
  const unauthenticated = setup()
  assert.equal((await unauthenticated.invoke(false, false)).status, 401)
  assert.equal(unauthenticated.calls.length, 0)
  const user = setup({ role: 'USER' })
  assert.equal((await user.invoke(false)).status, 403)
  assert.equal(user.calls.length, 1)
  const malformed = setup()
  assert.equal((await malformed.invoke('false')).status, 400)
  assert.equal(malformed.calls.length, 1)
})
