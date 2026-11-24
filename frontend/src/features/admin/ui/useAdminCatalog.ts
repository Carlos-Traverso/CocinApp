import { useCallback, useEffect, useRef, useState } from 'react'
import type { AdminStorageData } from '../data/localAdminStore'
import { adminRepository } from '../data/AdminRepository'
import { recipeRepository } from '../../recipes/data/recipeData'
import type { Recipe } from '../../recipes/domain/Recipe'
import type { DeleteResult } from '../data/deleteResult'
import { useNotifications } from '../../../shared/notifications/NotificationProvider'

export function useAdminCatalog() {
  const [data, setData] = useState<AdminStorageData | null>(null)
  const [knownRecipes, setKnownRecipes] = useState<Recipe[]>([])
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState('')
  const [pending, setPending] = useState(false)
  const { notify } = useNotifications()
  const requestId = useRef(0)
  const mounted = useRef(true)
  const reload = useCallback(async () => {
    const request = ++requestId.current
    setLoading(true)
    try {
      const [catalog, recipes] = await Promise.all([adminRepository.getCatalog(), recipeRepository.listKnown()])
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

  async function save(action: () => Promise<unknown>, fallback: string, onSaved?: () => void) {
    if (pending || loading) return
    setPending(true)
    setError('')
    try {
      const result = await action()
      onSaved?.()
      try {
        await reload()
      } catch {
        setError(result === 'not-found'
          ? 'El registro ya no existe y no se pudo actualizar el catálogo.'
          : 'El cambio se guardó, pero no se pudo actualizar el catálogo.')
        return
      }
      if (result === 'not-found') setError('El registro ya no existe. El catálogo se actualizó.')
    } catch (cause) {
      setError(cause instanceof Error ? cause.message : fallback)
    } finally {
      setPending(false)
    }
  }

  async function remove(label: string, name: string, action: () => Promise<DeleteResult>) {
    const confirmed = await notify({
      type: 'warning',
      title: `Eliminar ${label}`,
      message: `¿Querés eliminar «${name}»? Según las referencias y el modo de almacenamiento, puede quedar archivado.`,
      confirmLabel: 'Eliminar',
      cancelLabel: 'Cancelar',
    })
    if (confirmed) await save(action, 'No se pudo eliminar el registro.')
  }

  return { data, knownRecipes, loading, pending, error, setError, reload, save, remove }
}
