import { useState } from 'react'
import type { Recipe } from '../domain/Recipe'

interface RecipeImageProps {
  recipe: Pick<Recipe, 'name' | 'image' | 'imageAlt' | 'symbol' | 'color'>
  className: string
  loading?: 'eager' | 'lazy'
}

export function RecipeImage({ recipe, className, loading = 'lazy' }: RecipeImageProps) {
  const [failedSource, setFailedSource] = useState<string>()

  const alt = recipe.imageAlt?.trim() || `Plato terminado de ${recipe.name}`
  if (!recipe.image || failedSource === recipe.image) {
    return <div aria-label={alt} className={`${className} recipe-image-fallback ${recipe.color}`} role="img"><span aria-hidden="true">{recipe.symbol}</span></div>
  }

  return <img alt={alt} className={`${className} recipe-photo`} decoding="async" loading={loading} onError={() => setFailedSource(recipe.image)} src={recipe.image} />
}
