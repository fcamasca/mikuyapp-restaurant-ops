import { Fragment, useEffect, useMemo, useRef, useState } from 'react'
import AuthenticatedUserMenu from '../components/AuthenticatedUserMenu'
import { createCatalogService, type CatalogGroup } from '../services/catalogService'
import type { ValidatedProfileContext } from '../services/profileContext'
import { getSupabaseClient } from '../services/supabaseClient'
import { combineOrderObservation, createWaiterOrderService, type WaiterOrderDetail, type WaiterOrderReview } from '../services/waiterOrderService'

interface Props { readonly context: ValidatedProfileContext; readonly orderId: number; readonly isSigningOut: boolean; readonly onBack: () => void; readonly onSignOut: () => void }
const notes = ['Sin cebolla', 'Sin ají', 'Poco picante', 'Sin cancha'] as const
const money = new Intl.NumberFormat('es-PE', { style: 'currency', currency: 'PEN' })
export default function WaiterOrderPage({ context, orderId, isSigningOut, onBack, onSignOut }: Props) {
  const clientResult = useMemo(() => getSupabaseClient(), [])
  const orders = useMemo(() => clientResult.ok ? createWaiterOrderService(clientResult.client) : null, [clientResult])
  const catalog = useMemo(() => clientResult.ok ? createCatalogService(clientResult.client) : null, [clientResult])
  const [groups, setGroups] = useState<readonly CatalogGroup[]>([])
  const [details, setDetails] = useState<readonly WaiterOrderDetail[]>([])
  const [review, setReview] = useState<WaiterOrderReview | null>(null)
  const [category, setCategory] = useState('TODAS')
  const [mode, setMode] = useState<'ORDER' | 'CATALOG'>('CATALOG')
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState<string | null>(null)
  const [detailConflicts, setDetailConflicts] = useState<Readonly<Record<number, string>>>({})
  const [busy, setBusy] = useState<string | null>(null)
  const pendingProductIds = useRef(new Set<string>())
  const [busyDetails, setBusyDetails] = useState<readonly number[]>([])
  const pendingDetailIds = useRef(new Set<number>())
  const [attempt, setAttempt] = useState(0)
  const [editing, setEditing] = useState<number | null>(null)
  const [confirmingRemoval, setConfirmingRemoval] = useState<number | null>(null)
  const [selected, setSelected] = useState<readonly string[]>([])
  const [free, setFree] = useState('')
  const [sending, setSending] = useState(false)
  const sendingRef = useRef(false)

  async function reload(): Promise<boolean> {
    if (!orders) return false
    const result = await orders.getOrderDetails(context, orderId)
    if (!result.ok) { setError(result.error.message); return false }
    setDetails(result.data); return true
  }
  function resetDetailDraft(detailId: number) {
    if (editing === detailId) {
      setEditing(null)
      setSelected([])
      setFree('')
    }
    if (confirmingRemoval === detailId) setConfirmingRemoval(null)
  }
  function clearDetailConflict(detailId: number) {
    setDetailConflicts((current) => {
      if (!(detailId in current)) return current
      const next = { ...current }
      delete next[detailId]
      return next
    })
  }
  async function recoverDetailMutation(detailId: number, mutationError: { readonly kind: 'operation-error' | 'concurrent-conflict'; readonly message: string }) {
    if (mutationError.kind === 'concurrent-conflict') resetDetailDraft(detailId)
    const refreshed = await reload()
    if (refreshed) {
      if (mutationError.kind === 'concurrent-conflict') {
        setDetailConflicts((current) => ({ ...current, [detailId]: 'Actualizado desde otro dispositivo. Se cargó la versión más reciente.' }))
        setError(null)
      } else setError(mutationError.message)
    }
  }
  useEffect(() => {
    let cancelled = false
    async function load() {
      setLoading(true); setDetailConflicts({}); setError(null)
      if (!orders || !catalog) { setLoading(false); setError('No pudimos preparar el pedido. Intenta nuevamente.'); return }
      const [catalogResult, detailResult, reviewResult] = await Promise.all([catalog.getOperationalCatalog(context), orders.getOrderDetails(context, orderId), orders.getOrderReview(context, orderId)])
      if (cancelled) return
      setLoading(false)
      if (!catalogResult.ok) { setError(catalogResult.error.message); return }
      if (!detailResult.ok) { setError(detailResult.error.message); return }
      if (!reviewResult.ok) { setError(reviewResult.error.message); return }
      setGroups(catalogResult.data.groups); setDetails(detailResult.data)
      setReview(reviewResult.data)
      setMode(detailResult.data.length > 0 ? 'ORDER' : 'CATALOG')
    }
    void load(); return () => { cancelled = true }
  }, [attempt, catalog, context, orderId, orders])
  const visible = category === 'TODAS' ? groups : groups.filter((group) => group.category.id === category)
  const names = useMemo(() => new Map(groups.flatMap((group) => group.products.map((product) => [product.id, product.nombre] as const))), [groups])
  const requestedDetails = details.filter((detail) => detail.estado !== 'ABIERTO')
  const openDetails = details.filter((detail) => detail.estado === 'ABIERTO')
  const orderedDetails = [...requestedDetails, ...openDetails]
  const total = details.reduce((sum, detail) => sum + detail.cantidad * Number(detail.precio_unitario), 0)

  async function add(productId: string) {
    if (!orders || pendingProductIds.current.has(productId)) return
    pendingProductIds.current.add(productId)
    setBusy(`p-${productId}`); setError(null)
    try {
      const result = await orders.addOrderDetail(context, orderId, productId)
      if (!result.ok) { await reload(); setError(result.error.message) } else await reload()
    } finally {
      pendingProductIds.current.delete(productId); setBusy(null)
    }
  }
  async function quantity(detail: WaiterOrderDetail, value: number) {
    if (!orders || pendingDetailIds.current.has(detail.id) || detail.estado !== 'ABIERTO' || value < 1) return
    pendingDetailIds.current.add(detail.id)
    clearDetailConflict(detail.id)
    setBusyDetails((ids) => [...ids, detail.id]); setError(null)
    try {
      const result = await orders.updateOpenDetail(context, detail.id, { cantidad: value }, { cantidad: detail.cantidad })
      if (!result.ok) await recoverDetailMutation(detail.id, result.error); else await reload()
    } finally {
      pendingDetailIds.current.delete(detail.id); setBusyDetails((ids) => ids.filter((id) => id !== detail.id))
    }
  }
  function editObservation(detail: WaiterOrderDetail) {
    clearDetailConflict(detail.id); setError(null)
    const parts = detail.observacion?.split(',').map((part) => part.trim()).filter(Boolean) ?? []
    setSelected(notes.filter((note) => parts.includes(note)))
    setFree(parts.filter((part) => !notes.includes(part as typeof notes[number])).join(', ')); setEditing(detail.id)
  }
  async function saveObservation(detail: WaiterOrderDetail) {
    if (!orders || pendingDetailIds.current.has(detail.id) || detail.estado !== 'ABIERTO') return
    pendingDetailIds.current.add(detail.id)
    clearDetailConflict(detail.id)
    setBusyDetails((ids) => [...ids, detail.id]); setError(null)
    try {
      const result = await orders.updateOpenDetail(context, detail.id, { observacion: combineOrderObservation(selected, free) }, { observacion: detail.observacion })
      if (!result.ok) await recoverDetailMutation(detail.id, result.error)
      else if (await reload()) { setEditing(null); setSelected([]); setFree('') }
    } finally {
      pendingDetailIds.current.delete(detail.id); setBusyDetails((ids) => ids.filter((id) => id !== detail.id))
    }
  }
  async function remove(detail: WaiterOrderDetail) {
    if (!orders || pendingDetailIds.current.has(detail.id) || detail.estado !== 'ABIERTO') return
    pendingDetailIds.current.add(detail.id)
    clearDetailConflict(detail.id)
    setBusyDetails((ids) => [...ids, detail.id]); setError(null)
    try {
      const result = await orders.removeOpenDetail(context, detail.id)
      if (!result.ok) await recoverDetailMutation(detail.id, result.error)
      else { await reload(); setConfirmingRemoval(null) }
    } finally {
      pendingDetailIds.current.delete(detail.id); setBusyDetails((ids) => ids.filter((id) => id !== detail.id))
    }
  }

  async function sendToKitchen() {
    if (!orders || sendingRef.current || openDetails.length === 0) return
    sendingRef.current = true; setSending(true); setError(null)
    try {
      const result = await orders.sendOrderToKitchen(context, orderId)
      const refreshed = await reload()
      if (!result.ok) setError(result.error.message)
      else if (!refreshed) setError('El envío fue confirmado, pero no pudimos actualizar la vista. Reintenta la carga.')
    } finally {
      sendingRef.current = false; setSending(false)
    }
  }

  return <main className="min-h-screen overflow-x-hidden bg-stone-100 px-3 py-5 text-stone-900 sm:px-6 lg:px-8"><div className="mx-auto min-w-0 max-w-7xl">
    <header className="flex flex-col gap-4 sm:flex-row sm:items-center sm:justify-between"><div><p className="text-sm font-semibold uppercase tracking-[0.18em] text-emerald-700">Pedido vigente</p><h1 className="mt-2 text-2xl font-bold sm:text-3xl">{review ? `${review.mesa.codigo} · ${review.mesa.nombre}` : `Pedido #${orderId}`}</h1><p className="mt-1 text-sm text-stone-600">Pedido #{orderId}</p></div><div className="grid gap-2 sm:flex"><button className="min-h-11 w-full rounded-xl border bg-white px-4 py-3 font-semibold sm:w-auto" onClick={onBack} type="button">Volver a mesas</button><AuthenticatedUserMenu context={context} isSigningOut={isSigningOut} onSignOut={onSignOut} /></div></header>
    {error && <div className="mt-5 rounded-xl border border-rose-200 bg-rose-50 p-3 text-rose-800" role="alert"><p>{error}</p><button className="mt-2 min-h-11 rounded-xl border border-rose-300 px-4 font-semibold" onClick={() => setAttempt((n) => n + 1)} type="button">Reintentar</button></div>}
    {loading ? <p aria-busy="true" className="mt-8">Cargando pedido y productos…</p> : <div className="mt-8 min-w-0">
      {mode === 'CATALOG' && <section className="min-w-0 rounded-3xl border bg-white p-4 shadow-sm sm:p-6"><div className="flex flex-col gap-3 sm:flex-row sm:items-center sm:justify-between"><div><h2 className="text-xl font-bold">Agregar productos</h2>{details.length > 0 && <p className="mt-1 text-sm text-stone-600">{details.length} líneas · Total {money.format(total)}</p>}</div>{details.length > 0 && <button className="min-h-11 rounded-xl border border-stone-300 px-4 font-semibold" onClick={() => setMode('ORDER')} type="button">Volver al pedido</button>}</div><div className="mt-4 flex gap-2 overflow-x-auto pb-2" aria-label="Filtrar por categoría"><button className={`min-h-11 shrink-0 rounded-full px-4 font-semibold ${category === 'TODAS' ? 'bg-emerald-800 text-white' : 'border'}`} onClick={() => setCategory('TODAS')} type="button">Todas</button>{groups.map((group) => <button className={`min-h-11 shrink-0 rounded-full px-4 font-semibold ${category === group.category.id ? 'bg-emerald-800 text-white' : 'border'}`} key={group.category.id} onClick={() => setCategory(group.category.id)} type="button">{group.category.nombre}</button>)}</div>
        {visible.length === 0 ? <p className="mt-6">No hay productos disponibles.</p> : visible.map((group) => <div className="mt-6" key={group.category.id}><h3 className="font-bold">{group.category.nombre}</h3><ul className="mt-3 grid min-w-0 gap-3 sm:grid-cols-2">{group.products.map((product) => <li className="flex min-w-0 flex-col rounded-2xl border p-4" key={product.id}><strong className="break-words text-lg">{product.nombre}</strong><span className="mt-1 text-stone-600">{money.format(product.precio)}</span><button aria-busy={busy === `p-${product.id}`} className="mt-4 min-h-12 rounded-xl bg-emerald-800 px-4 font-bold text-white disabled:opacity-60" disabled={Boolean(busy)} onClick={() => { void add(product.id) }} type="button">{busy === `p-${product.id}` ? 'Agregando…' : 'Agregar'}</button></li>)}</ul></div>)}
      </section>}
      {mode === 'ORDER' && <section className="min-w-0 rounded-3xl border bg-white p-4 shadow-sm sm:p-6"><div className="flex flex-col gap-3 sm:flex-row sm:items-center sm:justify-between"><div><h2 className="text-xl font-bold">Pedido actual</h2><p className="mt-1 text-2xl font-bold text-emerald-900">Total {money.format(total)}</p></div><div className="grid gap-2 sm:grid-cols-2"><button className="min-h-12 rounded-xl border border-emerald-700 px-5 font-bold text-emerald-900" disabled={sending} onClick={() => setMode('CATALOG')} type="button">+ Agregar productos</button>{openDetails.length > 0 && <button aria-busy={sending} className="min-h-12 rounded-xl bg-emerald-800 px-5 font-bold text-white disabled:opacity-60" disabled={sending} onClick={() => { void sendToKitchen() }} type="button">{sending ? 'Enviando…' : 'Enviar a cocina'}</button>}</div></div>{details.length === 0 ? <p className="mt-4 text-stone-600">Aún no agregaste productos.</p> : <ul className="mt-6 grid gap-4">{orderedDetails.map((detail, index) => { const open = detail.estado === 'ABIERTO'; const detailBusy = busyDetails.includes(detail.id); const detailConflict = detailConflicts[detail.id]; const removing = detailBusy && confirmingRemoval === detail.id; const productName = names.get(detail.producto_id) ?? 'Producto'; const detailAmount = detail.cantidad * Number(detail.precio_unitario); return <Fragment key={detail.id}>{index === 0 && requestedDetails.length > 0 && <li className="list-none"><h3 className="text-lg font-bold text-stone-700">Ya solicitado</h3><p className="text-sm text-stone-500">Solo lectura</p></li>}{index === requestedDetails.length && openDetails.length > 0 && <li className="mt-2 list-none"><h3 className="text-lg font-bold text-emerald-800">Por enviar</h3><p className="text-sm text-stone-500">Puedes ajustar estos productos</p></li>}<li aria-busy={detailBusy || sending} className="min-w-0 rounded-2xl border p-4"><div className="flex items-start justify-between gap-3"><div className="min-w-0"><h3 className="break-words font-bold">{productName}</h3><p className="mt-1 text-sm text-stone-600">{money.format(detail.precio_unitario)}{detail.cantidad > 1 && ` · Importe ${money.format(detailAmount)}`}{!open && ` · Estado: ${detail.estado}`}</p></div>{open ? <button aria-label={`Retirar ${productName}`} className="grid h-11 w-11 shrink-0 place-items-center rounded-xl border border-stone-200 bg-transparent text-stone-500 transition-colors hover:border-rose-200 hover:bg-rose-50 hover:text-rose-700 active:bg-rose-100 disabled:opacity-50" disabled={detailBusy || sending} onClick={() => setConfirmingRemoval(detail.id)} type="button"><svg aria-hidden="true" className="h-5 w-5" fill="none" stroke="currentColor" strokeLinecap="round" strokeLinejoin="round" strokeWidth="2" viewBox="0 0 24 24"><path d="M3 6h18" /><path d="M8 6V4h8v2" /><path d="M19 6l-1 14H6L5 6" /><path d="M10 11v5" /><path d="M14 11v5" /></svg></button> : <strong className="shrink-0">× {detail.cantidad}</strong>}</div>{detail.observacion && <p className="mt-3 break-words text-sm text-stone-700">{detail.observacion}</p>}{detailConflict && <p className="mt-3 rounded-xl border border-amber-200 bg-amber-50 p-3 text-sm font-semibold text-amber-900" role="status">{detailConflict}</p>}
          {open ? <><div className="mt-4 grid grid-cols-3 gap-2"><button aria-label="Disminuir cantidad" className="min-h-11 rounded-xl border text-xl font-bold disabled:opacity-40" disabled={detailBusy || sending || detail.cantidad <= 1} onClick={() => { void quantity(detail, detail.cantidad - 1) }} type="button">−</button><span className="grid min-h-11 place-items-center rounded-xl bg-stone-100 font-bold">{detail.cantidad}</span><button aria-label="Aumentar cantidad" className="min-h-11 rounded-xl border text-xl font-bold" disabled={detailBusy || sending} onClick={() => { void quantity(detail, detail.cantidad + 1) }} type="button">+</button></div>
                {editing === detail.id ? <div className="mt-4 rounded-xl bg-stone-50 p-3"><p className="text-sm font-bold">Observaciones frecuentes</p><div className="mt-2 grid grid-cols-2 gap-2">{notes.map((note) => { const active = selected.includes(note); return <button aria-pressed={active} className={`min-h-11 rounded-xl border px-2 text-sm font-semibold ${active ? 'border-emerald-700 bg-emerald-50' : ''}`} disabled={detailBusy} key={note} onClick={() => setSelected(active ? selected.filter((item) => item !== note) : [...selected, note])} type="button">{note}</button> })}</div><label className="mt-3 block text-sm font-bold">Otra…<textarea className="mt-1 min-h-24 w-full min-w-0 rounded-xl border p-3 text-base" disabled={detailBusy} onChange={(event) => setFree(event.target.value)} value={free} /></label><div className="mt-3 grid grid-cols-2 gap-2"><button className="min-h-11 rounded-xl border font-semibold" disabled={detailBusy} onClick={() => setEditing(null)} type="button">Cancelar</button><button className="min-h-11 rounded-xl bg-emerald-800 font-semibold text-white" disabled={detailBusy} onClick={() => { void saveObservation(detail) }} type="button">{detailBusy ? 'Actualizando…' : 'Guardar'}</button></div></div> : <button className="mt-3 min-h-11 rounded-xl border px-3 font-semibold" disabled={detailBusy} onClick={() => editObservation(detail)} type="button">{detail.observacion ? 'Editar observación' : 'Agregar observación'}</button>}
                {detailBusy && !removing && <p className="mt-3 text-center text-sm font-semibold text-emerald-800" role="status">Actualizando…</p>}
                {confirmingRemoval === detail.id && <div className="mt-3 rounded-xl border border-rose-200 bg-rose-50 p-3"><p className="text-sm font-semibold text-rose-900">¿Retirar {productName}?</p><div className="mt-3 grid grid-cols-2 gap-2"><button className="min-h-11 rounded-xl border border-stone-300 font-semibold" disabled={detailBusy} onClick={() => setConfirmingRemoval(null)} type="button">Cancelar</button><button className="min-h-11 rounded-xl bg-rose-700 font-semibold text-white disabled:opacity-60" disabled={detailBusy} onClick={() => { void remove(detail) }} type="button">{removing ? '⏳ Retirando…' : 'Retirar'}</button></div></div>}</> : <p className="mt-4 rounded-xl bg-stone-100 p-3 text-sm font-semibold text-stone-600">Este detalle ya fue enviado y no se puede editar ni retirar.</p>}
        </li></Fragment>})}</ul>}</section>}
    </div>}
  </div></main>
}
