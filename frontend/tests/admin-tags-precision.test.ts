import assert from 'node:assert/strict'
import test from 'node:test'
import { validateRecipe } from '../src/features/admin/domain/adminValidation'
import type { AdminIngredient, AdminRecipe, AdminUnit } from '../src/features/admin/domain/adminModels'

const grams: AdminUnit = { id: 'g', name: 'Gramo', abbreviation: 'g', dimension: 'masa', active: true, isDeleted: false }
const flour: AdminIngredient = { id: 'flour', name: 'Harina', categoryId: 'grains', baseUnitId: 'g', active: true, isDeleted: false }
const recipe: Omit<AdminRecipe, 'id' | 'isDeleted'> = {
  title: 'Pan', author: 'CocinAPP', description: '', category: 'Desayuno', minutes: 20, portions: 2,
  difficulty: 'Fácil', calories: 200.25, mealShift: 'Desayuno', mealShifts: ['Desayuno'], dietaryTags: ['vegan'],
  ingredients: [{ ingredientId: 'flour', quantity: 1.2345, unitId: 'g' }], steps: ['Hornear'], stepMeta: [],
  featured: false, status: 'draft', active: true, symbol: 'P', color: 'green',
}

function validate(overrides: Partial<typeof recipe> = {}) {
  return validateRecipe({ ...recipe, ...overrides }, [], [flour], [grams])
}

test('relational recipe tags remain stable keys without label guessing', () => {
  assert.deepEqual(validate().dietaryTags, ['vegan'])
  assert.deepEqual(validate({ dietaryTags: ['unknown-inactive-key'] }).dietaryTags, ['unknown-inactive-key'])
})

test('recipe quantities accept four decimals through one million and reject excess scale or range', () => {
  assert.equal(validate({ ingredients: [{ ingredientId: 'flour', quantity: 1_000_000, unitId: 'g' }] }).ingredients[0]?.quantity, 1_000_000)
  assert.throws(() => validate({ ingredients: [{ ingredientId: 'flour', quantity: 1.23456, unitId: 'g' }] }), /cuatro decimales/i)
  assert.throws(() => validate({ ingredients: [{ ingredientId: 'flour', quantity: 1_000_000.0001, unitId: 'g' }] }), /1\.000\.000/i)
})

test('recipe calories accept numeric(9,2) values and reject excessive scale or range', () => {
  assert.equal(validate({ calories: 9_999_999.99 }).calories, 9_999_999.99)
  assert.throws(() => validate({ calories: 1.234 }), /dos decimales/i)
  assert.throws(() => validate({ calories: 10_000_000 }), /9\.999\.999,99/i)
})
