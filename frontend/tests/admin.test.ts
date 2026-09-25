const mockStorage = new Map()
global.localStorage = {
  getItem: (k) => mockStorage.get(k) || null,
  setItem: (k, v) => mockStorage.set(k, v),
  clear: () => mockStorage.clear(),
  removeItem: (k) => mockStorage.delete(k)
} as any
global.window = { dispatchEvent: () => {} } as any

import assert from 'node:assert'
import test, { describe, beforeEach } from 'node:test'
import { getAdminData, saveAdminData } from '../src/features/admin/data/localAdminStore'
import { createCategory, deleteCategory } from '../src/features/admin/data/categoriesStore'

describe('Admin Stores', () => {
  beforeEach(() => {
    localStorage.clear()
    saveAdminData({ categories: [], units: [], ingredients: [], recipes: [] })
  })

  test('creates a category and persists it', () => {
    const id = createCategory('Lácteos')
    const data = getAdminData()
    assert.strictEqual(data.categories.length, 1)
    assert.strictEqual(data.categories[0].name, 'Lácteos')
    assert.strictEqual(data.categories[0].isDeleted, false)
    assert.strictEqual(data.categories[0].id, id)
  })

  test('prevents creating duplicate categories', () => {
    createCategory('Lácteos')
    assert.throws(() => createCategory('lácteos'), /La categoría ya existe/)
  })

  test('performs physical delete when no references exist', () => {
    const id = createCategory('Especias')
    deleteCategory(id, false)
    const data = getAdminData()
    assert.strictEqual(data.categories.length, 0)
  })

  test('performs logical delete when references exist', () => {
    const id = createCategory('Carnes')
    deleteCategory(id, true)
    const data = getAdminData()
    assert.strictEqual(data.categories.length, 1)
    assert.strictEqual(data.categories[0].isDeleted, true)
  })
})

