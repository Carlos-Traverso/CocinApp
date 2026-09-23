import { BrowserRouter, Route, Routes } from 'react-router-dom'
import { AppShell } from '../components/AppShell'
import { FeaturePage } from '../pages/FeaturePage'
import { HomePage } from '../pages/HomePage'
import { RecipesPage } from '../pages/RecipesPage'

export function App() {
  return (
    <BrowserRouter>
      <Routes>
        <Route element={<AppShell />}>
          <Route index element={<HomePage />} />
          <Route path="recipes" element={<RecipesPage />} />
          <Route path=":section" element={<FeaturePage />} />
          <Route path="*" element={<FeaturePage />} />
        </Route>
      </Routes>
    </BrowserRouter>
  )
}
