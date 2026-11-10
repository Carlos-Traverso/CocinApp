import assert from 'node:assert/strict'
import test from 'node:test'
import { createSupabasePantryRepository, toRelationalPantrySnapshot } from '../src/features/pantry/data/supabasePantryRepository'

test('relational snapshot keeps stable ids and leaves manual catalog links empty', () => {
  const item = {
    id: 'stable-item-uuid', name: '  Arroz  integral ', category: 'Almacén',
    quantity: 2.25, unit: 'kg', minimum: 0.5, expiry: '', sourceShoppingIds: ['shopping-source'],
  }
  assert.deepEqual(toRelationalPantrySnapshot(item), {
    id: 'stable-item-uuid', name: 'Arroz  integral', category: 'Almacén',
    quantity: 2.25, unit: 'kg', minimum: 0.5, expiry: null, ingredient_id: null,
  })
})

test('relational snapshot preserves an explicit relational reference and its legacy key', () => {
  assert.deepEqual(toRelationalPantrySnapshot({
    id: 'stable-item-uuid', ingredientId: 'legacy-rice', ingredientRef: 'relational-rice-uuid',
    name: 'Arroz', category: 'Almacén', quantity: 1, unit: 'kg', minimum: 0, expiry: null,
  }), {
    id: 'stable-item-uuid', ingredient_id: 'legacy-rice', ingredient_ref: 'relational-rice-uuid',
    name: 'Arroz', category: 'Almacén', quantity: 1, unit: 'kg', minimum: 0, expiry: null,
  })
})

function makeRepo(rows: Array<Record<string, unknown>>) {
  const calls: Array<{ name: string; args: Record<string, unknown> }> = []
  const fake = {
    auth: { getUser: async () => ({ data: { user: { id: 'user-1' } }, error: null }) },
    rpc: async (name: string, args: Record<string, unknown>) => {
      calls.push({ name, args })
      if (name === 'get_my_pantry') return { data: { items: rows.map((row) => ({ ...row })), total: rows.length, limit: 100, offset: 0, as_of: '2026-11-06' }, error: null }
      if (name === 'put_my_pantry_items') {
        const entries = args.p_items as Array<{ item: Record<string, unknown>; expected_version: number }>
        return { data: entries.map(({ item, expected_version }) => ({ ...item, version: expected_version + 1, ingredient_ref: item.ingredient_ref ?? null, source_shopping_ids: [] })), error: null }
      }
      return { data: true, error: null }
    },
  }
  const session = { token: 'supabase-user:user-1', localRevision: 1, supabaseRevision: 1 }
  const repo = createSupabasePantryRepository({
    getClient: () => fake as never,
    captureSession: () => session,
    assertOwner: (_session, userId) => { assert.equal(userId, 'user-1') },
    assertSession: () => undefined,
    storage: { getItem: () => null, setItem: () => {} } as Storage,
  })
  return { repo, calls }
}

function row(id: string, version: number) {
  return { id, ingredient_id: null, ingredient_ref: null, name: 'Arroz', category: 'Almacén', quantity: 1, unit: 'kg', minimum: 0, expiry: null, source_shopping_ids: [], version }
}

test('relational repository lists then sends an optimistic version and keeps stable id', async () => {
  const { repo, calls } = makeRepo([row('stable-uuid', 7)])
  const items = await repo.list()
  items[0]!.quantity = 2
  await repo.save(items)
  const write = calls.find((call) => call.name === 'put_my_pantry_items')
  assert.ok(write)
  const [entry] = write.args.p_items as Array<{ item: { id: string }; expected_version: number }>
  assert.equal(entry?.item.id, 'stable-uuid')
  assert.equal(entry?.expected_version, 7)
  assert.equal(items[0]?.version, 8)
})

test('relational repository rejects a mixed update and deletion before writing', async () => {
  const { repo, calls } = makeRepo([row('keep-uuid', 2), row('remove-uuid', 4)])
  const items = await repo.list()
  items[0]!.quantity = 5
  await assert.rejects(repo.save([items[0]!]), /eliminación por vez/)
  assert.equal(calls.some((call) => call.name === 'put_my_pantry_items' || call.name === 'delete_my_pantry_item'), false)
})

test('relational conflict rejects stale save and a fresh list supplies the next expected version', async () => {
  let version = 3
  let rejectWrite = true
  const fake = {
    auth: { getUser: async () => ({ data: { user: { id: 'user-1' } }, error: null }) },
    rpc: async (name: string, args: Record<string, unknown>) => {
      if (name === 'get_my_pantry') return { data: { items: [row('item-uuid', version)], total: 1, limit: 100, offset: 0, as_of: '2026-11-06' }, error: null }
      const entry = (args.p_items as Array<{ item: Record<string, unknown>; expected_version: number }>)[0]!
      if (rejectWrite) { rejectWrite = false; return { data: null, error: { code: '40001', message: 'conflict' } } }
      assert.equal(entry.expected_version, version)
      version += 1
      return { data: [{ ...entry.item, version, ingredient_ref: null, source_shopping_ids: [] }], error: null }
    },
  }
  const session = { token: 'supabase-user:user-1', localRevision: 1, supabaseRevision: 1 }
  const repo = createSupabasePantryRepository({ getClient: () => fake as never, captureSession: () => session,
    assertOwner: (_session, id) => assert.equal(id, 'user-1'), assertSession: () => undefined,
    storage: { getItem: () => null, setItem: () => {} } as Storage })
  const stale = await repo.list()
  stale[0]!.quantity = 2
  await assert.rejects(repo.save(stale), (error: { code?: string }) => error.code === '40001')
  const current = await repo.list()
  current[0]!.quantity = 3
  await repo.save(current)
  assert.equal(current[0]?.version, 4)
})

function deferred<T>() {
  let resolve!: (value: T) => void
  const promise = new Promise<T>((done) => { resolve = done })
  return { promise, resolve }
}

test('pending pantry reads cannot publish after the session changes', async () => {
  let revision = 1
  let writes = 0
  const pending = deferred<{ data: unknown; error: null }>()
  const entered = deferred<void>()
  const fake = { auth: { getUser: async () => ({ data: { user: { id: 'user-1' } }, error: null }) },
    rpc: () => { entered.resolve(); return pending.promise } }
  const repo = createSupabasePantryRepository({ getClient: () => fake as never,
    captureSession: () => ({ token: 'supabase-user:user-1', localRevision: revision, supabaseRevision: revision }),
    assertSession: () => {}, assertOwner: (session) => { assert.equal(session.localRevision, revision, 'session changed') },
    storage: { getItem: () => null, setItem: () => { writes++ } } as Storage })
  const loading = repo.list()
  const rejected = assert.rejects(loading, /session changed/)
  await entered.promise
  revision++
  pending.resolve({ data: { items: [row('old-account-item', 1)], total: 1 }, error: null })
  await rejected
  assert.equal(writes, 0)
  await assert.rejects(repo.save([]), /Recargá/)
})

test('an older pantry read cannot overwrite a newer completed read', async () => {
  const first = deferred<{ data: unknown; error: null }>()
  const entered = deferred<void>()
  let reads = 0
  const stored: string[] = []
  const session = { token: 'supabase-user:user-1', localRevision: 1, supabaseRevision: 1 }
  const fake = { auth: { getUser: async () => ({ data: { user: { id: 'user-1' } }, error: null }) },
    rpc: () => { if (++reads === 1) { entered.resolve(); return first.promise }
      return Promise.resolve({ data: { items: [row('newest-item', 2)], total: 1 }, error: null }) } }
  const repo = createSupabasePantryRepository({ getClient: () => fake as never, captureSession: () => session,
    assertOwner: () => {}, assertSession: () => {},
    storage: { getItem: () => null, setItem: (_key: string, value: string) => { stored.push(value) } } as Storage })
  const old = repo.list()
  const rejected = assert.rejects(old, /carga de despensa cambió/)
  await entered.promise
  assert.equal((await repo.list())[0]?.id, 'newest-item')
  first.resolve({ data: { items: [row('obsolete-item', 1)], total: 1 }, error: null })
  await rejected
  assert.equal(stored.length, 1)
  assert.match(stored[0]!, /newest-item/)
})
