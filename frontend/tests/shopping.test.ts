import assert from 'node:assert/strict'
import test from 'node:test'
import { sampleRecipes } from '../src/mocks/recipes'
import { filterShoppingItems, mergeShoppingSuggestions, suggestForRecipes, suggestPantryRestock, type ShoppingItem } from '../src/features/shopping/domain/shopping'
import { appendShoppingSuggestions, markAllShoppingPurchased, readShoppingItems, setShoppingPurchased, transferPurchasedToPantry, writeShoppingItems } from '../src/features/shopping/data/localShoppingStore'
import { readPantryItems, writePantryItems } from '../src/features/pantry/data/localPantryStore'
import type { PantryItem } from '../src/features/pantry/domain/pantry'
import type { Recipe } from '../src/features/recipes/domain/Recipe'
import { getKnownRecipes } from '../src/features/recipes/data/availableRecipes'

const today = new Date(2026, 8, 23)
const pantry: PantryItem[] = [
  { id: 'rice', name: 'Arroz integral', category: 'Granos y legumbres', quantity: 200, unit: 'g', minimum: 300, expiry: '' },
  { id: 'chicken', name: 'Pechuga de pollo', category: 'Carnes y pescados', quantity: 100, unit: 'g', minimum: 200, expiry: '' },
  { id: 'oil', name: 'Aceite de oliva', category: 'Almacén', quantity: 100, unit: 'ml', minimum: 0, expiry: '' },
  { id: 'tomatoes', name: 'Tomates cherry', category: 'Frutas y verduras', quantity: 200, unit: 'g', minimum: 0, expiry: '2026-09-22' },
]

function shoppingItem(overrides: Partial<ShoppingItem> = {}): ShoppingItem {
  return { id: 'one', name: 'Arroz', category: 'Almacén', quantity: 200, unit: 'g', note: '', checked: false,
    transferredToPantry: false, transferredAt: null, sources: ['manual'], ...overrides }
}

test('recipe suggestions sum repeated ingredients before subtracting usable pantry stock once', () => {
  const recipe = sampleRecipes.find((item) => item.id === 'chicken-rice')!
  const suggestions = suggestForRecipes([recipe, recipe], pantry, 'plan', today)
  assert.equal(suggestions.find((item) => item.name === 'Arroz integral')?.quantity, 120)
  assert.equal(suggestions.find((item) => item.name === 'Pechuga de pollo')?.quantity, 500)
  assert.equal(suggestions.find((item) => item.name === 'Tomates cherry')?.quantity, 240)
  assert.equal(suggestions.some((item) => item.name === 'Aceite de oliva'), false)
})

test('weekly recipe suggestions preserve ingredient categories and only fall back when missing', () => {
  const recipe: Recipe = {
    id: 'mixed', name: 'Receta variada', description: '', category: 'Cena', minutes: 20, portions: 2,
    difficulty: 'Fácil', steps: ['Cocinar'], symbol: 'R', color: 'green', ingredients: [
      { name: 'Manzana', quantity: 2, unit: 'u', category: 'Frutas y verduras' },
      { name: 'Leche', quantity: 1, unit: 'l', category: 'Lácteos' },
      { name: 'Ingrediente desconocido', quantity: 1, unit: 'u' },
    ],
  }

  const suggestions = suggestForRecipes([recipe], [], 'plan', today)

  assert.equal(suggestions.find((item) => item.name === 'Manzana')?.category, 'Frutas y verduras')
  assert.equal(suggestions.find((item) => item.name === 'Leche')?.category, 'Lácteos')
  assert.equal(suggestions.find((item) => item.name === 'Ingrediente desconocido')?.category, 'Otros')
  assert.deepEqual(filterShoppingItems(suggestions.map((item, index) => shoppingItem({ ...item, id: String(index) })), { search: '', category: 'Lácteos', status: 'all' }).map((item) => item.name), ['Leche'])
})

test('the unified recipe repository supplies categories when planning without pantry stock', () => {
  const recipe = getKnownRecipes().find((item) => item.id === 'chicken-rice')!
  const suggestions = suggestForRecipes([recipe], [], 'plan', today)
  assert.equal(suggestions.find((item) => item.name === 'Pechuga de pollo')?.category, 'Carnes y pescados')
  assert.equal(suggestions.find((item) => item.name === 'Arroz integral')?.category, 'Granos y legumbres')
  assert.equal(suggestions.find((item) => item.name === 'Tomates cherry')?.category, 'Frutas y verduras')
})

test('merging repeated products promotes a specific category over Otros', () => {
  const current = [shoppingItem({ name: 'Leche', category: 'Otros', unit: 'l' })]
  const merged = mergeShoppingSuggestions(current, [{ name: 'Leche', category: 'Lácteos', quantity: 2, unit: 'l', source: 'plan' }])
  assert.equal(merged[0].category, 'Lácteos')
})

test('legacy shopping rows reconstruct a missing category and persist it after reload', () => {
  const entries = new Map<string, string>()
  const storage = { getItem: (key: string) => entries.get(key) ?? null, setItem: (key: string, value: string) => { entries.set(key, value) } }
  const legacy = { id: 'milk', name: 'Leche', quantity: 1, unit: 'l', note: '', checked: false, sources: ['plan'] }
  entries.set('cocinapp.shopping.v1', JSON.stringify([legacy]))

  const migrated = readShoppingItems(storage)
  assert.equal(migrated[0]?.category, 'Lácteos')
  writeShoppingItems(migrated, storage)
  assert.equal(readShoppingItems(storage)[0]?.category, 'Lácteos')
})

test('pantry restock suggests low, empty and expired products without duplicates', () => {
  const suggestions = suggestPantryRestock([...pantry, { ...pantry[0], id: 'rice-2', quantity: 50 }], today)
  assert.equal(suggestions.find((item) => item.name === 'Arroz integral')?.quantity, 50)
  assert.equal(suggestions.find((item) => item.name === 'Pechuga de pollo')?.quantity, 100)
  assert.equal(suggestions.find((item) => item.name === 'Tomates cherry')?.quantity, 200)
  assert.equal(suggestions.some((item) => item.name === 'Aceite de oliva'), false)
})

test('merging suggestions is idempotent and preserves edits and checked state', () => {
  const current: ShoppingItem[] = [shoppingItem({ name: 'Arroz integral', category: 'Granos y legumbres', quantity: 80, note: 'Marca habitual', checked: true })]
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
  const item = shoppingItem()
  writeShoppingItems([item], storage)
  assert.deepEqual(readShoppingItems(storage), [item])
  entries.set('cocinapp.shopping.v1', JSON.stringify([item, { ...item, id: 'bad', quantity: -1 }]))
  assert.deepEqual(readShoppingItems(storage), [item])
  entries.set('cocinapp.shopping.v1', '{bad')
  assert.deepEqual(readShoppingItems(storage), [])
})

test('category, search and status filters combine and return an empty result when nothing matches', () => {
  const items: ShoppingItem[] = [
    shoppingItem({ id: 'milk', name: 'Leche', category: 'Lácteos', quantity: 1, unit: 'l' }),
    shoppingItem({ id: 'yogurt', name: 'Yogur', category: 'Lácteos', quantity: 1, unit: 'u', checked: true }),
    shoppingItem({ id: 'apple', name: 'Manzana', category: 'Frutas y verduras', quantity: 2, unit: 'u' }),
  ]
  assert.deepEqual(filterShoppingItems(items, { search: 'LECHE', category: 'Lácteos', status: 'pending' }).map((item) => item.id), ['milk'])
  assert.deepEqual(filterShoppingItems(items, { search: '', category: 'Lácteos', status: 'checked' }).map((item) => item.id), ['yogurt'])
  assert.deepEqual(filterShoppingItems(items, { search: 'manzana', category: 'Lácteos', status: 'all' }), [])
  assert.equal(filterShoppingItems(items, { search: '', category: '', status: 'all' }).length, 3)
})

test('individual and bulk purchase marking persist without transferring to pantry', () => {
  const entries = new Map<string, string>()
  const storage = { getItem: (key: string) => entries.get(key) ?? null, setItem: (key: string, value: string) => { entries.set(key, value) } }
  writeShoppingItems([shoppingItem({ id: 'milk', name: 'Leche', category: 'Lácteos', quantity: 2, unit: 'l' }), shoppingItem({ id: 'apple', name: 'Manzana', unit: 'u' })], storage)
  setShoppingPurchased('milk', true, storage)
  assert.equal(readPantryItems(storage).length, 0)
  assert.equal(readShoppingItems(storage)[0].checked, true)
  assert.equal(markAllShoppingPurchased(storage).every((item) => item.checked), true)
  assert.equal(readPantryItems(storage).length, 0)
})

test('only purchased items transfer once; compatible stock combines and incompatible units remain separate', () => {
  const entries = new Map<string, string>()
  const storage = { getItem: (key: string) => entries.get(key) ?? null, setItem: (key: string, value: string) => { entries.set(key, value) } }
  writePantryItems([{ id: 'rice', name: 'Arroz', category: 'Almacén', quantity: 500, unit: 'g', minimum: 100, expiry: '2027-01-01' }], storage)
  writeShoppingItems([
    shoppingItem({ id: 'kg', name: 'Arroz', quantity: 1, unit: 'kg', checked: true }),
    shoppingItem({ id: 'units', name: 'Arroz', quantity: 2, unit: 'u', checked: true }),
    shoppingItem({ id: 'pending', name: 'Sal', quantity: 1, unit: 'u' }),
  ], storage)
  const first = transferPurchasedToPantry(storage, new Date('2026-09-28T12:00:00Z'))
  assert.equal(first.transferredCount, 2)
  assert.equal(first.removedCount, 2)
  assert.equal(readPantryItems(storage).length, 2)
  assert.equal(readPantryItems(storage)[0].quantity, 1500)
  assert.equal(readPantryItems(storage)[0].expiry, '2027-01-01')
  assert.equal(readPantryItems(storage)[1].unit, 'u')
  assert.equal(readPantryItems(storage).some((item) => item.name === 'Sal'), false)
  assert.deepEqual(readShoppingItems(storage).map((item) => item.id), ['pending'])
  assert.equal(transferPurchasedToPantry(storage).transferredCount, 0)
  assert.equal(readPantryItems(storage)[0].quantity, 1500)
  setShoppingPurchased('pending', false, storage)
  assert.equal(readPantryItems(storage)[0].quantity, 1500)
})

test('a failed shopping removal restores pantry and keeps every purchase retryable', () => {
  const entries = new Map<string, string>()
  let shoppingWrites = 0
  const storage = {
    getItem: (key: string) => entries.get(key) ?? null,
    setItem: (key: string, value: string) => {
      if (key === 'cocinapp.shopping.v1' && shoppingWrites++ === 1) throw new Error('quota')
      entries.set(key, value)
    },
  }
  writeShoppingItems([
    shoppingItem({ id: 'milk', name: 'Leche', category: 'Lácteos', quantity: 2, unit: 'l', checked: true }),
    shoppingItem({ id: 'apple', name: 'Manzana', category: 'Frutas y verduras', quantity: 4, unit: 'u', checked: true }),
  ], storage)

  assert.throws(() => transferPurchasedToPantry(storage), /transferencia/i)
  assert.deepEqual(readPantryItems(storage), [])
  assert.deepEqual(readShoppingItems(storage).map((item) => item.id), ['milk', 'apple'])
})

test('successful transfers persist an empty shopping state after reload', () => {
  const entries = new Map<string, string>()
  const storage = { getItem: (key: string) => entries.get(key) ?? null, setItem: (key: string, value: string) => { entries.set(key, value) } }
  writeShoppingItems([shoppingItem({ id: 'milk', name: 'Leche', category: 'Lácteos', quantity: 2, unit: 'l', checked: true })], storage)

  const result = transferPurchasedToPantry(storage, new Date('2026-09-28T12:00:00Z'))

  assert.deepEqual(result.items, [])
  assert.equal(result.transferredCount, 1)
  assert.equal(result.removedCount, 1)
  assert.deepEqual(readShoppingItems(storage), [])
  assert.equal(readPantryItems(storage)[0].name, 'Leche')
  assert.equal(readPantryItems(storage)[0].category, 'Lácteos')
})

test('new pantry products use a null expiry and legacy checked items are not assumed transferred', () => {
  const entries = new Map<string, string>()
  const storage = { getItem: (key: string) => entries.get(key) ?? null, setItem: (key: string, value: string) => { entries.set(key, value) } }
  const legacy = { id: 'milk', name: 'Leche', category: 'Lácteos', quantity: 2, unit: 'l', note: '', checked: true, sources: ['manual'] }
  entries.set('cocinapp.shopping.v1', JSON.stringify([legacy]))
  assert.equal(readShoppingItems(storage)[0].transferredToPantry, false)
  transferPurchasedToPantry(storage)
  assert.equal(readPantryItems(storage)[0].expiry, null)
  assert.deepEqual(readPantryItems(storage)[0].sourceShoppingIds, ['milk'])
  assert.deepEqual(readShoppingItems(storage), [])
})
