import { ArrowRight, Clock3, PackageCheck, Sparkles, UsersRound } from 'lucide-react'
import { Link } from 'react-router-dom'
import type { PantryItem } from '../../pantry/domain/pantry'
import { getIngredientAvailability, recipeMealShifts } from '../domain/recipeRules'
import type { RecipeRecommendationSection, RecipeRecommendations } from '../domain/recipeRecommendations'
import type { Recipe } from '../domain/Recipe'
import type { AdminUnit } from '../../admin/domain/adminModels'
import { RecipeImage } from './RecipeImage'

const sectionContent = {
  'recipe-featured': { eyebrow: 'SELECCIÓN COCINAPP', title: 'Recetas destacadas', description: 'Selecciones destacadas desde la administración de CocinAPP.' },
  'recipe-pantry-ready': { eyebrow: 'APROVECHÁ TU STOCK', title: 'Con lo que ya tenés', description: 'Opciones que podés preparar con el stock disponible.' },
  'recipe-history-based': { eyebrow: 'HECHO A TU MEDIDA', title: 'Según lo que cocinaste', description: 'Sugerencias relacionadas con tus últimas preparaciones.' },
  'recipe-recook': { eyebrow: 'OTRA VEZ, POR FAVOR', title: 'Volvé a cocinar', description: 'Tus preparaciones recientes, a un toque de distancia.' },
  'recipe-favorites': { eyebrow: 'TU COLECCIÓN', title: 'Tus favoritas', description: 'Las recetas que marcaste para tener siempre a mano.' },
  'recipe-quick': { eyebrow: 'POCO TIEMPO, MUCHO SABOR', title: 'Listas en 20 minutos', description: 'Preparaciones simples para los días con poco tiempo.' },
} as const satisfies Record<RecipeRecommendationSection['id'], { eyebrow: string; title: string; description: string }>

function RecommendationArtwork({ recipe, size }: { recipe: Recipe; size: 'hero' | 'mini' }) {
  return <RecipeImage className={`recipe-artwork recipe-artwork-${size}`} loading={size === 'hero' ? 'eager' : 'lazy'} recipe={recipe} />
}

function DietaryInfo({ recipe }: { recipe: Recipe }) {
  return <div className="recipe-dietary-info">
    <span className="recipe-dietary-tags">{recipe.dietaryTags?.length ? recipe.dietaryTags.join(' · ') : 'Sin etiquetas dietéticas declaradas'}</span>
    <span className="recipe-recommendation-ingredients"><strong>Ingredientes:</strong> {recipe.ingredients.map((ingredient) => ingredient.name).join(' · ')}</span>
  </div>
}

function RecommendationRail({ section }: { section: RecipeRecommendationSection }) {
  const content = sectionContent[section.id]
  return <section aria-labelledby={`${section.id}-title`} className="recipe-rail" id={section.id}>
    <div className="recipe-rail-heading"><div><p className="eyebrow">{content.eyebrow}</p><h2 id={`${section.id}-title`}>{content.title}</h2><p>{content.description}</p></div><Link className="recipe-rail-catalog-link" to="/recipes#recipe-catalog">Ver catálogo <ArrowRight aria-hidden="true" size={15} /></Link></div>
    <div className="recipe-rail-items">{section.recipes.map((recipe) => <Link className="recipe-mini-card" key={recipe.id} to={`/recipes/${recipe.id}`}><RecommendationArtwork recipe={recipe} size="mini" /><span className="recipe-mini-primary"><span className="recipe-category">{recipeMealShifts(recipe).join(' · ')}</span><strong>{recipe.name}</strong><small><Clock3 aria-hidden="true" size={13} /> {recipe.minutes} min · {recipe.difficulty}</small></span><DietaryInfo recipe={recipe} /><ArrowRight aria-hidden="true" className="recipe-mini-arrow" size={17} /></Link>)}</div>
  </section>
}

export function RecipeRecommendationsView({ recommendations, pantry, today = new Date(), units }: { recommendations: RecipeRecommendations; pantry: PantryItem[]; today?: Date; units?: AdminUnit[] }) {
  const hero = recommendations.hero
  const sections = recommendations.sections.filter((section) => section.recipes.length > 0)
  if (!hero && sections.length === 0) return null

  const heroAvailability = hero ? getIngredientAvailability(hero, pantry, today, units) : null
  const personalSections = sections.filter(({ id }) => id === 'recipe-recook' || id === 'recipe-favorites')
  const discoverySections = sections.filter(({ id }) => id !== 'recipe-recook' && id !== 'recipe-favorites' && id !== 'recipe-quick')
  const quickSection = sections.find(({ id }) => id === 'recipe-quick')
  const personalRails = personalSections.map((section) => <RecommendationRail key={section.id} section={section} />)

  return <section aria-labelledby="recommendations-title" className="dashboard-recommendations">
    <header className="recipes-intro"><div><p className="eyebrow">TU PRÓXIMA COMIDA EMPIEZA ACÁ</p><h2 id="recommendations-title">¿Qué cocinamos hoy?</h2><p>Ideas pensadas para tu tiempo, tu despensa y lo que ya disfrutaste.</p></div></header>
    {hero && <section className={`recipe-hero ${hero.color}`} aria-labelledby="recipe-hero-title">
      <div className="recipe-hero-copy recipe-hero-intro">
        <p className="recipe-hero-kicker"><Sparkles aria-hidden="true" size={16} /> Recomendación para vos</p>
      </div>
      <RecommendationArtwork recipe={hero} size="hero" />
      <div className="recipe-hero-copy recipe-hero-details">
        <h2 id="recipe-hero-title">{hero.name}</h2>
        <p>{hero.description}</p>
        <div className="recipe-hero-meta">
          <span><Clock3 aria-hidden="true" size={16} />{hero.minutes} min</span>
          <span><UsersRound aria-hidden="true" size={16} />{hero.portions} porciones</span>
          <span>{hero.difficulty}</span>
        </div>
        <DietaryInfo recipe={hero} />
        <div className="recipe-hero-actions">
          <Link className="button button-dark" to={`/recipes/${hero.id}`}>Ver receta <ArrowRight aria-hidden="true" size={17} /></Link>
          {heroAvailability && <span className={heroAvailability.missing.length === 0 ? 'ready' : ''}>
            <PackageCheck aria-hidden="true" size={17} />
            {heroAvailability.missing.length === 0 ? 'Tenés todo para cocinarla' : `Te faltan ${heroAvailability.missing.length} ingredientes`}
          </span>}
        </div>
      </div>
    </section>}
    {discoverySections.map((section) => <RecommendationRail key={section.id} section={section} />)}
    {personalRails.length > 1 ? <div className="recipe-personal-grid">{personalRails}</div> : personalRails}
    {quickSection && <RecommendationRail section={quickSection} />}
  </section>
}
