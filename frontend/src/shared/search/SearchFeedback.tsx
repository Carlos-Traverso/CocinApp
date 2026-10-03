import { searchFeedback, type SearchStatus } from './debouncedSearch'

export function SearchFeedback({ status, resultCount, className = 'search-feedback' }: {
  status: SearchStatus
  resultCount: number
  className?: string
}) {
  return <span aria-live="polite" className={className} role="status">{searchFeedback(status, resultCount)}</span>
}
