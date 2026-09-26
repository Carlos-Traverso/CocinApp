import assert from 'node:assert/strict'
import test from 'node:test'
import { countPantryAlerts, filterPantryItems, getPantryStatus, hasDuplicateItem, type PantryItem } from '../src/features/pantry/domain/pantry'
import { readPantryItems, writePantryItems } from '../src/features/pantry/data/localPantryStore'

const today = new Date(2026, 8, 23)
const rice: PantryItem = {
  id: 'rice', name: 'Arroz integral', category: 'Granos y legumbres',
  quantity: 500, unit: 'g', minimum: 200, expiry: '',
}

test('classifies expiry by local calendar days and keeps stock alerts independent', () => {
  assert.equal(getPantryStatus({ ...rice, expiry: '2026-09-22' }, today).kind, 'expired')
  assert.equal(getPantryStatus({ ...rice, expiry: '2026-09-23' }, today).kind, 'soon')
  assert.equal(getPantryStatus({ ...rice, expiry: '2026-09-26' }, today).kind, 'soon')
  assert.equal(getPantryStatus({ ...rice, expiry: '2026-09-27' }, today).kind, 'ok')
  assert.equal(getPantryStatus({ ...rice, quantity: 0, expiry: '2026-09-27' }, today).kind, 'empty')
  assert.equal(getPantryStatus({ ...rice, quantity: 100 }, today).kind, 'low')
})

test('summary separates past dates from today and upcoming dates without double counting', () => {
  const items = [
    { ...rice, id: 'past', expiry: '2026-09-22' },
    { ...rice, id: 'today', expiry: '2026-09-23' },
    { ...rice, id: 'soon', expiry: '2026-09-25' },
    { ...rice, id: 'none', expiry: '' },
  ]
  assert.deepEqual(countPantryAlerts(items, today), { low: 0, expired: 1, soon: 2 })
  assert.deepEqual(filterPantryItems(items, { search: '', category: '', status: 'expired' }, today).map((item) => item.id), ['past'])
  assert.deepEqual(filterPantryItems(items, { search: '', category: '', status: 'soon' }, today).map((item) => item.id), ['today', 'soon'])
})

test('filters accent-insensitively, including empty items in low stock', () => {
  const items = [rice, { ...rice, id: '2', name: 'Lácteos', quantity: 0, category: 'Lácteos' as const }]
  assert.deepEqual(filterPantryItems(items, { search: 'lacteos', category: '', status: '' }, today).map((item) => item.id), ['2'])
  assert.deepEqual(filterPantryItems(items, { search: '', category: '', status: 'low' }, today).map((item) => item.id), ['2'])
  assert.equal(hasDuplicateItem(items, { ...rice, id: 'new', name: ' ARROZ  INTEGRAL ' }), true)
  assert.equal(hasDuplicateItem(items, { ...rice, id: 'new', unit: 'u' }), false)
})

test('persists valid items and ignores malformed stored entries', () => {
  const entries = new Map<string, string>()
  const storage = {
    getItem: (key: string) => entries.get(key) ?? null,
    setItem: (key: string, value: string) => { entries.set(key, value) },
  }
  writePantryItems([rice], storage)
  assert.deepEqual(readPantryItems(storage), [rice])
  entries.set('cocinapp.pantry.v1', JSON.stringify([rice, { ...rice, id: 'bad', quantity: -1 }]))
  assert.deepEqual(readPantryItems(storage), [rice])
})

test('migrates existing prototype data without replacing an intentionally empty pantry', () => {
  const entries = new Map<string, string>([['cocinapp-demo-pantry-v1', JSON.stringify([rice])]])
  const storage = {
    getItem: (key: string) => entries.get(key) ?? null,
    setItem: (key: string, value: string) => { entries.set(key, value) },
  }
  assert.deepEqual(readPantryItems(storage), [rice])
  assert.deepEqual(JSON.parse(entries.get('cocinapp.pantry.v1') ?? ''), [rice])
  entries.set('cocinapp.pantry.v1', '[]')
  assert.deepEqual(readPantryItems(storage), [])
})
