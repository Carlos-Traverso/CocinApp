import assert from 'node:assert/strict'
import test from 'node:test'
import { createRelationalAdminCatalog } from '../src/features/admin/data/relationalAdminCatalog'

type Row = Record<string, unknown>
function harness(seed: Record<string, Row[]> = {}) {
  const calls: Array<{ name: string; args?: Record<string, unknown> }> = []
  const versions = new Map<string, number>()
  for (const [table, rows] of Object.entries(seed)) {
    const kind = ({ categorias: 'category', unidades: 'unit', ingredientes: 'ingredient' } as const)[table as 'categorias' | 'unidades' | 'ingredientes']
    if (kind) for (const row of rows) versions.set(`admin_put_${kind}:${String(row.id)}`, Number(row.version ?? 1))
  }
  const fake = {
    auth: { getSession: async () => ({ data: { session: { access_token: 'token-a', user: { id: 'admin-1' } } }, error: null }) },
    rpc: async (name: string, args: Record<string, unknown>) => {
      calls.push({ name, args })
      if (name === 'current_app_role') return { data: 'ADMIN', error: null }
      const payload = args.p_entity as Row
      const id = String(payload.id)
      const key = `${name}:${id}`
      const expected = Number(args.p_expected_version)
      const actual = versions.get(key) ?? 0
      if (expected !== actual) return { data: null, error: { code: '40001', message: 'stale' } }
      const row = { ...payload, version: actual + 1 }
      versions.set(key, actual + 1)
      return { data: row, error: null }
    },
    from: (table: string) => {
      let id: string | undefined
      const query = {
        select: () => query,
        order: () => query,
        range: async () => ({ data: (seed[table] ?? []).map((row) => ({ ...row })), error: null }),
        eq: (_column: string, value: string) => { id = value; return query },
        maybeSingle: async () => ({ data: (seed[table] ?? []).find((row) => row.id === id) ?? null, error: null }),
      }
      calls.push({ name: `select:${table}` })
      return query
    },
  }
  return { repo: createRelationalAdminCatalog({ getClient: () => fake as never }), calls, versions }
}

test('catalog read includes archived rows and pages through relational tables', async () => {
  const { repo, calls } = harness({ categorias: [{ id: 'c1', name: 'Archivada', active: false, is_deleted: true, version: 4 }], unidades: [], ingredientes: [] })
  const core = await repo.getCatalogCore()
  assert.deepEqual(core.categories, [{ id: 'c1', name: 'Archivada', active: false, isDeleted: true }])
  assert.equal(calls.some(({ name }) => name === 'select:categorias'), true)
  assert.equal(calls.some(({ name }) => name === 'admin_list_catalog'), false)
})

test('create sends a stable UUID and expected version zero with SQL field names', async () => {
  const { repo, calls } = harness()
  const id = await repo.createIngredient(' Arroz ', 'cat-1', 'unit-1')
  const write = calls.find(({ name }) => name === 'admin_put_ingredient')
  assert.ok(write)
  assert.match(id, /^[0-9a-f-]{36}$/i)
  assert.deepEqual(write.args, { p_entity: { id, name: 'Arroz', category_id: 'cat-1', base_unit_id: 'unit-1', active: true, is_deleted: false }, p_expected_version: 0 })
})

test('archive and restore are versioned soft-delete writes', async () => {
  const category = { id: 'cat-1', name: 'Verduras', active: true, is_deleted: false, version: 3 }
  const { repo, calls } = harness({ categorias: [category] })
  await repo.getCatalogCore()
  assert.equal(await repo.deleteCategory('cat-1'), 'deactivated')
  const archive = calls.find(({ name }) => name === 'admin_put_category')
  assert.equal(archive?.args?.p_expected_version, 3)
  assert.deepEqual(archive?.args?.p_entity, { id: 'cat-1', name: 'Verduras', active: false, is_deleted: true })
  assert.equal(await repo.deleteCategory('missing'), 'not-found')
})

test('role is validated and SQL version conflicts are surfaced as reload guidance', async () => {
  const { repo, calls, versions } = harness({ categorias: [{ id: 'cat-1', name: 'Anterior', active: true, is_deleted: false, version: 4 }] })
  await repo.getCatalogCore()
  versions.set('admin_put_category:cat-1', 5)
  await assert.rejects(repo.updateCategory('cat-1', 'Editada'), /cambió desde que lo cargaste/)
  const write = calls.find(({ name }) => name === 'admin_put_category')
  assert.equal(write?.args?.p_expected_version, 4)
})
