import assert from 'node:assert/strict'
import test from 'node:test'
import { sampleRecipes } from '../src/mocks/recipes'
import { filterShoppingItems, mergeShoppingSuggestions, suggestForRecipes, suggestPantryRestock, type ShoppingItem } from '../src/features/shopping/domain/shopping'
import { appendShoppingSuggestions, readShoppingItems, setShoppingPurchased, writeShoppingItems } from '../src/features/shopping/data/localShoppingStore'
import { readPantryItems, writePantryItems } from '../src/features/pantry/data/localPantryStore'
import type { PantryItem } from '../src/features/pantry/domain/pantry'

const today = new Date(2026, 8, 23)
const pantry: PantryItem[] = [
  { id: 'rice', name: 'Arroz integral', category: 'Granos y legumbres', quantity: 200, unit: 'g', minimum: 300, expiry: '' },
  { id: 'chicken', name: 'Pechuga de pollo', category: 'Carnes y pescados', quantity: 100, unit: 'g', minimum: 200, expiry: '' },
  { id: 'oil', name: 'Aceite de oliva', category: 'Almacén', quantity: 100, unit: 'ml', minimum: 0, expiry: '' },
  { id: 'tomatoes', name: 'Tomates cherry', category: 'Frutas y verduras', quantity: 200, unit: 'g', minimum: 0, expiry: '2026-09-22' },
]

test('recipe suggestions sum repeated ingredients before subtracting usable pantry stock once', () => {
  const recipe = sampleRecipes.find((item) => item.id === 'chicken-rice')!
  const suggestions = suggestForRecipes([recipe, recipe], pantry, 'plan', today)
  assert.equal(suggestions.find((item) => item.name === 'Arroz integral')?.quantity, 120)
  assert.equal(suggestions.find((item) => item.name === 'Pechuga de pollo')?.quantity, 500)
  assert.equal(suggestions.find((item) => item.name === 'Tomates cherry')?.quantity, 240)
  assert.equal(suggestions.some((item) => item.name === 'Aceite de oliva'), false)
})

test('pantry restock suggests low, empty and expired products without duplicates', () => {
  const suggestions = suggestPantryRestock([...pantry, { ...pantry[0], id: 'rice-2', quantity: 50 }], today)
  assert.equal(suggestions.find((item) => item.name === 'Arroz integral')?.quantity, 50)
  assert.equal(suggestions.find((item) => item.name === 'Pechuga de pollo')?.quantity, 100)
  assert.equal(suggestions.find((item) => item.name === 'Tomates cherry')?.quantity, 200)
  assert.equal(suggestions.some((item) => item.name === 'Aceite de oliva'), false)
})

test('merging suggestions is idempotent and preserves edits and checked state', () => {
  const current: ShoppingItem[] = [{ id: 'one', name: 'Arroz integral', category: 'Granos y legumbres', quantity: 80, unit: 'g', note: 'Marca habitual', checked: true, sources: ['manual'] }]
  const suggestions = [{ name: ' arroz  INTEGRAL ', category: 'Granos y legumbres' as const, quantity: 120, unit: 'g' as const, source: 'plan' as const }]
  const merged = mergeShoppingSuggestions(current, suggestions)
  assert.deepEqual(merged, [{ ...current[0], quantity: 120, sources: ['manual', 'plan'] }])
  assert.deepEqual(mergeShoppingSuggestions(merged, suggestions), merged)
})

test('sending recipe faltantes twice keeps one row per ingredient and the correct quantity', () => {
  const entries = new Map<string, string>()
  const storage = { getItem: (key: string) => entries.get(key) ?? null, setItem: (key: string, value: string) => { entries.set(key, value) } }
  const recipe = sampleRecipes.find((item) => item.id === 'chicken-rice')!
  const missing = suggestForRecipes([recipe], pantry, 'recipe', today)
  const first = appendShoppingSuggestions(missing, storage)
  const second = appendShoppingSuggestions(missing, storage)
  assert.deepEqual(second, first)
  assert.equal(second.length, missing.length)
  assert.equal(second.find((item) => item.name === 'Pechuga de pollo')?.quantity, 200)
})

test('shopping storage persists valid items and ignores malformed records', () => {
  const entries = new Map<string, string>()
  const storage = { getItem: (key: string) => entries.get(key) ?? null, setItem: (key: string, value: string) => { entries.set(key, value) } }
  const item: ShoppingItem = { id: 'one', name: 'Arroz', category: 'Almacén', quantity: 200, unit: 'g', note: '', checked: false, sources: ['manual'] }
  writeShoppingItems([item], storage)
  assert.deepEqual(readShoppingItems(storage), [item])
  entries.set('cocinapp.shopping.v1', JSON.stringify([item, { ...item, id: 'bad', quantity: -1 }]))
  assert.deepEqual(readShoppingItems(storage), [item])
  entries.set('cocinapp.shopping.v1', '{bad')
  assert.deepEqual(readShoppingItems(storage), [])
})

test('category, search and status filters combine and return an empty result when nothing matches', () => {
  const items: ShoppingItem[] = [
    { id: 'milk', name: 'Leche', category: 'Lácteos', quantity: 1, unit: 'l', note: '', checked: false, sources: ['manual'] },
    { id: 'yogurt', name: 'Yogur', category: 'Lácteos', quantity: 1, unit: 'u', note: '', checked: true, sources: ['manual'] },
    { id: 'apple', name: 'Manzana', category: 'Frutas y verduras', quantity: 2, unit: 'u', note: '', checked: false, sources: ['manual'] },
  ]
  assert.deepEqual(filterShoppingItems(items, { search: 'LECHE', category: 'Lácteos', status: 'pending' }).map((item) => item.id), ['milk'])
  assert.deepEqual(filterShoppingItems(items, { search: '', category: 'Lácteos', status: 'checked' }).map((item) => item.id), ['yogurt'])
  assert.deepEqual(filterShoppingItems(items, { search: 'manzana', category: 'Lácteos', status: 'all' }), [])
  assert.equal(filterShoppingItems(items, { search: '', category: '', status: 'all' }).length, 3)
})

test('purchased items transfer once, persist, and remain after unchecking', () => {
  const entries = new Map<string, string>()
  const storage = { getItem: (key: string) => entries.get(key) ?? null, setItem: (key: string, value: string) => { entries.set(key, value) } }
  const purchase: ShoppingItem = { id: 'milk', name: 'Leche', category: 'Lácteos', quantity: 2, unit: 'l', note: '', checked: false, sources: ['manual'] }
  writeShoppingItems([purchase], storage)
  setShoppingPurchased('milk', true, storage)
  assert.equal(readPantryItems(storage)[0].quantity, 2)
  assert.equal(readPantryItems(storage)[0].expiry, '')
  setShoppingPurchased('milk', false, storage)
  assert.equal(readPantryItems(storage).length, 1)
  setShoppingPurchased('milk', true, storage)
  assert.equal(readPantryItems(storage)[0].quantity, 2)
  assert.equal(readShoppingItems(storage)[0].transferred, true)
})

test('existing compatible stock combines quantities and incompatible units remain separate', () => {
  const entries = new Map<string, string>()
  const storage = { getItem: (key: string) => entries.get(key) ?? null, setItem: (key: string, value: string) => { entries.set(key, value) } }
  writePantryItems([{ id: 'rice', name: 'Arroz', category: 'Almacén', quantity: 500, unit: 'g', minimum: 100, expiry: '2027-01-01' }], storage)
  writeShoppingItems([
    { id: 'kg', name: 'Arroz', category: 'Almacén', quantity: 1, unit: 'kg', note: '', checked: false, sources: ['manual'] },
    { id: 'units', name: 'Arroz', category: 'Almacén', quantity: 2, unit: 'u', note: '', checked: false, sources: ['manual'] },
  ], storage)
  setShoppingPurchased('kg', true, storage)
  assert.equal(readPantryItems(storage)[0].quantity, 1500)
  assert.equal(readPantryItems(storage)[0].expiry, '2027-01-01')
  setShoppingPurchased('units', true, storage)
  assert.equal(readPantryItems(storage).length, 2)
  assert.equal(readPantryItems(storage)[1].unit, 'u')
})
