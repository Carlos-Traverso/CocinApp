import { ArrowRight, Clock3, PackageCheck, Sparkles, UsersRound } from 'lucide-react'
import { Link } from 'react-router-dom'
import type { PantryItem } from '../../pantry/domain/pantry'
import { getIngredientAvailability } from '../domain/recipeRules'
import type { RecipeRecommendationSection, RecipeRecommendations } from '../domain/recipeRecommendations'
import type { Recipe } from '../domain/Recipe'
import { RecipeImage } from './RecipeImage'

const sectionContent = {
  'recipe-featured': { eyebrow: 'SELECCIÓN COCINAPP', title: 'Recetas destacadas', description: 'Selecciones destacadas desde la administración de CocinAPP.', empty: 'Todavía no hay recetas destacadas.' },
  'recipe-pantry-ready': { eyebrow: 'APROVECHÁ TU STOCK', title: 'Con lo que ya tenés', description: 'Opciones que podés preparar con el stock disponible.', empty: 'Agregá ingredientes a tu despensa para recibir sugerencias listas para cocinar.' },
  'recipe-history-based': { eyebrow: 'HECHO A TU MEDIDA', title: 'Según lo que cocinaste', description: 'Sugerencias relacionadas con tus últimas preparaciones.', empty: 'Cociná una receta y usaremos ese historial para recomendarte nuevas ideas.' },
  'recipe-recook': { eyebrow: 'OTRA VEZ, POR FAVOR', title: 'Volvé a cocinar', description: 'Tus preparaciones recientes, a un toque de distancia.', empty: 'Tu historial todavía está vacío.' },
  'recipe-favorites': { eyebrow: 'TU COLECCIÓN', title: 'Tus favoritas', description: 'Las recetas que marcaste para tener siempre a mano.', empty: 'Marcá una receta con el corazón para verla acá.' },
  'recipe-quick': { eyebrow: 'POCO TIEMPO, MUCHO SABOR', title: 'Listas en 20 minutos', description: 'Preparaciones simples para los días con poco tiempo.', empty: 'No hay recetas rápidas publicadas por el momento.' },
} as const satisfies Record<RecipeRecommendationSection['id'], { eyebrow: string; title: string; description: string; empty: string }>

function RecommendationArtwork({ recipe, size }: { recipe: Recipe; size: 'hero' | 'mini' }) {
  return <RecipeImage className={`recipe-artwork recipe-artwork-${size}`} loading={size === 'hero' ? 'eager' : 'lazy'} recipe={recipe} />
}

function RecommendationRail({ section }: { section: RecipeRecommendationSection }) {
  const content = sectionContent[section.id]
  return <section aria-labelledby={`${section.id}-title`} className="recipe-rail" id={section.id}>
    <div className="recipe-rail-heading"><div><p className="eyebrow">{content.eyebrow}</p><h2 id={`${section.id}-title`}>{content.title}</h2><p>{content.description}</p></div><Link className="recipe-rail-catalog-link" to="/recipes#recipe-catalog">Ver catálogo <ArrowRight aria-hidden="true" size={15} /></Link></div>
    {section.recipes.length === 0
      ? <div className="recipe-rail-empty"><Sparkles aria-hidden="true" size={19} /><span>{content.empty}</span></div>
      : <div className="recipe-rail-items">{section.recipes.slice(0, 4).map((recipe) => <Link className="recipe-mini-card" key={recipe.id} to={`/recipes/${recipe.id}`}><RecommendationArtwork recipe={recipe} size="mini" /><span className="recipe-mini-copy"><span className="recipe-category">{recipe.category}</span><strong>{recipe.name}</strong><small><Clock3 aria-hidden="true" size={13} /> {recipe.minutes} min · {recipe.difficulty}</small></span><ArrowRight aria-hidden="true" className="recipe-mini-arrow" size={17} /></Link>)}</div>}
  </section>
}

export function RecipeRecommendationsView({ recommendations, pantry, today = new Date() }: { recommendations: RecipeRecommendations; pantry: PantryItem[]; today?: Date }) {
  const hero = recommendations.hero
  const heroAvailability = hero ? getIngredientAvailability(hero, pantry, today) : null
  const section = (id: RecipeRecommendationSection['id']) => recommendations.sections.find((item) => item.id === id)!
  const recook = section('recipe-recook')
  const favorites = section('recipe-favorites')

  return <section aria-labelledby="recommendations-title" className="dashboard-recommendations">
    <header className="recipes-intro"><div><p className="eyebrow">TU PRÓXIMA COMIDA EMPIEZA ACÁ</p><h2 id="recommendations-title">¿Qué cocinamos hoy?</h2><p>Ideas pensadas para tu tiempo, tu despensa y lo que ya disfrutaste.</p></div></header>
    {hero && <section className={`recipe-hero ${hero.color}`} aria-labelledby="recipe-hero-title"><div className="recipe-hero-copy"><p className="recipe-hero-kicker"><Sparkles aria-hidden="true" size={16} /> Recomendación para vos</p><h2 id="recipe-hero-title">{hero.name}</h2><p>{hero.description}</p><div className="recipe-hero-meta"><span><Clock3 aria-hidden="true" size={16} />{hero.minutes} min</span><span><UsersRound aria-hidden="true" size={16} />{hero.portions} porciones</span><span>{hero.difficulty}</span></div><div className="recipe-hero-actions"><Link className="button button-dark" to={`/recipes/${hero.id}`}>Ver receta <ArrowRight aria-hidden="true" size={17} /></Link>{heroAvailability && <span className={heroAvailability.missing.length === 0 ? 'ready' : ''}><PackageCheck aria-hidden="true" size={17} />{heroAvailability.missing.length === 0 ? 'Tenés todo para cocinarla' : `Te faltan ${heroAvailability.missing.length} ingredientes`}</span>}</div></div><RecommendationArtwork recipe={hero} size="hero" /></section>}
    <RecommendationRail section={section('recipe-featured')} />
    <RecommendationRail section={section('recipe-pantry-ready')} />
    <RecommendationRail section={section('recipe-history-based')} />
    {(recook.recipes.length > 0 || favorites.recipes.length > 0) && <div className="recipe-personal-grid"><RecommendationRail section={recook} /><RecommendationRail section={favorites} /></div>}
    <RecommendationRail section={section('recipe-quick')} />
  </section>
}
