import { useCallback, useEffect, useMemo, useRef, useState } from 'react'
import AuthenticatedUserMenu from '../components/AuthenticatedUserMenu'
import { createCashierService, type CashierPendingOrder, type PersistedPayment } from '../services/cashierService'
import type { ValidatedProfileContext } from '../services/profileContext'
import { subscribeToOperationsChanges } from '../services/operationsRealtimeService.ts'
import { getSupabaseClient } from '../services/supabaseClient'
import type { PaymentMethodCode } from '../types/operations'

interface Props {
  readonly context: ValidatedProfileContext
  readonly isSigningOut: boolean
  readonly onSignOut: () => void
}

const methods: readonly PaymentMethodCode[] = ['EFECTIVO', 'YAPE', 'PLIN', 'TARJETA']
const money = new Intl.NumberFormat('es-PE', { style: 'currency', currency: 'PEN' })
const dateTime = new Intl.DateTimeFormat('es-PE', { dateStyle: 'short', timeStyle: 'short', timeZone: 'America/Lima' })

function Consumption({ order }: { readonly order: CashierPendingOrder }) {
  return <div className="document-table-scroll overflow-x-auto"><table className="document-table mt-4 w-full min-w-[34rem] text-left text-sm"><thead className="border-b border-stone-200 text-stone-600"><tr><th className="py-2 pr-3">Producto</th><th className="px-3 py-2 text-right">Cant.</th><th className="px-3 py-2 text-right">P. unitario</th><th className="py-2 pl-3 text-right">Importe</th></tr></thead><tbody>{order.lines.map((line) => <tr className="border-b border-stone-100" key={line.detailId}><td className="py-3 pr-3 font-medium">{line.productName}</td><td className="px-3 py-3 text-right">{line.quantity}</td><td className="px-3 py-3 text-right">{money.format(line.unitPrice)}</td><td className="py-3 pl-3 text-right font-semibold">{money.format(line.lineAmount)}</td></tr>)}</tbody></table></div>
}

function DocumentView({ kind, localName, order, payment, onClose }: { readonly kind: 'PRECUENTA' | 'TICKET'; readonly localName: string; readonly order: CashierPendingOrder; readonly payment: PersistedPayment | null; readonly onClose: () => void }) {
  const documentDate = payment?.paidAt ?? order.createdAt
  return <div aria-label={kind === 'PRECUENTA' ? 'Precuenta' : 'Ticket interno'} className="print-overlay fixed inset-0 z-40 overflow-y-auto bg-stone-950/50 p-3 sm:p-8"><section className="print-document mx-auto max-w-xl rounded-3xl bg-white p-5 text-stone-950 shadow-xl sm:p-7"><div className="flex items-start justify-between gap-4"><div><p className="text-sm font-bold uppercase tracking-widest text-emerald-800">{localName}</p><h2 className="mt-2 text-2xl font-bold">{kind === 'PRECUENTA' ? 'Precuenta' : 'Ticket interno'}</h2><p className="mt-1 text-sm text-stone-600">Pedido #{order.orderId} · Mesa {order.tableCode} · {order.tableName}</p><p className="mt-1 text-sm text-stone-600">Fecha/hora: {dateTime.format(new Date(documentDate))} · America/Lima</p></div><div className="no-print flex shrink-0 flex-col gap-2 sm:flex-row"><button className="min-h-11 rounded-xl bg-stone-950 px-4 py-2 font-semibold text-white" onClick={() => window.print()} type="button">Imprimir</button><button className="min-h-11 rounded-xl border border-stone-300 px-4 py-2 font-semibold" onClick={onClose} type="button">Cerrar</button></div></div><Consumption order={order} /><p className="mt-5 flex justify-between border-t-2 border-stone-900 pt-4 text-xl font-bold"><span>Total</span><span>{money.format(payment?.amount ?? order.total)}</span></p>{kind === 'PRECUENTA' ? <p className="mt-3 text-sm text-stone-500">Documento informativo · Pedido pendiente de pago</p> : payment && <div className="payment-summary mt-4 rounded-xl bg-stone-100 p-3 text-sm"><p>Pago #{payment.paymentId}</p><p className="mt-1">Medio de pago: <strong>{payment.method}</strong></p></div>}</section></div>
}

export default function CashierPage({ context, isSigningOut, onSignOut }: Props) {
  const clientResult = useMemo(() => getSupabaseClient(), [])
  const service = useMemo(() => clientResult.ok ? createCashierService(clientResult.client) : null, [clientResult])
  const [orders, setOrders] = useState<readonly CashierPendingOrder[]>([])
  const [selectedId, setSelectedId] = useState<number | null>(null)
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState<string | null>(null)
  const [attempt, setAttempt] = useState(0)
  const [method, setMethod] = useState<PaymentMethodCode>('EFECTIVO')
  const [confirming, setConfirming] = useState(false)
  const [paying, setPaying] = useState(false)
  const payingRef = useRef(false)
  const [payment, setPayment] = useState<PersistedPayment | null>(null)
  const [paidOrder, setPaidOrder] = useState<CashierPendingOrder | null>(null)
  const [document, setDocument] = useState<'PRECUENTA' | 'TICKET' | null>(null)

  const load = useCallback(async (showLoading = false, isCurrent: () => boolean = () => true): Promise<readonly CashierPendingOrder[] | null> => {
    if (showLoading) setLoading(true)
    if (!service) { setLoading(false); setError('No pudimos conectar con caja.'); return null }
    const result = await service.getPendingOrders(context)
    if (!isCurrent()) return null
    setLoading(false)
    if (!result.ok) { setError(result.error.message); return null }
    setOrders(result.data)
    setSelectedId((current) => result.data.some((order) => order.orderId === current) ? current : result.data[0]?.orderId ?? null)
    setError(null)
    return result.data
  }, [context, service])

  useEffect(() => { void load(true) }, [attempt, load])

  useEffect(() => {
    if (!clientResult.ok) return
    let disposed = false
    let handle: Awaited<ReturnType<typeof subscribeToOperationsChanges>> | null = null
    void subscribeToOperationsChanges(
      clientResult.client,
      () => load(false, () => !disposed).then(() => undefined),
      () => {
        if (!disposed) setError('La conexión en tiempo real se interrumpió. Estamos recuperando la caja.')
      },
      { channelName: 'cashier-orders-signals', initialRefresh: false },
    ).then((started) => {
      if (disposed) void started.stop()
      else handle = started
    })
    return () => {
      disposed = true
      if (handle) void handle.stop()
    }
  }, [clientResult, load])
  const selected = orders.find((order) => order.orderId === selectedId) ?? null

  async function pay(): Promise<void> {
    if (!service || !selected || payingRef.current) return
    payingRef.current = true
    setPaying(true)
    setError(null)
    try {
      const result = await service.registerPayment(context, selected.orderId, method)
      if (!result.ok) {
        setConfirming(false)
        const refreshed = await load(false)
        setError(refreshed && !refreshed.some((order) => order.orderId === selected.orderId)
          ? 'Este pedido ya fue procesado. La lista de caja está actualizada.'
          : result.error.message)
        return
      }
      setPaidOrder(selected)
      setPayment(result.data)
      setConfirming(false)
      await load(false)
    } finally {
      payingRef.current = false
      setPaying(false)
    }
  }

  const shownDocumentOrder = document === 'TICKET' ? paidOrder : selected

  return <main className="min-h-screen overflow-x-hidden bg-stone-100 px-3 py-5 text-stone-900 sm:px-6 sm:py-8 lg:px-8"><div className="mx-auto max-w-7xl"><header className="flex flex-col items-start justify-between gap-4 sm:flex-row"><div><p className="text-sm font-semibold uppercase tracking-[0.18em] text-emerald-700">MikuyApp · Caja</p><h1 className="mt-2 text-2xl font-bold sm:text-3xl">Cobros pendientes</h1><p className="mt-2 text-sm text-stone-600">{context.local.nombre} · Horario America/Lima</p></div><AuthenticatedUserMenu context={context} isSigningOut={isSigningOut} onSignOut={onSignOut} /></header>
    {error && <div className="mt-5 rounded-xl border border-rose-200 bg-rose-50 p-4"><p role="alert" className="text-sm text-rose-800">{error}</p><button className="mt-3 min-h-11 rounded-lg border border-rose-300 px-4 font-semibold" onClick={() => setAttempt((value) => value + 1)} type="button">Reintentar</button></div>}
    {payment && paidOrder && <section aria-live="polite" className="mt-5 rounded-2xl border border-emerald-300 bg-emerald-50 p-4"><h2 className="font-bold text-emerald-950">Pago registrado</h2><p className="mt-1 text-sm text-emerald-900">Pedido #{payment.orderId} · {payment.method} · {money.format(payment.amount)} · mesa liberada</p><button className="mt-3 min-h-11 rounded-xl bg-emerald-900 px-4 py-2 font-bold text-white" onClick={() => setDocument('TICKET')} type="button">Abrir ticket interno</button></section>}
    <div className="mt-6 grid min-w-0 gap-5 lg:grid-cols-[minmax(17rem,22rem)_minmax(0,1fr)]"><section className="rounded-3xl border border-stone-200 bg-white p-4 shadow-sm"><h2 className="text-lg font-bold">Mesas pendientes de pago</h2>{loading ? <p aria-busy="true" className="mt-5 text-sm text-stone-600">Cargando pedidos pendientes…</p> : orders.length === 0 ? <p className="mt-5 rounded-xl border border-dashed border-stone-300 p-4 text-sm text-stone-600">No hay pedidos pendientes de pago.</p> : <ul className="mt-4 space-y-3">{orders.map((order) => <li key={order.orderId}><button aria-pressed={selectedId === order.orderId} className={`min-h-16 w-full rounded-xl border p-3 text-left ${selectedId === order.orderId ? 'border-emerald-700 bg-emerald-50' : 'border-stone-200 bg-white'}`} onClick={() => { setSelectedId(order.orderId); setConfirming(false) }} type="button"><span className="block font-bold">Mesa {order.tableCode} · Pedido #{order.orderId}</span><span className="mt-1 block text-sm text-stone-600">{order.tableName} · {money.format(order.total)}</span></button></li>)}</ul>}</section>
      <section className="min-w-0 rounded-3xl border border-stone-200 bg-white p-4 shadow-sm sm:p-6">{selected ? <><div className="flex flex-col justify-between gap-3 sm:flex-row"><div><p className="text-sm font-semibold text-emerald-800">ENTREGADO · PENDIENTE_PAGO</p><h2 className="mt-1 text-2xl font-bold">Pedido #{selected.orderId}</h2><p className="mt-1 text-stone-600">Mesa {selected.tableCode} · {selected.tableName}</p></div><button className="min-h-11 rounded-xl border border-stone-300 px-4 py-2 font-semibold" onClick={() => setDocument('PRECUENTA')} type="button">Abrir precuenta</button></div><Consumption order={selected} /><p className="mt-5 flex justify-between border-t-2 border-stone-900 pt-4 text-xl font-bold"><span>Total autoritativo</span><span>{money.format(selected.total)}</span></p><fieldset className="mt-6"><legend className="font-bold">Medio de pago</legend><div className="mt-3 grid gap-2 sm:grid-cols-2 xl:grid-cols-4">{methods.map((value) => <label className={`flex min-h-12 cursor-pointer items-center gap-2 rounded-xl border px-3 ${method === value ? 'border-emerald-700 bg-emerald-50' : 'border-stone-300'}`} key={value}><input checked={method === value} disabled={paying} name="payment-method" onChange={() => setMethod(value)} type="radio" />{value}</label>)}</div></fieldset>{confirming ? <div className="mt-5 rounded-2xl border border-amber-300 bg-amber-50 p-4"><p className="font-bold">¿Confirmar cobro de {money.format(selected.total)} mediante {method}?</p><p className="mt-1 text-sm text-stone-600">Esta operación registrará el pago y liberará la mesa.</p><div className="mt-4 flex flex-col gap-2 sm:flex-row"><button aria-busy={paying} className="min-h-12 rounded-xl bg-emerald-900 px-5 font-bold text-white disabled:opacity-60" disabled={paying} onClick={() => { void pay() }} type="button">{paying ? 'Registrando pago…' : 'Confirmar y cobrar'}</button><button className="min-h-12 rounded-xl border border-stone-300 px-5 font-semibold" disabled={paying} onClick={() => setConfirming(false)} type="button">Cancelar</button></div></div> : <button className="mt-6 min-h-12 w-full rounded-xl bg-stone-950 px-5 font-bold text-white disabled:opacity-60" disabled={paying} onClick={() => setConfirming(true)} type="button">Cobrar pedido</button>}</> : <div className="grid min-h-64 place-items-center text-center text-stone-600"><div><h2 className="font-bold text-stone-900">Selecciona un pedido</h2><p className="mt-2 text-sm">El detalle del consumo aparecerá aquí.</p></div></div>}</section></div></div>
    {document && shownDocumentOrder && <DocumentView kind={document} localName={context.local.nombre} onClose={() => setDocument(null)} order={shownDocumentOrder} payment={document === 'TICKET' ? payment : null} />}
  </main>
}
