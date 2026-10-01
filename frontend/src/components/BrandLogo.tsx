type BrandLogoProps = {
  alt?: string
  className?: string
  variant?: 'complete' | 'compact'
}

export function BrandLogo({ alt = 'CocinAPP', className = '', variant = 'compact' }: BrandLogoProps) {
  const classes = `brand-logo brand-logo-${variant}${className ? ` ${className}` : ''}`

  if (variant === 'complete') {
    return <img alt={alt} className={classes} src="/assets/branding/cocinapp-logo.png" />
  }

  return (
    <span className={classes}>
      <img alt="" aria-hidden="true" className="brand-logo-mark" src="/assets/branding/cocinapp-marca.png" />
      <span className="brand-logo-name">CocinAPP</span>
    </span>
  )
}
