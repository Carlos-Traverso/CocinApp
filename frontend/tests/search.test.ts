import assert from 'node:assert/strict'
import test from 'node:test'
import {
  SEARCH_DEBOUNCE_MS,
  createDebouncedValueScheduler,
  searchFeedback,
} from '../src/shared/search/debouncedSearch'

const wait = (milliseconds: number) => new Promise((resolve) => setTimeout(resolve, milliseconds))

test('all repository searches use the shared exact 500 ms delay', () => {
  assert.equal(SEARCH_DEBOUNCE_MS, 500)
})

test('debounce runs only the latest search after the quiet period', async () => {
  const values: string[] = []
  const scheduler = createDebouncedValueScheduler((value: string) => values.push(value), 20)
  scheduler.schedule('T')
  await wait(8)
  scheduler.schedule('Ta')
  await wait(12)
  assert.deepEqual(values, [])
  await wait(12)
  assert.deepEqual(values, ['Ta'])
})

test('clearing or disposing a search cancels its pending timer', async () => {
  const values: string[] = []
  const scheduler = createDebouncedValueScheduler((value: string) => values.push(value), 15)
  scheduler.schedule('arroz')
  scheduler.cancel()
  await wait(20)
  scheduler.schedule('tomate')
  scheduler.dispose()
  await wait(20)
  assert.deepEqual(values, [])
})

test('search feedback covers empty, waiting, results, no results and errors', () => {
  assert.equal(searchFeedback('empty', 0), 'Escribí para buscar')
  assert.equal(searchFeedback('waiting', 0), 'Buscando…')
  assert.equal(searchFeedback('ready', 3), '3 resultados')
  assert.equal(searchFeedback('ready', 0), 'No encontramos resultados')
  assert.equal(searchFeedback('error', 0), 'Ocurrió un error. Intentá nuevamente')
})
