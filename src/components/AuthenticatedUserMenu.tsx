import { useEffect, useId, useRef, useState } from 'react'
import type { ValidatedProfileContext } from '../services/profileContext'
import type { RoleCode } from '../types/operations'

const roleLabels: Record<RoleCode, string> = {
  ADMINISTRADOR: 'Administrador',
  MOZO: 'Mozo',
  COCINA: 'Cocina',
  CAJA: 'Caja',
}

interface Props {
  readonly context: ValidatedProfileContext
  readonly isSigningOut: boolean
  readonly onSignOut: () => void
}

function initials(name: string): string {
  const parts = name.trim().split(/\s+/).filter(Boolean)
  if (parts.length === 0) return 'U'
  return `${parts[0][0]}${parts.length > 1 ? parts.at(-1)?.[0] ?? '' : ''}`.toLocaleUpperCase('es-PE')
}

export default function AuthenticatedUserMenu({ context, isSigningOut, onSignOut }: Props) {
  const [open, setOpen] = useState(false)
  const containerRef = useRef<HTMLDivElement>(null)
  const menuId = useId()

  useEffect(() => {
    if (!open) return
    function closeFromOutside(event: PointerEvent) {
      if (!containerRef.current?.contains(event.target as Node)) setOpen(false)
    }
    function closeFromKeyboard(event: KeyboardEvent) {
      if (event.key === 'Escape') setOpen(false)
    }
    document.addEventListener('pointerdown', closeFromOutside)
    document.addEventListener('keydown', closeFromKeyboard)
    return () => {
      document.removeEventListener('pointerdown', closeFromOutside)
      document.removeEventListener('keydown', closeFromKeyboard)
    }
  }, [open])

  function signOut() {
    setOpen(false)
    onSignOut()
  }

  return (
    <div className="relative ml-auto shrink-0" ref={containerRef}>
      <button
        aria-controls={menuId}
        aria-expanded={open}
        aria-haspopup="menu"
        aria-label={`Abrir menú de usuario de ${context.profile.nombre}`}
        className="grid h-11 w-11 place-items-center rounded-full bg-emerald-800 text-sm font-bold text-white shadow-sm ring-offset-2 hover:bg-emerald-900 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-emerald-700"
        disabled={isSigningOut}
        onClick={() => setOpen((value) => !value)}
        type="button"
      >
        {initials(context.profile.nombre)}
      </button>
      {open && (
        <div className="absolute right-0 z-50 mt-2 w-64 max-w-[calc(100vw-1.5rem)] rounded-2xl border border-stone-200 bg-white p-3 text-left shadow-xl" id={menuId} role="menu">
          <p className="truncate text-sm font-bold text-stone-900">{context.profile.nombre}</p>
          <p className="mt-1 text-xs font-semibold text-stone-500">{roleLabels[context.role.codigo]}</p>
          <button
            aria-busy={isSigningOut}
            className="mt-3 min-h-11 w-full rounded-xl bg-emerald-800 px-4 py-2 text-sm font-semibold text-white hover:bg-emerald-900 disabled:opacity-70"
            disabled={isSigningOut}
            onClick={signOut}
            role="menuitem"
            type="button"
          >
            {isSigningOut ? 'Cerrando sesión…' : 'Cerrar sesión'}
          </button>
        </div>
      )}
    </div>
  )
}
