import { ArrowLeft, ArrowUpRight } from 'lucide-react'
import { Link, useParams } from 'react-router-dom'

const sections: Record<string, { title: string; eyebrow: string; description: string; prototype?: string }> = {
  auth: { title: 'Tu cuenta', eyebrow: 'ACCESO', description: 'El acceso y la identidad se gestionan desde Supabase Auth.', prototype: 'CocinAPP_Landing_Registro_Mejorado.html' },
  onboarding: { title: 'Tus preferencias', eyebrow: 'PRIMEROS PASOS', description: 'Preferencias y objetivos asociados al perfil de cada persona.', prototype: 'CocinAPP_Onboarding_Clasico_Mejorado.html' },
  pantry: { title: 'Mi despensa', eyebrow: 'INVENTARIO', description: 'Stock, cantidades y vencimientos para cocinar con lo que ya tenés.', prototype: 'CocinAPP_Mi_Despensa_Mejorada.html' },
  planner: { title: 'Planificador semanal', eyebrow: 'ORGANIZACIÓN', description: 'Comidas y porciones organizadas por día.', prototype: 'CocinAPP_Planificador_Semanal_Mejorado.html' },
  shopping: { title: 'Lista de compras', eyebrow: 'COMPRAS', description: 'Artículos propios y necesidades calculadas a partir del plan semanal.', prototype: 'CocinAPP_Compras_Mejorado.html' },
  favorites: { title: 'Favoritos', eyebrow: 'RECETAS GUARDADAS', description: 'Acceso rápido a las recetas que quieras volver a preparar.' },
  admin: { title: 'Administración', eyebrow: 'GESTIÓN', description: 'Moderación de contenido y administración con permisos validados en el servidor.', prototype: 'CocinAPP_Panel_Administrador_Mejorado.html' },
  cooking: { title: 'Cocinar ahora', eyebrow: 'PREPARACIÓN', description: 'El descuento de ingredientes y el registro de preparación se ejecutarán en una operación transaccional.' },
}

export function FeaturePage() {
  const { section = '' } = useParams()
  const feature = sections[section]

  if (!feature) {
    return <div className="page"><Link className="back-link" to="/panel"><ArrowLeft size={16} /> Volver al panel</Link><h1>Esta sección no existe</h1></div>
  }

  return (
    <div className="page feature-page">
      <header className="page-heading">
        <div>
          <Link className="back-link" to="/panel"><ArrowLeft size={16} /> Panel</Link>
          <p className="eyebrow">{feature.eyebrow}</p>
          <h1>{feature.title}</h1>
          <p className="page-lead">{feature.description}</p>
        </div>
      </header>
      <section className="feature-content">
        <span className="data-badge"><span /> Módulo inicial</span>
        <p>La pantalla y las reglas de este módulo se incorporan dentro de su funcionalidad, sin acoplarlas a la navegación general.</p>
        {feature.prototype && (
          <a className="text-link" href={`/prototypes/cocinapp.html#${feature.prototype}`}>
            Ver pantalla en el prototipo <ArrowUpRight size={16} />
          </a>
        )}
      </section>
    </div>
  )
}
