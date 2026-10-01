import { createContext, useCallback, useContext, useEffect, useMemo, useRef, useState, type ReactNode } from 'react'
import AuthenticatedUserMenu from './AuthenticatedUserMenu'
import type { ValidatedProfileContext } from '../services/profileContext'
import { getSupabaseClient } from '../services/supabaseClient'
import {
  LOCAL_CLOSED_MESSAGE,
  createOperationalDayService,
  subscribeToOperationalDay,
  type OperationalDay,
} from '../services/operationalDayService.ts'

/**
 * E9-D13: estado del local para MOZO, COCINA y CAJA. Barrera visual únicamente: PostgreSQL rechaza toda
 * operación con el local cerrado. Fail-closed: si el estado no puede determinarse, no se muestra la pantalla
 * operativa.
 */
export type OperationalDayGateState =
  | { readonly status: 'loading' }
  | { readonly status: 'open'; readonly day: OperationalDay }
  | { readonly status: 'closed' }
  | { readonly status: 'error'; readonly message: string }

export interface OperationalDayContextValue {
  readonly jornada: OperationalDay | null
  readonly resync: () => Promise<void>
}

const OperationalDayContext = createContext<OperationalDayContextValue>({ jornada: null, resync: async () => {} })

/** Jornada abierta vigente y resincronización del estado del local (p. ej. ante un PT409 de local cerrado). */
export function useOperationalDay(): OperationalDayContextValue {
  return useContext(OperationalDayContext)
}

export function LocalClosedScreen({ context, isSigningOut, onRefresh, onSignOut, refreshing }: {
  readonly context: ValidatedProfileContext
  readonly isSigningOut: boolean
  readonly onRefresh: () => void
  readonly onSignOut: () => void
  readonly refreshing: boolean
}) {
  return (
    <main className="grid min-h-screen place-items-center overflow-x-hidden bg-stone-100 px-4 py-6 text-stone-900">
      <section aria-labelledby="local-closed-title" className="w-full min-w-0 max-w-md rounded-3xl border border-stone-200 bg-white p-6 shadow-sm sm:p-7">
        <div className="flex items-start justify-between gap-3">
          <p className="text-sm font-semibold uppercase tracking-[0.18em] text-emerald-700">MikuyApp</p>
          <AuthenticatedUserMenu context={context} isSigningOut={isSigningOut} onSignOut={onSignOut} />
        </div>
        <h1 className="mt-4 text-2xl font-bold" id="local-closed-title" role="status">{LOCAL_CLOSED_MESSAGE}</h1>
        <p className="mt-3 text-stone-600">{context.local.nombre}</p>
        <p className="mt-2 text-sm text-stone-600">Cuando el administrador abra la jornada, esta pantalla se habilitará automáticamente.</p>
        <div className="mt-6 flex flex-col gap-3 sm:flex-row">
          <button className="min-h-11 rounded-xl border border-stone-300 px-4 py-3 font-semibold text-stone-800 disabled:opacity-60" disabled={refreshing} onClick={onRefresh} type="button">
            {refreshing ? 'Actualizando…' : 'Actualizar'}
          </button>
          <button className="min-h-11 rounded-xl bg-stone-900 px-4 py-3 font-semibold text-white disabled:opacity-60" disabled={isSigningOut} onClick={onSignOut} type="button">
            {isSigningOut ? 'Cerrando sesión…' : 'Cerrar sesión'}
          </button>
        </div>
      </section>
    </main>
  )
}

function OperationalDayStatusScreen({ error, isSigningOut, onRetry, onSignOut }: {
  readonly error: string | null
  readonly isSigningOut: boolean
  readonly onRetry: () => void
  readonly onSignOut: () => void
}) {
  return (
    <main className="grid min-h-screen place-items-center overflow-x-hidden bg-stone-100 px-4 py-6 text-stone-900">
      <section aria-busy={error ? undefined : true} aria-live="polite" className="w-full min-w-0 max-w-md rounded-3xl border border-stone-200 bg-white p-6 shadow-sm sm:p-7">
        <p className="text-sm font-semibold uppercase tracking-[0.18em] text-emerald-700">MikuyApp</p>
        <h1 className="mt-3 text-xl font-bold">{error ? 'No pudimos verificar el estado del local' : 'Verificando el estado del local…'}</h1>
        {error && <p className="mt-3 text-stone-600" role="alert">{error}</p>}
        {error && (
          <div className="mt-6 flex flex-col gap-3 sm:flex-row">
            <button className="min-h-11 rounded-xl bg-emerald-800 px-4 py-3 font-semibold text-white" onClick={onRetry} type="button">Reintentar</button>
            <button className="min-h-11 rounded-xl border border-stone-300 px-4 py-3 font-semibold text-stone-800 disabled:opacity-60" disabled={isSigningOut} onClick={onSignOut} type="button">
              {isSigningOut ? 'Cerrando sesión…' : 'Cerrar sesión'}
            </button>
          </div>
        )}
      </section>
    </main>
  )
}

export default function OperationalDayGate({ children, context, isSigningOut, onSignOut }: {
  readonly children: ReactNode
  readonly context: ValidatedProfileContext
  readonly isSigningOut: boolean
  readonly onSignOut: () => void
}) {
  const clientResult = useMemo(() => getSupabaseClient(), [])
  const service = useMemo(() => clientResult.ok ? createOperationalDayService(clientResult.client) : null, [clientResult])
  const [state, setState] = useState<OperationalDayGateState>({ status: 'loading' })
  const [refreshing, setRefreshing] = useState(false)
  const handleRef = useRef<Awaited<ReturnType<typeof subscribeToOperationalDay>> | null>(null)

  const load = useCallback(async (isCurrent: () => boolean = () => true): Promise<void> => {
    if (!service) {
      setState({ status: 'error', message: 'La conexión con Supabase no está configurada correctamente.' })
      return
    }
    const result = await service.getCurrent()
    if (!isCurrent()) return
    if (!result.ok) setState({ status: 'error', message: result.error.message })
    else setState(result.data ? { status: 'open', day: result.data } : { status: 'closed' })
  }, [service])

  useEffect(() => {
    let disposed = false
    void load(() => !disposed)
    if (!clientResult.ok) return () => { disposed = true }
    void subscribeToOperationalDay(clientResult.client, () => load(() => !disposed), () => {}, { channelName: 'operational-day-signals' })
      .then((started) => {
        if (disposed) void started.stop()
        else handleRef.current = started
      })
    return () => {
      disposed = true
      const handle = handleRef.current
      handleRef.current = null
      if (handle) void handle.stop()
    }
  }, [clientResult, load])

  const resync = useCallback(async (): Promise<void> => {
    if (handleRef.current) await handleRef.current.resync()
    else await load()
  }, [load])

  const refresh = useCallback(() => {
    setRefreshing(true)
    void resync().finally(() => setRefreshing(false))
  }, [resync])

  const value = useMemo<OperationalDayContextValue>(
    () => ({ jornada: state.status === 'open' ? state.day : null, resync }),
    [resync, state],
  )

  if (state.status === 'open') {
    return <OperationalDayContext.Provider value={value}>{children}</OperationalDayContext.Provider>
  }
  if (state.status === 'closed') {
    return <LocalClosedScreen context={context} isSigningOut={isSigningOut} onRefresh={refresh} onSignOut={onSignOut} refreshing={refreshing} />
  }
  return (
    <OperationalDayStatusScreen
      error={state.status === 'error' ? state.message : null}
      isSigningOut={isSigningOut}
      onRetry={refresh}
      onSignOut={onSignOut}
    />
  )
}
