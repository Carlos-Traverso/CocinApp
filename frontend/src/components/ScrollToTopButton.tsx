import { ArrowUp } from 'lucide-react'
import { useEffect, useState } from 'react'
import { bindScrollVisibility, scrollBehavior } from './scrollToTop'

export function ScrollToTopButton() {
  const [visible, setVisible] = useState(false)

  useEffect(() => bindScrollVisibility(window, setVisible), [])

  function returnToTop() {
    const reducedMotion = window.matchMedia('(prefers-reduced-motion: reduce)').matches
    window.scrollTo({ top: 0, behavior: scrollBehavior(reducedMotion) })
  }

  return (
    <button
      aria-hidden={!visible}
      aria-label="Volver arriba"
      className={`scroll-to-top${visible ? ' visible' : ''}`}
      onClick={returnToTop}
      tabIndex={visible ? 0 : -1}
      title="Volver arriba"
      type="button"
    >
      <ArrowUp aria-hidden="true" size={20} />
    </button>
  )
}
