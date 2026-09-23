import { useEffect, useState } from 'react'
import { ArrowLeft, Clock3, UsersRound } from 'lucide-react'
import { Link } from 'react-router-dom'
import { mockRecipeRepository } from '../features/recipes/data/MockRecipeRepository'
import type { Recipe } from '../features/recipes/domain/Recipe'

export function RecipesPage() {
  const [recipes, setRecipes] = useState<Recipe[]>()

  useEffect(() => {
    let active = true
    void mockRecipeRepository.list().then((items) => {
      if (active) setRecipes(items)
    })
    return () => { active = false }
  }, [])

  return (
    <div className="page">
      <header className="page-heading">
        <div>
          <Link className="back-link" to="/"><ArrowLeft size={16} /> Inicio</Link>
          <p className="eyebrow">RECETAS</p>
          <h1>Ideas para cocinar</h1>
          <p className="page-lead">Una primera colección local para probar la capa de datos.</p>
        </div>
        <span className="data-badge"><span /> Datos de muestra</span>
      </header>
      {recipes ? <div className="recipe-grid">
        {recipes.map((recipe) => (
          <article className="recipe-card" key={recipe.id}>
            <div className={`recipe-art ${recipe.color}`} aria-hidden="true"><span>{recipe.symbol}</span></div>
            <div className="recipe-body">
              <span className="recipe-category">{recipe.category}</span>
              <h2>{recipe.name}</h2>
              <p>{recipe.description}</p>
              <div className="recipe-meta">
                <span><Clock3 size={15} /> {recipe.minutes} min</span>
                <span><UsersRound size={15} /> {recipe.portions} porciones</span>
              </div>
            </div>
          </article>
        ))}
      </div> : <p className="loading-state" role="status">Cargando recetas...</p>}
    </div>
  )
}
