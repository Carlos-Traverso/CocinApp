import { BrowserRouter, Navigate, Route, Routes } from 'react-router-dom'
import { AppShell } from '../components/AppShell'
import { CookingPage } from '../pages/CookingPage'
import { FeaturePage } from '../pages/FeaturePage'
import { HomePage } from '../pages/HomePage'
import { HistoryPage } from '../pages/HistoryPage'
import { OnboardingPage } from '../pages/OnboardingPage'
import { PantryPage } from '../pages/PantryPage'
import { PlannerPage } from '../pages/PlannerPage'
import { ProfilePage } from '../pages/ProfilePage'
import { RecipesPage } from '../pages/RecipesPage'
import { RecipeDetailPage } from '../pages/RecipeDetailPage'
import { ShoppingPage } from '../pages/ShoppingPage'
import { WelcomePage } from '../pages/WelcomePage'

export function App() {
  return (
    <BrowserRouter>
      <Routes>
        <Route index element={<WelcomePage />} />
        <Route path="onboarding" element={<OnboardingPage />} />
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
          <Route path=":section" element={<FeaturePage />} />
        </Route>
        <Route path="*" element={<Navigate replace to="/" />} />
      </Routes>
    </BrowserRouter>
  )
}
