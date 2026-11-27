import { createBrowserRouter, createRoutesFromElements, Navigate, Route, RouterProvider } from 'react-router-dom'
import { AppShell } from '../components/AppShell'
import { CookingPage } from '../pages/CookingPage'
import { AdminNutritionPage, AdminAuditPage, AdminCategoriesPage, AdminIngredientsPage, AdminPage, AdminRecipesPage, AdminUnitsPage, AdminUsersPage } from '../pages/AdminPage'
import { HomePage } from '../pages/HomePage'
import { HistoryPage } from '../pages/HistoryPage'
import { PantryPage } from '../pages/PantryPage'
import { PlannerPage } from '../pages/PlannerPage'
import { ProfilePage } from '../pages/ProfilePage'
import { RecipesPage } from '../pages/RecipesPage'
import { RecipeDetailPage } from '../pages/RecipeDetailPage'
import { ShoppingPage } from '../pages/ShoppingPage'
import { WelcomePage } from '../pages/WelcomePage'
import { RequestPasswordRecoveryPage, ResetPasswordPage } from '../pages/PasswordRecoveryPage'
import { AdminShell } from '../components/AdminShell'
import { RequireRole, RequireSession, RedirectIfAuthenticated } from './AuthGuards'
import { RequireUserSetup } from './RequireUserSetup'
import { RouteErrorPage, UnexpectedErrorPage } from './RouteErrorPage'
import { NotificationProvider } from '../shared/notifications/NotificationProvider'
import { adminAuditAvailable, adminNutritionAvailable } from '../features/admin/ui/adminNavigation'

const router = createBrowserRouter(createRoutesFromElements(
  <Route errorElement={<UnexpectedErrorPage />}>
    <Route path="recuperar-contrasena" element={<RequestPasswordRecoveryPage />} />
    <Route path="restablecer-contrasena" element={<ResetPasswordPage />} />
    {import.meta.env.DEV && <Route path="__errores/500" element={null} loader={() => {
      throw new Response(null, { status: 500 })
    }} />}
    <Route element={<RedirectIfAuthenticated />}>
      <Route index element={<WelcomePage />} />
      <Route path="auth" element={<Navigate replace to="/" />} />
    </Route>

    <Route element={<RequireSession />}>
      <Route element={<RequireRole role="ADMIN" />}>
        <Route path="admin" element={<AdminShell />}>
          <Route index element={<AdminPage />} />
          <Route path="recipes" element={<AdminRecipesPage />} />
          <Route path="ingredients" element={<AdminIngredientsPage />} />
          <Route path="categories" element={<AdminCategoriesPage />} />
          <Route path="units" element={<AdminUnitsPage />} />
          <Route path="users" element={<AdminUsersPage />} />
          <Route path="history" element={adminAuditAvailable ? <AdminAuditPage /> : <Navigate replace to="/admin" />} />
          <Route path="nutrition" element={adminNutritionAvailable ? <AdminNutritionPage /> : <Navigate replace to="/admin" />} />
        </Route>
      </Route>

      <Route element={<RequireRole role="USER" />}>
        <Route element={<RequireUserSetup />}>
          <Route path="onboarding" element={<Navigate replace to="/panel" />} />
          <Route path="recipes/:id/cook" element={<CookingPage />} />
          <Route element={<AppShell />}>
            <Route path="panel" element={<HomePage />} />
            <Route path="recipes" element={<RecipesPage />} />
            <Route path="recipes/:id" element={<RecipeDetailPage />} />
            <Route path="favorites" element={<RecipesPage favoritesOnly />} />
            <Route path="history" element={<HistoryPage />} />
            <Route path="cooking" element={<Navigate replace to="/recipes" />} />
            <Route path="profile" element={<ProfilePage />} />
            <Route path="pantry" element={<PantryPage />} />
            <Route path="planner" element={<PlannerPage />} />
            <Route path="shopping" element={<ShoppingPage />} />
          </Route>
        </Route>
      </Route>
    </Route>
    <Route path="*" element={<RouteErrorPage status={404} />} />
  </Route>,
))

export function App() {
  return (
    <NotificationProvider>
      <RouterProvider router={router} />
    </NotificationProvider>
  )
}
