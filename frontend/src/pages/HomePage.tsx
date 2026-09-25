import { ArrowRight, CalendarDays, ChefHat, Clock3, Heart, History, Refrigerator, ShoppingCart, UserRound } from 'lucide-react'
import { Link } from 'react-router-dom'
import { readHistory } from '../features/cooking/data/localCookingStore'
import { buildDashboardSummary } from '../features/dashboard/domain/dashboard'
import { readPantryItems } from '../features/pantry/data/localPantryStore'
import { formatPantryAmount } from '../features/pantry/domain/pantry'
import { readMealPlan } from '../features/planner/data/localMealPlanStore'
import { readFavoriteIds } from '../features/recipes/data/localFavoritesStore'
import { readShoppingItems } from '../features/shopping/data/localShoppingStore'
import { getAvailableRecipes, getKnownRecipes } from '../features/recipes/data/availableRecipes'

const shortcuts = [
  { to: '/pantry', label: 'Despensa', Icon: Refrigerator },
  { to: '/recipes', label: 'Recetas', Icon: ChefHat },
  { to: '/planner', label: 'Planificación', Icon: CalendarDays },
  { to: '/shopping', label: 'Lista de compras', Icon: ShoppingCart },
  { to: '/history', label: 'Historial y modo cocina', Icon: History },
  { to: '/profile', label: 'Perfil', Icon: UserRound },
]

function formatCookedAt(value: string): string {
  return new Date(value).toLocaleDateString('es-AR', { day: 'numeric', month: 'short' })
}

export function HomePage() {
  const availableRecipes = getAvailableRecipes()
  const knownRecipes = getKnownRecipes()
  const summary = buildDashboardSummary({
    pantry: readPantryItems(),
    recipes: availableRecipes,
    favoriteIds: readFavoriteIds(),
    plan: readMealPlan(),
    shopping: readShoppingItems(),
    history: readHistory(),
  })
  const attentionItems = [...summary.pantry.expired, ...summary.pantry.expiringSoon, ...summary.pantry.lowStock]
    .filter((item, index, items) => items.findIndex((candidate) => candidate.id === item.id) === index)
  const attentionCount = attentionItems.length

  return (
    <div className="page dashboard-page">
      <header className="page-heading dashboard-heading">
        <div>
          <p className="eyebrow">MI COCINA</p>
          <h1>Tu cocina, en orden.</h1>
          <p className="page-lead">Un resumen de lo que podés cocinar y organizar hoy.</p>
        </div>
        <Link className="button button-primary" to="/recipes"><ChefHat size={18} aria-hidden="true" /> Explorar recetas</Link>
      </header>

      <nav aria-label="Accesos rápidos" className="dashboard-shortcuts">
        {shortcuts.map(({ to, label, Icon }) => (
          <Link className="dashboard-shortcut" key={to} to={to}>
            <Icon size={18} aria-hidden="true" /><span>{label}</span><ArrowRight size={15} aria-hidden="true" />
          </Link>
        ))}
      </nav>

      <section aria-label="Resumen" className="dashboard-stats">
        <Link className="dashboard-stat" to="/pantry"><span>Ingredientes</span><strong>{summary.pantry.totalItems}</strong><small>en la despensa</small></Link>
        <Link className="dashboard-stat dashboard-stat-warn" to="/pantry"><span>Para revisar</span><strong>{attentionCount}</strong><small>{attentionCount === 1 ? 'alerta de stock o vencimiento' : 'alertas de stock o vencimiento'}</small></Link>
        <Link className="dashboard-stat" to="/planner"><span>Esta semana</span><strong>{summary.weeklyMealCount}</strong><small>{summary.weeklyMealCount === 1 ? 'comida planificada' : 'comidas planificadas'}</small></Link>
        <Link className="dashboard-stat" to="/shopping"><span>Por comprar</span><strong>{summary.shopping.pendingCount}</strong><small>{summary.shopping.completedCount} ya {summary.shopping.completedCount === 1 ? 'comprado' : 'comprados'}</small></Link>
      </section>

      <div className="dashboard-columns">
        <div className="dashboard-main-column">
          <section aria-labelledby="dashboard-pantry-title" className="dashboard-panel">
            <div className="dashboard-panel-heading"><div><p className="eyebrow">DESPENSA</p><h2 id="dashboard-pantry-title">Atención para hoy</h2></div><Link className="text-link" to="/pantry">Ver despensa <ArrowRight size={15} /></Link></div>
            {summary.pantry.totalItems === 0 ? (
              <div className="dashboard-empty"><p>Tu despensa todavía está vacía.</p><Link className="text-link" to="/pantry">Añadir ingredientes <ArrowRight size={15} /></Link></div>
            ) : attentionCount === 0 ? (
              <div className="dashboard-empty"><p>Todo en orden: no hay alertas de stock ni vencimientos próximos.</p></div>
            ) : (
              <ul className="dashboard-list">
                {attentionItems.slice(0, 4).map((item) => {
                  const status = summary.pantry.expired.includes(item) ? 'Vencido' : summary.pantry.expiringSoon.includes(item) ? 'Vence pronto' : item.quantity === 0 ? 'Sin stock' : 'Stock bajo'
                  return <li className="dashboard-row" key={item.id}><span><strong>{item.name}</strong><small>{status}</small></span><span className="dashboard-row-value">{formatPantryAmount(item.quantity, item.unit)}</span></li>
                })}
              </ul>
            )}
          </section>

          <section aria-labelledby="dashboard-recipes-title" className="dashboard-panel">
            <div className="dashboard-panel-heading"><div><p className="eyebrow">CON TU DESPENSA</p><h2 id="dashboard-recipes-title">¿Qué podés cocinar?</h2></div><Link className="text-link" to="/recipes">Ver recetas <ArrowRight size={15} /></Link></div>
            {summary.pantry.totalItems === 0 ? (
              <div className="dashboard-empty"><p>Agregá ingredientes para recibir sugerencias según tu stock.</p><Link className="text-link" to="/pantry">Ir a la despensa <ArrowRight size={15} /></Link></div>
            ) : (
              <ul className="dashboard-list">
                {summary.suggestedRecipes.slice(0, 3).map(({ recipe, missingNames, canCook }) => (
                  <li className="dashboard-row dashboard-recipe-row" key={recipe.id}>
                    <span><Link className="dashboard-item-link" to={`/recipes/${recipe.id}`}>{recipe.name}</Link><small>{canCook ? 'Tenés todo lo necesario' : `Te falta: ${missingNames.slice(0, 2).join(', ')}${missingNames.length > 2 ? '…' : ''}`}</small></span>
                    {canCook ? <Link className="dashboard-row-action" to={`/recipes/${recipe.id}/cook`}>Cocinar ahora <ArrowRight size={14} /></Link> : <span className="dashboard-row-value"><Clock3 size={14} /> {recipe.minutes} min</span>}
                  </li>
                ))}
              </ul>
            )}
          </section>

          <section aria-labelledby="dashboard-plan-title" className="dashboard-panel">
            <div className="dashboard-panel-heading"><div><p className="eyebrow">PLANIFICACIÓN</p><h2 id="dashboard-plan-title">Comidas de hoy</h2></div><Link className="text-link" to="/planner">Ver semana <ArrowRight size={15} /></Link></div>
            {(['Almuerzo', 'Cena'] as const).map((meal) => {
              const entry = summary.todayMeals.find((item) => item.meal === meal)
              return <div className="dashboard-row dashboard-meal-row" key={meal}><span><strong>{meal}</strong><small>{entry ? entry.recipe.name : 'Todavía sin planificar'}</small></span>{entry ? <Link className="dashboard-row-action" to={`/recipes/${entry.recipe.id}/cook`}>Cocinar <ArrowRight size={14} /></Link> : <Link className="text-link" to="/planner">Agregar <ArrowRight size={14} /></Link>}</div>
            })}
          </section>
        </div>

        <aside className="dashboard-side-column">
          <section aria-labelledby="dashboard-shopping-title" className="dashboard-panel">
            <div className="dashboard-panel-heading"><div><p className="eyebrow">COMPRAS</p><h2 id="dashboard-shopping-title">Lista pendiente</h2></div><Link aria-label="Ver lista de compras" className="dashboard-icon-link" to="/shopping"><ShoppingCart size={18} /></Link></div>
            {summary.shopping.pendingCount === 0 ? <div className="dashboard-empty"><p>No tenés compras pendientes.</p><Link className="text-link" to="/shopping">Abrir lista <ArrowRight size={15} /></Link></div> : <ul className="dashboard-list">{summary.shopping.pendingItems.slice(0, 4).map((item) => <li className="dashboard-row" key={item.id}><span><strong>{item.name}</strong><small>{item.sources.includes('manual') ? 'Agregado manualmente' : 'Sugerido para cocinar'}</small></span><span className="dashboard-row-value">{formatPantryAmount(item.quantity, item.unit)}</span></li>)}</ul>}
            {summary.shopping.pendingCount > 4 && <Link className="dashboard-foot-link" to="/shopping">Ver {summary.shopping.pendingCount - 4} artículos más</Link>}
          </section>

          <section aria-labelledby="dashboard-favorites-title" className="dashboard-panel">
            <div className="dashboard-panel-heading"><div><p className="eyebrow">GUARDADAS</p><h2 id="dashboard-favorites-title">Favoritas</h2></div><Link aria-label="Ver recetas favoritas" className="dashboard-icon-link" to="/favorites"><Heart size={18} /></Link></div>
            {summary.favorites.length === 0 ? <div className="dashboard-empty"><p>Todavía no guardaste recetas.</p><Link className="text-link" to="/recipes">Explorar recetas <ArrowRight size={15} /></Link></div> : <ul className="dashboard-list">{summary.favorites.slice(0, 3).map((recipe) => <li className="dashboard-row" key={recipe.id}><span><Link className="dashboard-item-link" to={`/recipes/${recipe.id}`}>{recipe.name}</Link><small>{recipe.minutes} min · {recipe.difficulty}</small></span><Link aria-label={`Ver ${recipe.name}`} className="dashboard-icon-link" to={`/recipes/${recipe.id}`}><ArrowRight size={16} /></Link></li>)}</ul>}
          </section>

          <section aria-labelledby="dashboard-history-title" className="dashboard-panel">
            <div className="dashboard-panel-heading"><div><p className="eyebrow">MODO COCINA</p><h2 id="dashboard-history-title">Cocinaste hace poco</h2></div><Link aria-label="Ver historial" className="dashboard-icon-link" to="/history"><History size={18} /></Link></div>
            {summary.recentHistory.length === 0 ? <div className="dashboard-empty"><p>Acá vas a encontrar tus preparaciones recientes.</p><Link className="text-link" to="/recipes">Elegir una receta <ArrowRight size={15} /></Link></div> : <ul className="dashboard-list">{summary.recentHistory.slice(0, 3).map((event) => { const recipe = knownRecipes.find((item) => item.id === event.recipeId); return recipe && <li className="dashboard-row" key={event.id}><span><Link className="dashboard-item-link" to={`/recipes/${recipe.id}`}>{recipe.name}</Link><small>{formatCookedAt(event.cookedAt)} · {event.portions} porciones</small></span>{availableRecipes.some((item) => item.id === recipe.id) && <Link aria-label={`Cocinar ${recipe.name} otra vez`} className="dashboard-icon-link" to={`/recipes/${recipe.id}/cook`}><ChefHat size={16} /></Link>}</li> })}</ul>}
          </section>
        </aside>
      </div>
    </div>
  )
}
