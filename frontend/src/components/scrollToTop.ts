export const mobileScrollBreakpoint = 620
export const scrollVisibilityThreshold = 300

export interface ScrollEnvironment {
  innerWidth: number
  scrollY: number
  addEventListener: (name: string, listener: () => void, options?: { passive?: boolean }) => void
  removeEventListener: (name: string, listener: () => void) => void
}

export function shouldShowScrollToTop(scrollY: number, viewportWidth: number): boolean {
  return viewportWidth <= mobileScrollBreakpoint && scrollY > scrollVisibilityThreshold
}

export function scrollBehavior(prefersReducedMotion: boolean): ScrollBehavior {
  return prefersReducedMotion ? 'auto' : 'smooth'
}

export function bindScrollVisibility(environment: ScrollEnvironment, onChange: (visible: boolean) => void): () => void {
  const update = () => onChange(shouldShowScrollToTop(environment.scrollY, environment.innerWidth))
  update()
  environment.addEventListener('scroll', update, { passive: true })
  environment.addEventListener('resize', update)
  return () => {
    environment.removeEventListener('scroll', update)
    environment.removeEventListener('resize', update)
  }
}
