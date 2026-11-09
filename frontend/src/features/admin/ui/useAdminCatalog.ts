import { useCallback, useEffect, useRef, useState } from 'react'
import type { AdminStorageData } from '../data/localAdminStore'
import { adminRepository } from '../data/AdminRepository'
import { mockRecipeRepository } from '../../recipes/data/MockRecipeRepository'
import type { Recipe } from '../../recipes/domain/Recipe'

export function useAdminCatalog() {
  const [data, setData] = useState<AdminStorageData | null>(null)
  const [knownRecipes, setKnownRecipes] = useState<Recipe[]>([])
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState('')
  const requestId = useRef(0)
  const mounted = useRef(true)
  const reload = useCallback(async () => {
    const request = ++requestId.current
    setLoading(true)
    try {
      const [catalog, recipes] = await Promise.all([adminRepository.getCatalog(), mockRecipeRepository.listKnown()])
      if (!mounted.current || request !== requestId.current) return
      setData(catalog)
      setKnownRecipes(recipes)
      setError('')
    } catch (cause) {
      if (mounted.current && request === requestId.current) setError(cause instanceof Error ? cause.message : 'No se pudo cargar el catálogo. Probá nuevamente.')
      throw cause
    } finally {
      if (mounted.current && request === requestId.current) setLoading(false)
    }
  }, [])

  useEffect(() => {
    mounted.current = true
    void reload().catch(() => undefined)
    return () => { mounted.current = false; requestId.current++ }
  }, [reload])

  return { data, knownRecipes, loading, error, setError, reload }
}
