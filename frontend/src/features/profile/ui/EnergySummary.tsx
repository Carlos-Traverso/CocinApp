import type { EnergyEstimate } from '../domain/profile'

export function EnergySummary({ estimate }: { estimate: EnergyEstimate }) {
  return <section className="energy-summary" aria-label="Estimación energética de referencia">
    <div><span>TMB en reposo</span><strong>{estimate.basalCalories} kcal/día</strong></div>
    <div><span>Gasto diario estimado</span><strong>{estimate.dailyCalories} kcal/día</strong></div>
    <div><span>Rango orientativo del objetivo</span><strong>{estimate.goalRange.minimum}–{estimate.goalRange.maximum} kcal/día</strong></div>
  </section>
}
