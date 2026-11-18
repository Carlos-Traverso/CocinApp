import { ArrowLeft } from 'lucide-react'
import { Link } from 'react-router-dom'
import { ErrorScreen } from '../../../app/ErrorScreen'

export function MissingRecipe({ embedded }: { embedded?: boolean }) {
  return <ErrorScreen
    description="Puede que el enlace haya cambiado o que la receta ya no esté disponible."
    embedded={embedded}
    status={404}
    title="Receta no encontrada"
  >
    <Link className="button button-primary" to="/recipes">
      <ArrowLeft size={17} aria-hidden="true" />Volver a recetas
    </Link>
  </ErrorScreen>
}
