export const appNavigation = [
  { id: 'panel', to: '/panel', label: 'Panel', mobileLabel: 'Panel', end: true, mobile: true },
  { id: 'recipes', to: '/recipes', label: 'Recetas', mobileLabel: 'Recetas', mobile: true },
  { id: 'pantry', to: '/pantry', label: 'Despensa', mobileLabel: 'Despensa', mobile: true },
  { id: 'planner', to: '/planner', label: 'Planificación', mobileLabel: 'Plan', mobile: true },
  { id: 'shopping', to: '/shopping', label: 'Lista de compras', mobileLabel: 'Compras', mobile: true },
  { id: 'favorites', to: '/favorites', label: 'Favoritos', mobileLabel: 'Favoritos', mobile: true },
  { id: 'history', to: '/history', label: 'Historial', mobileLabel: 'Historial', mobile: true },
  { id: 'profile', to: '/profile', label: 'Perfil', mobileLabel: 'Perfil', mobile: true },
] as const

export const mobileNavigationPaths = appNavigation.filter((item) => item.mobile).map((item) => item.to)
