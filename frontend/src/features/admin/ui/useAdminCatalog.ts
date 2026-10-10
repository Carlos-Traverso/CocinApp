import { useCallback, useEffect, useState } from 'react'
import type { AdminStorageData } from '../data/localAdminStore'
import { adminRepository } from '../data/AdminRepository'
import { mockRecipeRepository } from '../../recipes/data/MockRecipeRepository'
import type { Recipe } from '../../recipes/domain/Recipe'

export function useAdminCatalog() {
  const [data, setData] = useState<AdminStorageData | null>(null)
  const [knownRecipes, setKnownRecipes] = useState<Recipe[]>([])
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState('')
  const reload = useCallback(async () => {
    const [catalog, recipes] = await Promise.all([adminRepository.getCatalog(), mockRecipeRepository.listKnown()])
    setData(catalog)
    setKnownRecipes(recipes)
    setError('')
  }, [])

  useEffect(() => {
    let current = true
    void Promise.all([adminRepository.getCatalog(), mockRecipeRepository.listKnown()])
      .then(([catalog, recipes]) => { if (current) { setData(catalog); setKnownRecipes(recipes) } })
      .catch(() => { if (current) setError('No se pudo cargar el catálogo. Probá nuevamente.') })
      .finally(() => { if (current) setLoading(false) })
    return () => { current = false }
  }, [])

  return { data, knownRecipes, loading, error, setError, reload }
}
