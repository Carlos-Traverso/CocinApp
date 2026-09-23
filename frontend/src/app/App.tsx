import { BrowserRouter, Navigate, Route, Routes } from 'react-router-dom'
import { AppShell } from '../components/AppShell'
import { FeaturePage } from '../pages/FeaturePage'
import { HomePage } from '../pages/HomePage'
import { OnboardingPage } from '../pages/OnboardingPage'
import { ProfilePage } from '../pages/ProfilePage'
import { RecipesPage } from '../pages/RecipesPage'
import { WelcomePage } from '../pages/WelcomePage'

export function App() {
  return (
    <BrowserRouter>
      <Routes>
        <Route index element={<WelcomePage />} />
        <Route path="onboarding" element={<OnboardingPage />} />
        <Route element={<AppShell />}>
          <Route path="panel" element={<HomePage />} />
          <Route path="recipes" element={<RecipesPage />} />
          <Route path="profile" element={<ProfilePage />} />
          <Route path=":section" element={<FeaturePage />} />
        </Route>
        <Route path="*" element={<Navigate replace to="/" />} />
      </Routes>
    </BrowserRouter>
  )
}
