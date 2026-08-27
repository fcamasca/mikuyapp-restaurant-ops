import { useEffect, useMemo, useRef, useState } from 'react'
import type { ValidatedProfileContext } from '../services/profileContext'
import { getSupabaseClient } from '../services/supabaseClient'
import {
  createWaiterOrderService,
  filterAndSortWaiterTables,
  type WaiterTableBoardItem,
  type WaiterTableFilter,
  type WaiterTableOrder,
} from '../services/waiterOrderService'
import type { TableStatusCode } from '../types/operations'

interface WaiterTablesPageProps {
  readonly context: ValidatedProfileContext
  readonly isSigningOut: boolean
  readonly onOpenOrder: (orderId: number) => void
  readonly onSignOut: () => void
  readonly onNavigateToTechnical: () => void
}

const tableStatuses: Record<TableStatusCode, {
  readonly label: string
  readonly description: string
  readonly className: string
  readonly badgeClassName: string
}> = {
  LIBRE: { label: 'Libre', description: 'Disponible para tomar pedido', className: 'border-emerald-200 bg-emerald-50/70', badgeClassName: 'bg-emerald-800 text-white' },
  OCUPADA: { label: 'Ocupada', description: 'Mesa en atención', className: 'border-amber-200 bg-amber-50/70', badgeClassName: 'bg-amber-700 text-white' },
  PEDIDO_LISTO: { label: 'Pedido listo', description: 'Preparado para entregar', className: 'border-sky-200 bg-sky-50/70', badgeClassName: 'bg-sky-800 text-white' },
  PENDIENTE_PAGO: { label: 'Pendiente de pago', description: 'Mesa pendiente de cobro', className: 'border-violet-200 bg-violet-50/70', badgeClassName: 'bg-violet-800 text-white' },
}

const filters: readonly { value: WaiterTableFilter; label: string }[] = [
  { value: 'TODAS', label: 'Todas' },
  { value: 'LIBRE', label: 'Libres' },
  { value: 'OCUPADA', label: 'Ocupadas' },
  { value: 'PEDIDO_LISTO', label: 'Pedido listo' },
  { value: 'PENDIENTE_PAGO', label: 'Pendiente de pago' },
]

const moneyFormatter = new Intl.NumberFormat('es-PE', { style: 'currency', currency: 'PEN' })

export default function WaiterTablesPage({ context, isSigningOut, onOpenOrder, onSignOut, onNavigateToTechnical }: WaiterTablesPageProps) {
  const clientResult = useMemo(() => getSupabaseClient(), [])
  const service = useMemo(() => clientResult.ok ? createWaiterOrderService(clientResult.client) : null, [clientResult])
  const [tables, setTables] = useState<readonly WaiterTableBoardItem[]>([])
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState<string | null>(null)
  const [attempt, setAttempt] = useState(0)
  const [filter, setFilter] = useState<WaiterTableFilter>('TODAS')
  const [order, setOrder] = useState<WaiterTableOrder>('ASC')
  const [openingTableId, setOpeningTableId] = useState<string | null>(null)
  const openingTableRef = useRef<string | null>(null)
  const [actionError, setActionError] = useState<string | null>(null)

  useEffect(() => {
    let cancelled = false
    async function loadBoard(): Promise<void> {
      setLoading(true)
      setError(null)
      if (!service) {
        setLoading(false)
        setError('No pudimos cargar las mesas. Intenta nuevamente.')
        return
      }
      const result = await service.getTableBoard(context)
      if (cancelled) return
      setLoading(false)
      if (!result.ok) {
        setTables([])
        setError(result.error.message)
        return
      }
      setTables(result.data)
    }
    void loadBoard()
    return () => { cancelled = true }
  }, [attempt, context, service])

  const visibleTables = useMemo(() => filterAndSortWaiterTables(tables, filter, order), [filter, order, tables])

  async function handleTableAction(table: WaiterTableBoardItem): Promise<void> {
    if (openingTableRef.current) return
    if (table.pedido) {
      onOpenOrder(table.pedido.id)
      return
    }
    if (table.estado !== 'LIBRE' || !service) return
    openingTableRef.current = table.id
    setOpeningTableId(table.id)
    setActionError(null)
    try {
      const result = await service.createOrRecoverOrder(context, table.id)
      if (!result.ok) {
        setActionError(result.error.message)
        return
      }
      onOpenOrder(result.data.pedidoId)
    } finally {
      openingTableRef.current = null
      setOpeningTableId(null)
    }
  }

  return (
    <main className="min-h-screen overflow-x-hidden bg-stone-100 px-3 py-5 text-stone-900 sm:px-6 sm:py-8 lg:px-8">
      <div className="mx-auto min-w-0 max-w-6xl">
        <header className="flex min-w-0 flex-col items-start justify-between gap-4 sm:flex-row">
          <div className="min-w-0">
            <p className="text-sm font-semibold uppercase tracking-[0.18em] text-emerald-700">MikuyApp · Atención de mesas</p>
            <h1 className="mt-2 break-words text-2xl font-bold tracking-tight sm:text-3xl">Selecciona una mesa</h1>
            <p className="mt-2 text-sm text-stone-600">Consulta el consumo y continúa el pedido vigente.</p>
          </div>
          <nav className="flex w-full flex-wrap gap-3 sm:w-auto">
            <button className="min-h-11 flex-1 rounded-xl border border-stone-300 bg-white px-4 py-3 text-sm font-semibold sm:flex-none" onClick={onNavigateToTechnical} type="button">Verificación técnica</button>
            <button aria-busy={isSigningOut} className="min-h-11 flex-1 rounded-xl bg-emerald-800 px-4 py-3 text-sm font-semibold text-white disabled:opacity-70 sm:flex-none" disabled={isSigningOut} onClick={onSignOut} type="button">{isSigningOut ? 'Cerrando sesión…' : 'Cerrar sesión'}</button>
          </nav>
        </header>

        <section aria-labelledby="waiter-tables-title" className="mt-8 min-w-0 rounded-3xl border border-stone-200 bg-white p-4 shadow-sm sm:p-6">
          <div className="flex min-w-0 flex-col gap-4 lg:flex-row lg:items-end lg:justify-between">
            <div className="min-w-0">
              <h2 className="text-xl font-semibold" id="waiter-tables-title">Tablero de mesas</h2>
              <p className="mt-2 text-sm text-stone-600">Mesas activas de tu local.</p>
            </div>
            <div className="grid min-w-0 gap-3 sm:grid-cols-2">
              <label className="min-w-0 text-sm font-semibold text-stone-700">Filtrar por estado
                <select className="mt-1 min-h-11 w-full min-w-0 rounded-xl border border-stone-300 bg-white px-3 py-2 text-base" onChange={(event) => setFilter(event.target.value as WaiterTableFilter)} value={filter}>
                  {filters.map((option) => <option key={option.value} value={option.value}>{option.label}</option>)}
                </select>
              </label>
              <label className="min-w-0 text-sm font-semibold text-stone-700">Ordenar mesas
                <select className="mt-1 min-h-11 w-full min-w-0 rounded-xl border border-stone-300 bg-white px-3 py-2 text-base" onChange={(event) => setOrder(event.target.value as WaiterTableOrder)} value={order}>
                  <option value="ASC">Código ascendente</option><option value="DESC">Código descendente</option>
                </select>
              </label>
            </div>
          </div>

          <ul aria-label="Leyenda de estados de mesas" className="mt-5 grid min-w-0 gap-2 sm:grid-cols-2 lg:grid-cols-4">
            {Object.entries(tableStatuses).map(([code, status]) => <li className={`min-w-0 break-words rounded-xl border px-3 py-2 text-sm ${status.className}`} key={code}><span className="font-semibold">{status.label}:</span> {status.description}</li>)}
          </ul>
          {actionError && <p className="mt-5 rounded-xl border border-rose-200 bg-rose-50 p-3 text-sm text-rose-800" role="alert">{actionError}</p>}

          {loading ? <p aria-busy="true" className="mt-6 text-sm text-stone-600">Cargando mesas…</p>
            : error ? <div className="mt-6 rounded-2xl border border-rose-200 bg-rose-50 p-4"><p className="text-sm text-rose-800" role="alert">{error}</p><button className="mt-3 min-h-11 w-full rounded-lg border border-rose-300 px-3 py-2 text-sm font-semibold text-rose-900 sm:w-auto" onClick={() => setAttempt((value) => value + 1)} type="button">Reintentar mesas</button></div>
              : tables.length === 0 ? <p className="mt-6 rounded-2xl border border-dashed border-stone-300 p-4 text-sm text-stone-600">No hay mesas disponibles</p>
                : visibleTables.length === 0 ? <p className="mt-6 rounded-2xl border border-dashed border-stone-300 p-4 text-sm text-stone-600">No hay mesas para este filtro</p>
                  : <ul className="mt-6 grid min-w-0 gap-4 sm:grid-cols-2 xl:grid-cols-3">{visibleTables.map((table) => {
                    const status = tableStatuses[table.estado]
                    const isOpening = openingTableId === table.id
                    const unavailable = !table.pedido && table.estado !== 'LIBRE'
                    return <li className={`flex min-w-0 flex-col break-words rounded-2xl border p-4 shadow-sm ${status.className}`} key={table.id}>
                      <div className="flex min-w-0 items-start justify-between gap-3"><div className="min-w-0"><p className="text-xs font-semibold uppercase tracking-wide text-stone-600">{table.codigo}</p><h3 className="mt-1 break-words text-xl font-bold text-stone-950">{table.nombre}</h3></div><span className={`shrink-0 rounded-full px-3 py-1 text-xs font-bold ${status.badgeClassName}`}>{status.label}</span></div>
                      <p className="mt-3 text-sm text-stone-700">Estado: <strong>{status.label}</strong></p>
                      <div className="mt-4 rounded-xl bg-white/80 p-3"><p className="text-xs font-semibold uppercase tracking-wide text-stone-500">Total vigente</p><p className="mt-1 text-xl font-bold text-stone-950">{table.pedido ? moneyFormatter.format(table.pedido.total) : 'Sin consumo'}</p></div>
                      <button aria-busy={isOpening} className="mt-4 min-h-12 w-full rounded-xl bg-stone-900 px-4 py-3 text-base font-bold text-white disabled:cursor-not-allowed disabled:opacity-55" disabled={Boolean(openingTableId) || unavailable} onClick={() => { void handleTableAction(table) }} type="button">{isOpening ? 'Abriendo pedido…' : table.pedido ? 'Ver pedido' : table.estado === 'LIBRE' ? 'Tomar pedido' : 'Pedido no disponible'}</button>
                    </li>
                  })}</ul>}
        </section>
      </div>
    </main>
  )
}
