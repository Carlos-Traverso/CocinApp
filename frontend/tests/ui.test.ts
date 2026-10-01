import assert from 'node:assert/strict'
import test from 'node:test'
import { bindScrollVisibility, scrollBehavior, shouldShowScrollToTop } from '../src/components/scrollToTop'
import { profileHeaderActions } from '../src/features/profile/ui/profileHeaderActions'
import { mealBadgeDetails, plannerSlotPresentation } from '../src/features/planner/ui/plannerPresentation'

test('mobile back-to-top visibility follows scroll and cleans up its listeners', () => {
  assert.equal(shouldShowScrollToTop(0, 390), false)
  assert.equal(shouldShowScrollToTop(301, 390), true)
  assert.equal(shouldShowScrollToTop(800, 1024), false)
  assert.equal(scrollBehavior(false), 'smooth')
  assert.equal(scrollBehavior(true), 'auto')

  const listeners: Map<string, () => void> = new Map()
  const removed: string[] = []
  const environment = {
    innerWidth: 390,
    scrollY: 0,
    addEventListener: (name: string, listener: () => void) => { listeners.set(name, listener) },
    removeEventListener: (name: string) => { removed.push(name); listeners.delete(name) },
  }
  const states: boolean[] = []
  const cleanup = bindScrollVisibility(environment, (visible) => states.push(visible))
  assert.deepEqual(states, [false])
  environment.scrollY = 450
  listeners.get('scroll')?.()
  assert.deepEqual(states, [false, true])
  cleanup()
  assert.deepEqual(removed.sort(), ['resize', 'scroll'])
  assert.equal(listeners.size, 0)
})

test('profile header groups Ver recetas and Cerrar sesión', () => {
  assert.deepEqual(profileHeaderActions, [
    { id: 'recipes', label: 'Ver recetas', href: '/recipes', tone: 'neutral' },
    { id: 'signout', label: 'Cerrar sesión', tone: 'danger' },
  ])
})
test('planner presents four meal badges and explicit slot actions', () => {
  assert.deepEqual(Object.values(mealBadgeDetails).map(({ label, icon }) => ({ label, icon })), [
    { label: 'Desayuno', icon: 'coffee' },
    { label: 'Almuerzo', icon: 'sun' },
    { label: 'Merienda', icon: 'apple' },
    { label: 'Cena', icon: 'moon' },
  ])
  assert.deepEqual(plannerSlotPresentation(false), {
    state: 'Sin receta planificada', primaryAction: 'Agregar receta', actions: [],
  })
  assert.deepEqual(plannerSlotPresentation(true), {
    state: 'Receta asignada', primaryAction: 'Cambiar receta', actions: ['Ver receta', 'Quitar receta'],
  })
})
