import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import test from 'node:test'
import { runInNewContext } from 'node:vm'
import ts from 'typescript'

// Run the actual Edge handler with a fake Supabase transport and a delayed body
// parse so a role revocation can happen after initial authentication.
const source = readFileSync(new URL('../../backend/supabase/functions/admin-users/index.ts', import.meta.url), 'utf8')
const compiled = ts.transpileModule(source, {
  compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2023 },
}).outputText

type AdminAction =
  | { action: 'create'; name: string; email: string; password: string }
  | { action: 'update_name'; email: string; name: string }

function setup(onBodyRead: () => Promise<void>) {
  const calls: string[] = []
  let currentRole = 'ADMIN'
  let handler: ((request: Request) => Promise<Response>) | undefined
  const caller = {
    auth: { getUser: async () => ({ data: { user: { id: 'actor' } }, error: null }) },
    rpc: async (name: string) => {
      calls.push(name)
      return name === 'current_app_role' ? { data: currentRole, error: null } : { data: null, error: null }
    },
  }
  const admin = {
    auth: { admin: {
      listUsers: async () => ({ data: { users: [{ id: 'target', email: 'target@example.com', user_metadata: { name: 'Target' } }] }, error: null }),
      createUser: async () => {
        calls.push('createUser')
        return { data: { user: { id: 'created-user' } }, error: null }
      },
      updateUserById: async () => {
        calls.push('updateUserById')
        return { error: null }
      },
    } },
    from: (table: string) => ({
      select: () => ({ eq: () => ({ eq: () => ({ maybeSingle: async () => ({ data: { value: {} }, error: null }) }) }) }),
      upsert: async () => { calls.push(`${table}.upsert`); return { error: null } },
      insert: async () => { calls.push(`${table}.insert`); return { error: null } },
    }),
  }
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
    revokeAdmin: () => { currentRole = 'USER' },
    invoke: async (action: AdminAction) => {
      assert.ok(handler)
      const request = new Request('https://example.test/admin-users', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json', Authorization: 'Bearer test-token' },
        body: JSON.stringify(action),
      })
      Object.defineProperty(request, 'json', { value: async () => { await onBodyRead(); return action } })
      return handler(request)
    },
  }
}

function deferred() {
  let signalRead!: () => void
  let release!: () => void
  return {
    read: new Promise<void>((resolve) => { signalRead = resolve }),
    gate: new Promise<void>((resolve) => { release = resolve }),
    signalRead: () => signalRead(),
    release: () => release(),
  }
}

test('rejects create when administrator permissions are revoked before the action is admitted', async () => {
  const pause = deferred()
  const app = setup(async () => { pause.signalRead(); await pause.gate })
  const pending = app.invoke({ action: 'create', name: 'New user', email: 'new@example.com', password: 'secure-pass-123' })

  await pause.read
  app.revokeAdmin()
  pause.release()

  const result = await pending
  assert.equal(result.status, 403)
  assert.deepEqual(app.calls, ['current_app_role', 'current_app_role'])
})

test('rejects name update when administrator permissions are revoked before the first write', async () => {
  const pause = deferred()
  const app = setup(async () => { pause.signalRead(); await pause.gate })
  const pending = app.invoke({ action: 'update_name', email: 'target@example.com', name: 'Changed name' })

  await pause.read
  app.revokeAdmin()
  pause.release()

  const result = await pending
  assert.equal(result.status, 403)
  assert.equal(app.calls.includes('personal_data.upsert'), false)
  assert.equal(app.calls.includes('updateUserById'), false)
  assert.equal(app.calls.includes('admin_audit_log.insert'), false)
})

test('admits create and name update while the administrator still has the role at the final check', async () => {
  const create = setup(async () => {})
  const createResult = await create.invoke({ action: 'create', name: 'New user', email: 'new@example.com', password: 'secure-pass-123' })
  assert.equal(createResult.status, 200)
  assert.equal(create.calls.includes('createUser'), true)

  const update = setup(async () => {})
  const updateResult = await update.invoke({ action: 'update_name', email: 'target@example.com', name: 'Changed name' })
  assert.equal(updateResult.status, 200)
  assert.equal(update.calls.includes('personal_data.upsert'), true)
  assert.equal(update.calls.includes('updateUserById'), true)
})
