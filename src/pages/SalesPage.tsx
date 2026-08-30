import { useCallback, useEffect, useMemo, useState } from 'react'
import AuthenticatedUserMenu from '../components/AuthenticatedUserMenu'
import { createSalesService, csv } from '../services/salesService'
import type { ValidatedProfileContext } from '../services/profileContext'
import { getSupabaseClient } from '../services/supabaseClient'

const methods = ['EFECTIVO', 'YAPE', 'PLIN', 'TARJETA']
const money = new Intl.NumberFormat('es-PE', { style: 'currency', currency: 'PEN' })

export default function SalesPage({ context, isSigningOut, onSignOut }: { readonly context: ValidatedProfileContext; readonly isSigningOut: boolean; readonly onSignOut: () => void }) {
  const client = useMemo(() => getSupabaseClient(), [])
  const service = useMemo(() => client.ok ? createSalesService(client.client) : null, [client])
  const [summary, setSummary] = useState<readonly { method: string; paidOrders: number; amount: number }[]>([])
  const [error, setError] = useState<string | null>(null)
  const load = useCallback(async () => { if (!service) return setError('No pudimos conectar con ventas.') ; const result = await service.getSummary(context); if (result.ok) { setSummary(result.data); setError(null) } else setError(result.error) }, [context, service])
  useEffect(() => { void load() }, [load])
  async function download(kind: 'sales' | 'products'): Promise<void> { if (!service) return; const result = kind === 'sales' ? await service.exportSales(context) : await service.exportProducts(context); if (!result.ok) { setError(result.error); return }; const content = csv(result.data as unknown as Record<string, unknown>[]); const href = URL.createObjectURL(new Blob([content], { type: 'text/csv;charset=utf-8' })); const link = document.createElement('a'); link.href = href; link.download = `mikuyapp-${kind}-${new Date().toISOString().slice(0, 10)}.csv`; link.click(); URL.revokeObjectURL(href) }
  const total = summary.reduce((sum, row) => sum + row.amount, 0)
  return <main className="min-h-screen bg-stone-100 px-4 py-6 text-stone-900"><div className="mx-auto max-w-5xl"><header className="flex items-start justify-between gap-4"><div><p className="text-sm font-semibold uppercase tracking-widest text-emerald-700">MikuyApp · Ventas</p><h1 className="mt-2 text-3xl font-bold">Resumen del día</h1><p className="mt-2 text-stone-600">{context.local.nombre} · America/Lima</p></div><AuthenticatedUserMenu context={context} isSigningOut={isSigningOut} onSignOut={onSignOut} /></header>{error && <p role="alert" className="mt-5 rounded-xl bg-rose-50 p-4 text-rose-800">{error}</p>}<section className="mt-6 rounded-3xl bg-white p-6 shadow-sm"><p className="text-sm text-stone-600">Total vendido hoy</p><p className="mt-2 text-4xl font-bold">{money.format(total)}</p><div className="mt-6 grid gap-3 sm:grid-cols-4">{methods.map((method) => { const row = summary.find((item) => item.method === method); return <div className="rounded-2xl border border-stone-200 p-4" key={method}><p className="text-sm font-semibold">{method}</p><p className="mt-2 text-xl font-bold">{money.format(row?.amount ?? 0)}</p><p className="text-xs text-stone-500">{row?.paidOrders ?? 0} pedidos pagados</p></div> })}</div>{context.role.codigo === 'ADMINISTRADOR' && <div className="mt-8 flex flex-wrap gap-3"><button className="rounded-xl bg-stone-900 px-4 py-3 font-semibold text-white" onClick={() => void download('sales')} type="button">Descargar ventas CSV</button><button className="rounded-xl border border-stone-300 px-4 py-3 font-semibold" onClick={() => void download('products')} type="button">Descargar productos CSV</button></div>}</section></div></main>
}
