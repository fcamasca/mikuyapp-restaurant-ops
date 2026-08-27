import { useEffect, useMemo, useRef, useState } from 'react'
import AuthenticatedUserMenu from '../components/AuthenticatedUserMenu'
import {
  createKitchenRealtimeService,
  formatKitchenAge,
  groupKitchenBoard,
  runKitchenDetailMutation,
  settleKitchenTransitionsFromSnapshot,
  type KitchenBoardRow,
  type KitchenDetailStatus,
  type KitchenRealtimeHandle,
} from '../services/kitchenRealtimeService'
import type { ValidatedProfileContext } from '../services/profileContext'
import { getSupabaseClient } from '../services/supabaseClient'

interface KitchenBoardPageProps {
  readonly context: ValidatedProfileContext
  readonly isSigningOut: boolean
  readonly onSignOut: () => void
}

const statusPresentation: Record<KitchenDetailStatus, {
  readonly label: string
  readonly cardClass: string
  readonly badgeClass: string
  readonly action: { readonly label: string; readonly next: KitchenDetailStatus } | null
}> = {
  ENVIADO: {
    label: 'Nuevo · Por recibir',
    cardClass: 'border-amber-200 bg-amber-50/70',
    badgeClass: 'bg-amber-800 text-white',
    action: { label: 'Recibir', next: 'RECIBIDO_COCINA' },
  },
  RECIBIDO_COCINA: {
    label: 'Recibido',
    cardClass: 'border-sky-200 bg-sky-50/70',
    badgeClass: 'bg-sky-800 text-white',
    action: { label: 'Iniciar preparación', next: 'EN_PREPARACION' },
  },
  EN_PREPARACION: {
    label: 'En preparación',
    cardClass: 'border-violet-200 bg-violet-50/70',
    badgeClass: 'bg-violet-800 text-white',
    action: { label: 'Marcar listo', next: 'LISTO' },
  },
  LISTO: {
    label: 'Listo',
    cardClass: 'border-emerald-200 bg-emerald-50/70',
    badgeClass: 'bg-emerald-800 text-white',
    action: null,
  },
}

export default function KitchenBoardPage({ context, isSigningOut, onSignOut }: KitchenBoardPageProps) {
  const clientResult = useMemo(() => getSupabaseClient(), [])
  const service = useMemo(
    () => clientResult.ok ? createKitchenRealtimeService(clientResult.client) : null,
    [clientResult],
  )
  const handleRef = useRef<KitchenRealtimeHandle | null>(null)
  const pendingTransitions = useRef(new Map<number, { expectedStatus: KitchenDetailStatus; token: symbol }>())
  const [rows, setRows] = useState<readonly KitchenBoardRow[]>([])
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState<string | null>(null)
  const [busyIds, setBusyIds] = useState<readonly number[]>([])
  const [detailMessages, setDetailMessages] = useState<Readonly<Record<number, string>>>({})

  useEffect(() => {
    let cancelled = false
    let activeHandle: KitchenRealtimeHandle | null = null

    if (!service || context.role.codigo !== 'COCINA') {
      setLoading(false)
      setError('No pudimos iniciar el tablero de cocina.')
      return undefined
    }

    setLoading(true)
    void service.start({
      onSnapshot(snapshot) {
        if (cancelled) return
        const settledIds = settleKitchenTransitionsFromSnapshot(pendingTransitions.current, snapshot)
        if (settledIds.length > 0) {
          setBusyIds((current) => current.filter((id) => !settledIds.includes(id)))
        }
        setRows(snapshot)
        setLoading(false)
        setError(null)
      },
      onError(message) {
        if (cancelled) return
        setLoading(false)
        setError(message)
      },
    }).then((handle) => {
      if (cancelled) {
        void handle.stop()
        return
      }
      activeHandle = handle
      handleRef.current = handle
    })

    return () => {
      cancelled = true
      handleRef.current = null
      if (activeHandle) void activeHandle.stop()
    }
  }, [context.role.codigo, service])

  const groups = useMemo(() => groupKitchenBoard(rows), [rows])

  async function transition(detail: KitchenBoardRow, next: KitchenDetailStatus): Promise<void> {
    if (!service || pendingTransitions.current.has(detail.detalle_id)) return
    const operationToken = Symbol(`kitchen-detail-${detail.detalle_id}`)
    pendingTransitions.current.set(detail.detalle_id, {
      expectedStatus: detail.estado,
      token: operationToken,
    })
    setBusyIds((current) => [...current, detail.detalle_id])
    setDetailMessages((current) => {
      const nextMessages = { ...current }
      delete nextMessages[detail.detalle_id]
      return nextMessages
    })
    await runKitchenDetailMutation({
      operation: () => service.transitionDetail(detail.detalle_id, detail.estado, next),
      onResult(result) {
        if (pendingTransitions.current.get(detail.detalle_id)?.token !== operationToken) return
        if (!result.ok) {
          setDetailMessages((current) => ({ ...current, [detail.detalle_id]: result.error.message }))
        }
      },
      releasePending() {
        if (pendingTransitions.current.get(detail.detalle_id)?.token !== operationToken) return
        pendingTransitions.current.delete(detail.detalle_id)
        setBusyIds((current) => current.filter((id) => id !== detail.detalle_id))
      },
      resync: async () => { await handleRef.current?.resync() },
    })
  }

  return (
    <main className="min-h-screen overflow-x-hidden bg-stone-100 px-3 py-5 text-stone-900 sm:px-6 sm:py-8 lg:px-8">
      <div className="mx-auto min-w-0 max-w-7xl">
        <header className="flex min-w-0 items-start justify-between gap-4">
          <div className="min-w-0">
            <p className="text-sm font-semibold uppercase tracking-[0.18em] text-emerald-700">MikuyApp · Cocina</p>
            <h1 className="mt-2 text-2xl font-bold tracking-tight sm:text-3xl">Pedidos en cocina</h1>
            <p className="mt-2 text-sm text-stone-600">Procesa cada producto según su estado confirmado.</p>
          </div>
          <AuthenticatedUserMenu context={context} isSigningOut={isSigningOut} onSignOut={onSignOut} />
        </header>

        <section aria-labelledby="kitchen-board-title" className="mt-7">
          <div className="flex flex-wrap items-end justify-between gap-3">
            <div>
              <h2 className="text-xl font-semibold" id="kitchen-board-title">Cola operativa</h2>
              <p className="mt-1 text-sm text-stone-600">Ordenada por el envío más antiguo pendiente.</p>
            </div>
            <button
              className="min-h-11 rounded-xl border border-stone-300 bg-white px-4 py-2 text-sm font-semibold"
              onClick={() => { void handleRef.current?.resync() }}
              type="button"
            >
              Actualizar
            </button>
          </div>

          {error && <div className="mt-5 rounded-2xl border border-rose-200 bg-rose-50 p-4" role="alert"><p className="text-sm text-rose-800">{error}</p><button className="mt-3 min-h-11 rounded-xl border border-rose-300 px-4 py-2 font-semibold text-rose-900" onClick={() => { void handleRef.current?.resync() }} type="button">Reintentar</button></div>}
          {loading ? <p aria-busy="true" className="mt-6 rounded-2xl bg-white p-5 text-stone-600">Cargando pedidos de cocina…</p>
            : groups.length === 0 ? <p className="mt-6 rounded-2xl border border-dashed border-stone-300 bg-white p-5 text-stone-600">No hay productos pendientes en cocina.</p>
              : <ul className="mt-6 grid min-w-0 gap-5 xl:grid-cols-2">{groups.map((group) => (
                <li className="min-w-0 rounded-3xl border border-stone-200 bg-white p-4 shadow-sm sm:p-5" key={group.key}>
                  <div className="flex flex-wrap items-start justify-between gap-3 border-b border-stone-200 pb-4">
                    <div><p className="text-xs font-semibold uppercase tracking-wide text-stone-500">Mesa {group.mesaCodigo}</p><h3 className="mt-1 text-xl font-bold">{group.mesaNombre}</h3></div>
                    <div className="text-right"><p className="font-semibold">Pedido #{group.pedidoId}</p><p className="mt-1 text-sm text-stone-600">{formatKitchenAge(group.oldestSentAt)}</p></div>
                  </div>
                  <ul className="mt-4 grid min-w-0 gap-3 sm:grid-cols-2">{group.details.map((detail) => {
                    const presentation = statusPresentation[detail.estado]
                    const busy = busyIds.includes(detail.detalle_id)
                    const message = detailMessages[detail.detalle_id]
                    return <li className={`min-w-0 rounded-2xl border p-4 ${presentation.cardClass}`} key={detail.detalle_id}>
                      <div className="flex min-w-0 items-start justify-between gap-3"><div className="min-w-0"><h4 className="break-words text-lg font-bold">{detail.producto_nombre}</h4><p className="mt-1 text-sm font-semibold">Cantidad: {detail.cantidad}</p></div><span className={`shrink-0 rounded-full px-3 py-1 text-xs font-bold ${presentation.badgeClass}`}>{presentation.label}</span></div>
                      <p className="mt-3 text-sm text-stone-700">{formatKitchenAge(detail.enviado_en)}</p>
                      <p className="mt-2 min-h-5 break-words text-sm text-stone-700">{detail.observacion ? `Observación: ${detail.observacion}` : 'Sin observaciones'}</p>
                      {message && <p className="mt-3 rounded-lg border border-rose-200 bg-white/80 p-2 text-sm text-rose-800" role="status">{message}</p>}
                      {presentation.action ? <button aria-busy={busy} className="mt-4 min-h-11 w-full rounded-xl bg-stone-900 px-4 py-3 font-bold text-white disabled:opacity-60" disabled={busy} onClick={() => { void transition(detail, presentation.action!.next) }} type="button">{busy ? 'Actualizando…' : presentation.action.label}</button>
                        : <p className="mt-4 rounded-xl border border-emerald-300 bg-white/70 px-4 py-3 text-center font-semibold text-emerald-900">Preparación completada</p>}
                    </li>
                  })}</ul>
                </li>
              ))}</ul>}
        </section>
      </div>
    </main>
  )
}
