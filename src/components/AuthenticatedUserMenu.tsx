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

export default function AuthenticatedUserMenu({ context, isSigningOut, onSignOut }: Props) {
  return (
    <div className="flex min-w-0 items-center gap-2 rounded-2xl border border-stone-200 bg-white p-2 shadow-sm sm:gap-3 sm:px-3">
      <div className="min-w-0 flex-1 sm:flex-none">
        <p className="max-w-40 truncate text-sm font-bold text-stone-900 sm:max-w-56">{context.profile.nombre}</p>
        <p className="text-xs font-semibold text-stone-500">{roleLabels[context.role.codigo]}</p>
      </div>
      <button
        aria-busy={isSigningOut}
        className="min-h-11 shrink-0 rounded-xl bg-emerald-800 px-3 py-2 text-sm font-semibold text-white hover:bg-emerald-900 disabled:opacity-70 sm:px-4"
        disabled={isSigningOut}
        onClick={onSignOut}
        type="button"
      >
        {isSigningOut ? 'Cerrando…' : 'Cerrar sesión'}
      </button>
    </div>
  )
}
