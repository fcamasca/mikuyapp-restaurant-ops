import { Fragment, useEffect, useMemo, useRef, useState } from 'react'
import AuthenticatedUserMenu from '../components/AuthenticatedUserMenu'
import {
  countPendingReception,
  createKitchenRealtimeService,
  formatKitchenAge,
  groupKitchenBoard,
  groupKitchenCancellations,
  runKitchenDetailMutation,
  settleKitchenTransitionsFromSnapshot,
  type KitchenBoardRow,
  type KitchenCancellation,
  type KitchenCommand,
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
  // E7-D08/D09: cancelaciones y comandas del snapshot; guard de recepción completa por pedido.
  const [cancellations, setCancellations] = useState<readonly KitchenCancellation[]>([])
  const [commands, setCommands] = useState<readonly KitchenCommand[]>([])
  const receivingOrders = useRef(new Set<number>())
  const [receivingIds, setReceivingIds] = useState<readonly number[]>([])
  const [orderMessages, setOrderMessages] = useState<Readonly<Record<number, string>>>({})

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
      onSnapshot(snapshot, board) {
        if (cancelled) return
        const settledIds = settleKitchenTransitionsFromSnapshot(pendingTransitions.current, snapshot)
        if (settledIds.length > 0) {
          setBusyIds((current) => current.filter((id) => !settledIds.includes(id)))
        }
        setRows(snapshot)
        setCancellations(board.cancelaciones)
        setCommands(board.comandas)
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
  const cancellationsByOrder = useMemo(() => groupKitchenCancellations(cancellations), [cancellations])
  const orphanCancellations = useMemo(
    () => cancellations.filter((item) => !groups.some((group) => group.pedidoId === item.pedido_id)),
    [cancellations, groups],
  )

  async function receiveOrder(pedidoId: number): Promise<void> {
    if (!service || receivingOrders.current.has(pedidoId)) return
    receivingOrders.current.add(pedidoId)
    setReceivingIds((current) => [...current, pedidoId])
    setOrderMessages((current) => {
      const next = { ...current }
      delete next[pedidoId]
      return next
    })
    try {
      const result = await service.receiveOrder(pedidoId)
      if (!result.ok) setOrderMessages((current) => ({ ...current, [pedidoId]: result.error.message }))
    } finally {
      receivingOrders.current.delete(pedidoId)
      setReceivingIds((current) => current.filter((id) => id !== pedidoId))
    }
    await handleRef.current?.resync()
  }

  async function transition(detail: KitchenBoardRow, next: KitchenDetailStatus): Promise<void> {
    if (!service || pendingTransitions.current.has(detail.detalle_id) || receivingOrders.current.has(detail.pedido_id)) return
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
            : groups.length === 0 && orphanCancellations.length === 0 ? <p className="mt-6 rounded-2xl border border-dashed border-stone-300 bg-white p-5 text-stone-600">No hay productos pendientes en cocina.</p>
              : <>{orphanCancellations.length > 0 && <section aria-labelledby="kitchen-cancelled-title" className="mt-6 rounded-3xl border border-rose-200 bg-rose-50 p-4 sm:p-5"><h3 className="text-lg font-bold text-rose-900" id="kitchen-cancelled-title">Productos cancelados por el mozo</h3><p className="mt-1 text-sm text-rose-800">No los prepares. Solo lectura.</p><ul className="mt-3 grid gap-2 sm:grid-cols-2">{orphanCancellations.map((item) => <li className="min-w-0 rounded-2xl border border-rose-200 bg-white p-3" key={item.detalle_id}><p className="break-words font-bold line-through">{item.producto_nombre} × {item.cantidad}</p><p className="mt-1 text-sm text-stone-700">Pedido #{item.pedido_id} · Motivo: {item.motivo}</p></li>)}</ul></section>}
              <ul className="mt-6 grid min-w-0 gap-5 xl:grid-cols-2">{groups.map((group, groupIndex) => (
                <Fragment key={group.key}>
                  {groupIndex === 0 && !group.allReady && <li className="list-none xl:col-span-2"><h3 className="text-lg font-bold text-stone-800">Trabajo pendiente</h3><p className="mt-1 text-sm text-stone-600">Pedidos que todavía requieren una acción de cocina.</p></li>}
                  {group.allReady && (groupIndex === 0 || !groups[groupIndex - 1].allReady) && <li className="mt-2 list-none border-t border-stone-300 pt-6 xl:col-span-2"><h3 className="text-lg font-bold text-emerald-900">Listos</h3><p className="mt-1 text-sm text-stone-600">Permanecen visibles hasta completar la entrega en H5.</p></li>}
                <li className="min-w-0 rounded-3xl border border-stone-200 bg-white p-4 shadow-sm sm:p-5">
                  <div className="flex flex-wrap items-start justify-between gap-3 border-b border-stone-200 pb-4">
                    <div><p className="text-xs font-semibold uppercase tracking-wide text-stone-500">Mesa {group.mesaCodigo}</p><h3 className="mt-1 text-xl font-bold">{group.mesaNombre}</h3></div>
                    <div className="text-right"><p className="font-semibold">Pedido #{group.pedidoId}</p><p className="mt-1 text-sm text-stone-600">{formatKitchenAge(group.oldestSentAt)}</p></div>
                  </div>
                  {countPendingReception(group.details) > 0 && <button aria-busy={receivingIds.includes(group.pedidoId)} className="mt-4 min-h-11 w-full rounded-xl bg-amber-800 px-4 py-3 font-bold text-white disabled:opacity-60" disabled={receivingIds.includes(group.pedidoId)} onClick={() => { void receiveOrder(group.pedidoId) }} type="button">{receivingIds.includes(group.pedidoId) ? 'Recibiendo…' : `Recibir pedido (${countPendingReception(group.details)})`}</button>}
                  {orderMessages[group.pedidoId] && <p className="mt-3 rounded-lg border border-rose-200 bg-rose-50 p-2 text-sm text-rose-800" role="status">{orderMessages[group.pedidoId]}</p>}
                  <ul className="mt-4 grid min-w-0 gap-3 sm:grid-cols-2">{group.details.map((detail) => {
                    const presentation = statusPresentation[detail.estado]
                    const busy = busyIds.includes(detail.detalle_id) || receivingIds.includes(group.pedidoId)
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
                  {(cancellationsByOrder.get(group.pedidoId) ?? []).length > 0 && <div className="mt-4 rounded-2xl border border-rose-200 bg-rose-50 p-3"><p className="text-sm font-bold text-rose-900">Cancelado por el mozo · no preparar</p><ul className="mt-2 grid gap-1">{(cancellationsByOrder.get(group.pedidoId) ?? []).map((item) => <li className="break-words text-sm text-rose-900" key={item.detalle_id}><span className="font-semibold line-through">{item.producto_nombre} × {item.cantidad}</span>{item.observacion ? ` (${item.observacion})` : ''} · Motivo: {item.motivo}</li>)}</ul></div>}
                </li></Fragment>
              ))}</ul></>}
        </section>
      </div>
    </main>
  )
}
