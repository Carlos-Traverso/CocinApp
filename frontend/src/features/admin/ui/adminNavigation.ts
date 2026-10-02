export type AdminNavigationKey = 'dashboard' | 'recipes' | 'ingredients' | 'categories' | 'units'

export type AdminNavigationItem = {
  key: AdminNavigationKey
  label: string
  path: string
  end?: boolean
}

export const adminNavigation: AdminNavigationItem[] = [
  { key: 'dashboard', label: 'Dashboard', path: '/admin', end: true },
  { key: 'recipes', label: 'Recetas', path: '/admin/recipes' },
  { key: 'ingredients', label: 'Ingredientes', path: '/admin/ingredients' },
  { key: 'categories', label: 'Categorías', path: '/admin/categories' },
  { key: 'units', label: 'Unidades', path: '/admin/units' },
]

export function getAdminNavigationItem(pathname: string) {
  return [...adminNavigation]
    .sort((a, b) => b.path.length - a.path.length)
    .find((item) => pathname === item.path || (!item.end && pathname.startsWith(`${item.path}/`)))
}
