import { useEffect, useState } from 'react'
import {
  SEARCH_DEBOUNCE_MS,
  createDebouncedValueScheduler,
  type SearchStatus,
} from './debouncedSearch'

export function useDebouncedSearch(rawQuery: string): { query: string; status: Extract<SearchStatus, 'empty' | 'waiting' | 'ready'> } {
  const [debouncedQuery, setDebouncedQuery] = useState('')
  const trimmedQuery = rawQuery.trim()

  useEffect(() => {
    const scheduler = createDebouncedValueScheduler((query: string) => {
      setDebouncedQuery(query)
    }, trimmedQuery ? SEARCH_DEBOUNCE_MS : 0)
    scheduler.schedule(rawQuery)
    return () => scheduler.dispose()
  }, [rawQuery, trimmedQuery])

  if (!trimmedQuery) return { query: '', status: 'empty' }
  if (debouncedQuery !== rawQuery) return { query: '', status: 'waiting' }
  return { query: debouncedQuery, status: 'ready' }
}
