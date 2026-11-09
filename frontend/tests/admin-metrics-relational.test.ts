import assert from 'node:assert/strict'
import test from 'node:test'
import type { AdminRecipe } from '../src/features/admin/domain/adminModels.ts'
import type { AdminStorageData } from '../src/features/admin/data/localAdminStore.ts'
import { createAdminDashboard } from '../src/features/admin/domain/adminDashboard.ts'

function recipe(id: string, overrides: Partial<AdminRecipe> = {}): AdminRecipe {
  return {
    id, title: id, author: 'CocinAPP', description: '', category: 'Cena', minutes: 20, portions: 2,
    difficulty: 'Fácil', calories: 100, mealShift: 'Cena', dietaryTags: [], ingredients: [{ ingredientId: 'i', quantity: 1, unitId: 'u' }],
    steps: ['Cocinar'], status: 'published', active: true, isDeleted: false, featured: false, symbol: 'R', color: 'green',
    ...overrides,
  }
}

test('admin overview counts the complete official set, including drafts and inactive recipes', () => {
  const data: AdminStorageData = {
    recipes: [
      recipe('published', { image: '/published.webp' }),
      recipe('draft', { status: 'draft', active: true, image: undefined }),
      recipe('inactive', { active: false, featured: true }),
      recipe('archived', { isDeleted: true }),
    ],
    ingredients: [], categories: [], units: [],
  }

  const dashboard = createAdminDashboard(data)

  assert.deepEqual(dashboard.metrics, { total: 4, active: 1, inactive: 3, featured: 0 })
  assert.equal(dashboard.alerts.drafts, 1)
  assert.equal(dashboard.alerts.missingImage, 2)
})

test('admin overview does not count a draft or inactive official recipe as active', () => {
  const dashboard = createAdminDashboard({
    recipes: [recipe('draft', { status: 'draft' }), recipe('inactive', { active: false })],
    ingredients: [], categories: [], units: [],
  })

  assert.equal(dashboard.metrics.total, 2)
  assert.equal(dashboard.metrics.active, 0)
  assert.equal(dashboard.metrics.inactive, 2)
})
