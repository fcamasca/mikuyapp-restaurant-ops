import { useCallback, useEffect, useMemo, useState } from 'react'
import AuthenticatedUserMenu from '../components/AuthenticatedUserMenu'
import { createSalesService, csv, type DailyCashSummary, type SessionCashReport } from '../services/salesService'
import type { ValidatedProfileContext } from '../services/profileContext'
import { getSupabaseClient } from '../services/supabaseClient'

const methods = ['EFECTIVO', 'YAPE', 'PLIN', 'TARJETA']
const money = new Intl.NumberFormat('es-PE', { style: 'currency', currency: 'PEN' })
const downloadCsv = (name: string, snapshot: Record<string, unknown>) => {
  const href = URL.createObjectURL(new Blob([csv([snapshot])], { type: 'text/csv;charset=utf-8' }))
  const link = document.createElement('a'); link.href = href; link.download = name; link.click(); URL.revokeObjectURL(href)
}
const sessionCsv = (row: SessionCashReport): Record<string, unknown> => ({
  sesion: row.sessionId, caja: row.cashbox, estado: row.status, abierta_por: row.openedBy,
  cerrada_por: row.closedBy, abierta_en: row.openedAt, cerrada_en: row.closedAt,
  monto_inicial: row.initialAmount, ...Object.fromEntries(methods.map((m) => [`venta_${m.toLowerCase()}`, row.salesByMethod[m]])),
  ...Object.fromEntries(methods.map((m) => [`propina_${m.toLowerCase()}`, row.tipsByMethod[m]])),
  entradas: row.entries, salidas: row.exits, efectivo_esperado: row.expectedCash,
  efectivo_contado: row.countedCash, diferencia: row.difference, descuentos: row.discounts,
  anulaciones: row.annulments, pagos: row.payments, pagos_parciales: row.partialPayments,
  pedidos_completados: row.completedOrders,
})
const dailyCsv = (row: DailyCashSummary): Record<string, unknown> => ({
  fecha_operativa: row.operationalDate, total_vendido: row.totalSold,
  ...Object.fromEntries(methods.map((m) => [`venta_${m.toLowerCase()}`, row.salesByMethod[m]])),
  total_propinas: row.totalTips, ...Object.fromEntries(methods.map((m) => [`propina_${m.toLowerCase()}`, row.tipsByMethod[m]])),
  descuentos: row.discounts, anulaciones: row.annulments, pagos: row.payments,
  pagos_parciales: row.partialPayments, pedidos_completados: row.completedOrders,
})

export default function SalesPage({ context, isSigningOut, onBack, onSignOut }: { readonly context: ValidatedProfileContext; readonly isSigningOut: boolean; readonly onBack: () => void; readonly onSignOut: () => void }) {
  const client = useMemo(() => getSupabaseClient(), [])
  const service = useMemo(() => client.ok ? createSalesService(client.client) : null, [client])
  const [daily, setDaily] = useState<DailyCashSummary | null>(null)
  const [sessions, setSessions] = useState<readonly SessionCashReport[]>([])
  const [sessionId, setSessionId] = useState('')
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState<string | null>(null)
  const load = useCallback(async () => {
    if (!service) { setError('No pudimos conectar con ventas.'); setLoading(false); return }
    setLoading(true)
    const [day, history] = await Promise.all([service.getDailyCashSummary(context), service.getSessionReports(context)])
    if (!day.ok || !history.ok) setError(!day.ok ? day.error : history.ok ? '' : history.error)
    else { setDaily(day.data); setSessions(history.data); setSessionId((old) => history.data.some((x) => x.sessionId === old) ? old : history.data[0]?.sessionId ?? ''); setError(null) }
    setLoading(false)
  }, [context, service])
  useEffect(() => { void load() }, [load])
  const selected = sessions.find((row) => row.sessionId === sessionId) ?? null
  return <main className="min-h-screen bg-stone-100 px-4 py-6 text-stone-900"><div className="mx-auto max-w-6xl"><header className="flex flex-wrap items-start justify-between gap-4"><div><p className="text-sm font-semibold uppercase tracking-widest text-emerald-700">MikuyApp · Caja</p><h1 className="mt-2 text-3xl font-bold">Reportes operativos</h1><p className="mt-2 text-stone-600">{context.local.nombre} · America/Lima</p></div><div className="flex items-center gap-3"><button onClick={onBack} type="button">{context.role.codigo === 'CAJA' ? 'Volver a cobros pendientes' : 'Volver al catálogo'}</button><AuthenticatedUserMenu context={context} isSigningOut={isSigningOut} onSignOut={onSignOut} /></div></header>
  {error && <div className="mt-5 rounded-xl bg-rose-50 p-4"><p role="alert">{error}</p><button onClick={() => void load()}>Reintentar</button></div>}
  {loading ? <p className="mt-6" aria-busy="true">Cargando reportes…</p> : daily && <><section className="mt-6 rounded-3xl bg-white p-6 shadow-sm"><div className="flex flex-wrap justify-between gap-3"><div><p className="text-sm text-stone-600">Total vendido · {daily.operationalDate}</p><p className="mt-2 text-4xl font-bold">{money.format(daily.totalSold)}</p></div><button onClick={() => downloadCsv(`mikuyapp-resumen-${daily.operationalDate}.csv`, dailyCsv(daily))}>Exportar resumen CSV</button></div><div className="mt-6 grid gap-3 sm:grid-cols-4">{methods.map((method) => <div className="rounded-2xl border p-4" key={method}><b>{method}</b><p>{money.format(daily.salesByMethod[method] ?? 0)}</p><small>Propina {money.format(daily.tipsByMethod[method] ?? 0)}</small></div>)}</div><div className="mt-5 grid gap-3 sm:grid-cols-5"><p>Propinas<br/><b>{money.format(daily.totalTips)}</b></p><p>Descuentos<br/><b>{money.format(daily.discounts)}</b></p><p>Anulaciones<br/><b>{daily.annulments}</b></p><p>Pagos/parciales<br/><b>{daily.payments}/{daily.partialPayments}</b></p><p>Pedidos completados<br/><b>{daily.completedOrders}</b></p></div></section>
  <section className="mt-6 rounded-3xl bg-white p-6 shadow-sm"><div className="flex flex-wrap justify-between gap-3"><label>Sesión<select value={sessionId} onChange={(e) => setSessionId(e.target.value)}>{sessions.map((row) => <option value={row.sessionId} key={row.sessionId}>{row.cashbox} · {new Date(row.openedAt).toLocaleString('es-PE')}</option>)}</select></label>{selected && <button onClick={() => downloadCsv(`mikuyapp-sesion-${selected.sessionId}.csv`, sessionCsv(selected))}>Exportar sesión CSV</button>}</div>{selected ? <div className="mt-5"><h2 className="text-xl font-bold">{selected.cashbox} · {selected.status}</h2><p>Abierta por {selected.openedBy} · Cerrada por {selected.closedBy ?? '—'}</p><div className="mt-4 grid gap-3 sm:grid-cols-4">{methods.map((method) => <p key={method}>{method}<br/><b>{money.format(selected.salesByMethod[method] ?? 0)}</b><br/><small>Propina {money.format(selected.tipsByMethod[method] ?? 0)}</small></p>)}</div><div className="mt-5 grid gap-3 sm:grid-cols-4"><p>Inicial<br/><b>{money.format(selected.initialAmount)}</b></p><p>Entradas / salidas<br/><b>{money.format(selected.entries)} / {money.format(selected.exits)}</b></p><p>Esperado / contado<br/><b>{money.format(selected.expectedCash)} / {selected.countedCash == null ? '—' : money.format(selected.countedCash)}</b></p><p>Diferencia<br/><b>{selected.difference == null ? '—' : money.format(selected.difference)}</b></p><p>Descuentos<br/><b>{money.format(selected.discounts)}</b></p><p>Anulaciones<br/><b>{selected.annulments}</b></p><p>Pagos / parciales<br/><b>{selected.payments} / {selected.partialPayments}</b></p><p>Pedidos completados<br/><b>{selected.completedOrders}</b></p></div></div> : <p className="mt-4">No hay sesiones para mostrar.</p>}</section></>}</div></main>
}
