import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import { createAdminCashService, type AdminOrder } from "../services/cashierService";
import type { ValidatedProfileContext } from "../services/profileContext";
import { getSupabaseClient } from "../services/supabaseClient";

const cancellableStates = new Set(["ABIERTO", "ENVIADO", "RECIBIDO_COCINA", "EN_PREPARACION", "LISTO", "ENTREGADO"]);
const operationalWarningStates = new Set(["EN_PREPARACION", "LISTO", "ENTREGADO"]);
const money = new Intl.NumberFormat("es-PE", { style: "currency", currency: "PEN" });
const updatedAtFormatter = new Intl.DateTimeFormat("es-PE", {
  day: "2-digit",
  month: "2-digit",
  year: "numeric",
  hour: "2-digit",
  minute: "2-digit",
});
const textCollator = new Intl.Collator("es-PE", { numeric: true, sensitivity: "base" });
type OrderSort = "UPDATED_DESC" | "UPDATED_ASC" | "TABLE" | "STATUS" | "BALANCE_DESC" | "BALANCE_ASC";

function canCancel(order: AdminOrder): boolean {
  return !order.hasPayments && cancellableStates.has(order.orderStatus);
}

function blockedReason(order: AdminOrder): string {
  if (order.hasPayments) return "Bloqueado por pago";
  if (["PAGADO", "ANULADO"].includes(order.orderStatus)) return "Estado terminal";
  return "No anulable";
}

export default function AdminOrdersPage({ context }: { readonly context: ValidatedProfileContext }) {
  const clientResult = useMemo(() => getSupabaseClient(), []);
  const service = useMemo(() => clientResult.ok ? createAdminCashService(clientResult.client) : null, [clientResult]);
  const [orders, setOrders] = useState<readonly AdminOrder[]>([]);
  const [cancellableOnly, setCancellableOnly] = useState(true);
  const [sortBy, setSortBy] = useState<OrderSort>("UPDATED_DESC");
  const [loading, setLoading] = useState(true);
  const [pageError, setPageError] = useState<string | null>(clientResult.ok ? null : clientResult.error.message);
  const [feedback, setFeedback] = useState<string | null>(null);
  const [selected, setSelected] = useState<AdminOrder | null>(null);
  const [reason, setReason] = useState("");
  const [operationError, setOperationError] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);
  const requestLock = useRef(false);
  const idempotencyKey = useRef<string | null>(null);

  const load = useCallback(async (showLoading = true) => {
    if (!service) {
      setLoading(false);
      return;
    }
    if (showLoading) setLoading(true);
    setPageError(null);
    const result = await service.getOrders(context);
    if (result.ok) setOrders(result.data);
    else setPageError(result.error.message);
    if (showLoading) setLoading(false);
  }, [context, service]);

  useEffect(() => { void load(); }, [load]);

  const visibleOrders = [...(cancellableOnly ? orders.filter(canCancel) : orders)].sort((left, right) => {
    switch (sortBy) {
      case "UPDATED_ASC": return Date.parse(left.updatedAt) - Date.parse(right.updatedAt) || left.orderId - right.orderId;
      case "TABLE": return textCollator.compare(left.tableCode, right.tableCode) || right.orderId - left.orderId;
      case "STATUS": return textCollator.compare(left.orderStatus, right.orderStatus) || Date.parse(right.updatedAt) - Date.parse(left.updatedAt);
      case "BALANCE_DESC": return right.balance - left.balance || Date.parse(right.updatedAt) - Date.parse(left.updatedAt);
      case "BALANCE_ASC": return left.balance - right.balance || Date.parse(right.updatedAt) - Date.parse(left.updatedAt);
      default: return Date.parse(right.updatedAt) - Date.parse(left.updatedAt) || right.orderId - left.orderId;
    }
  });

  function startCancellation(order: AdminOrder): void {
    setSelected(order);
    setReason("");
    setOperationError(null);
    setFeedback(null);
    idempotencyKey.current = crypto.randomUUID();
  }

  function closeConfirmation(): void {
    if (busy) return;
    setSelected(null);
    setReason("");
    setOperationError(null);
    idempotencyKey.current = null;
  }

  async function confirmCancellation(): Promise<void> {
    if (!service || !selected || !reason.trim() || requestLock.current) return;
    requestLock.current = true;
    setBusy(true);
    setOperationError(null);
    const order = selected;
    try {
      const result = await service.annul(context, order.orderId, reason.trim(), idempotencyKey.current ?? crypto.randomUUID());
      await load(false);
      if (result.ok) {
        setSelected(null);
        setReason("");
        idempotencyKey.current = null;
        setFeedback(`Pedido #${order.orderId} anulado correctamente.`);
      } else {
        setOperationError(result.error.message);
      }
    } catch {
      setOperationError("No se pudo completar la anulación. Revisa los datos e inténtalo nuevamente.");
      await load(false);
    } finally {
      setBusy(false);
      requestLock.current = false;
    }
  }

  return <main className="mx-auto max-w-6xl px-3 py-5 sm:px-6 sm:py-7">
    <p className="text-sm font-semibold uppercase tracking-[0.16em] text-emerald-700">Operación</p>
    <h1 className="mt-1 text-2xl font-bold sm:text-3xl">Pedidos</h1>
    <p className="mt-2 text-sm text-stone-600">Consulta los pedidos actuales del local y anula directamente los que aún no tienen pagos.</p>

    <section className="mt-6 rounded-3xl border border-stone-200 bg-white p-4 shadow-sm sm:p-6" aria-labelledby="orders-title">
      <div className="flex flex-wrap items-start justify-between gap-3">
        <div><h2 className="text-xl font-bold" id="orders-title">Pedidos del local</h2><p className="mt-1 text-sm text-stone-600">Vista de sólo consulta, excepto la anulación administrativa disponible.</p></div>
        {!loading && !pageError && <div className="flex flex-wrap items-end justify-end gap-3">
          <label className="text-xs font-semibold text-stone-600">Ordenar por
            <select className="mt-1 block min-h-11 max-w-full rounded-xl border border-stone-300 bg-white px-3 text-sm font-semibold text-stone-800 outline-none focus:border-emerald-700 focus:ring-4 focus:ring-emerald-100" onChange={(event) => setSortBy(event.target.value as OrderSort)} value={sortBy}>
              <option value="UPDATED_DESC">Última actualización: reciente primero</option>
              <option value="UPDATED_ASC">Última actualización: antigua primero</option>
              <option value="TABLE">Mesa</option>
              <option value="STATUS">Estado</option>
              <option value="BALANCE_DESC">Saldo: mayor primero</option>
              <option value="BALANCE_ASC">Saldo: menor primero</option>
            </select>
          </label>
          <label className="flex min-h-11 cursor-pointer items-center gap-2 rounded-xl border border-stone-300 bg-white px-3 text-sm font-semibold text-stone-800">
            <input checked={cancellableOnly} className="peer sr-only" onChange={(event) => setCancellableOnly(event.target.checked)} role="switch" type="checkbox" />
            <span aria-hidden="true" className="relative h-6 w-11 shrink-0 rounded-full bg-stone-300 transition peer-checked:bg-emerald-700 peer-focus-visible:ring-4 peer-focus-visible:ring-emerald-200 after:absolute after:left-0.5 after:top-0.5 after:size-5 after:rounded-full after:bg-white after:shadow-sm after:transition-transform peer-checked:after:translate-x-5" />
            <span>Sólo anulables</span>
          </label>
          <span className="rounded-full bg-stone-100 px-3 py-1 text-xs font-bold text-stone-700">{visibleOrders.length} de {orders.length} pedidos</span>
        </div>}
      </div>

      {feedback && <p className="mt-4 rounded-xl border border-emerald-200 bg-emerald-50 p-3 font-semibold text-emerald-900" role="status">{feedback}</p>}
      {pageError && <div className="mt-4 rounded-xl border border-rose-200 bg-rose-50 p-4 text-rose-900" role="alert"><p>{pageError}</p><button className="mt-3 min-h-11 rounded-xl border border-rose-300 bg-white px-4 text-sm font-bold hover:bg-rose-100" onClick={() => void load()} type="button">Reintentar</button></div>}
      {loading ? <p aria-busy="true" className="mt-5 rounded-xl bg-stone-50 p-4 text-stone-600">Cargando pedidos…</p>
        : !pageError && orders.length === 0 ? <p className="mt-5 rounded-xl bg-stone-50 p-4 font-semibold text-stone-700">No hay pedidos actuales en el local.</p>
        : !pageError && visibleOrders.length === 0 ? <p className="mt-5 rounded-xl bg-emerald-50 p-4 font-semibold text-emerald-900">No hay pedidos anulables. Desactiva el filtro para consultar todos.</p>
        : !pageError && <div className="mt-5" role="table" aria-label="Pedidos actuales del local">
          <div className="hidden grid-cols-[minmax(6rem,1fr)_minmax(6rem,.8fr)_minmax(9rem,1fr)_minmax(10rem,1.2fr)_minmax(9rem,.8fr)] gap-3 border-b border-stone-200 bg-stone-50 px-4 py-3 text-xs font-bold uppercase tracking-wide text-stone-600 md:grid" role="row">
            {['Mesa', 'Pedido', 'Estado', 'Cuenta', 'Acción'].map((label) => <span key={label} role="columnheader">{label}</span>)}
          </div>
          <div className="divide-y divide-stone-200 border-y border-stone-200 md:border-t-0">
            {visibleOrders.map((order) => {
              const eligible = canCancel(order);
              return <article className="grid grid-cols-2 gap-x-4 gap-y-3 px-3 py-4 md:grid-cols-[minmax(6rem,1fr)_minmax(6rem,.8fr)_minmax(9rem,1fr)_minmax(10rem,1.2fr)_minmax(9rem,.8fr)] md:items-center md:px-4" key={order.orderId} role="row">
                <div role="cell"><span className="block text-xs font-semibold text-stone-500 md:hidden">Mesa</span><span className="font-bold">{order.tableCode}</span>{order.tableName && order.tableName !== order.tableCode && <span className="block text-xs text-stone-500">{order.tableName}</span>}</div>
                <div role="cell"><span className="block text-xs font-semibold text-stone-500 md:hidden">Pedido</span><span className="font-bold">#{order.orderId}</span></div>
                <div role="cell"><span className="block text-xs font-semibold text-stone-500 md:hidden">Estado</span><span className="inline-flex rounded-full bg-stone-100 px-2.5 py-1 text-xs font-bold text-stone-800">{order.orderStatus.replaceAll('_', ' ')}</span><span className="mt-1 block text-xs text-stone-500">Actualizado {updatedAtFormatter.format(new Date(order.updatedAt))}</span></div>
                <dl className="grid grid-cols-[auto_1fr] gap-x-2 gap-y-1 text-sm" role="cell"><dt className="font-medium text-stone-500">Total</dt><dd className="text-right font-semibold md:text-left">{money.format(order.netTotal)}</dd><dt className="font-medium text-stone-500">Saldo</dt><dd className="text-right font-bold md:text-left">{money.format(order.balance)}</dd></dl>
                <div className="flex items-center md:justify-start" role="cell"><span className="sr-only md:hidden">Acción: </span>{eligible ? <button className="min-h-11 rounded-xl border border-rose-300 bg-white px-4 text-sm font-bold text-rose-800 hover:bg-rose-50 focus:outline-none focus:ring-4 focus:ring-rose-100" onClick={() => startCancellation(order)} type="button">Anular</button> : <span className="text-sm font-semibold text-stone-500">{blockedReason(order)}</span>}</div>
              </article>;
            })}
          </div>
        </div>}
    </section>

    {selected && <div className="fixed inset-0 z-50 flex items-center justify-center bg-stone-950/55 p-3" role="presentation" onPointerDown={(event) => { if (event.target === event.currentTarget) closeConfirmation(); }}>
      <section aria-labelledby="annul-order-title" aria-modal="true" className="w-full max-w-lg rounded-3xl bg-white p-5 shadow-2xl sm:p-6" role="dialog">
        <p className="text-xs font-bold uppercase tracking-[0.16em] text-rose-700">Confirmación requerida</p>
        <h2 className="mt-1 text-2xl font-bold" id="annul-order-title">Anular pedido</h2>
        <dl className="mt-4 grid grid-cols-2 gap-3 rounded-2xl bg-stone-50 p-4 text-sm">
          <div><dt className="text-stone-500">Mesa</dt><dd className="font-bold">{selected.tableCode}</dd></div>
          <div><dt className="text-stone-500">Pedido</dt><dd className="font-bold">#{selected.orderId}</dd></div>
          <div><dt className="text-stone-500">Estado</dt><dd className="font-bold">{selected.orderStatus.replaceAll('_', ' ')}</dd></div>
          <div><dt className="text-stone-500">Pago</dt><dd className="font-bold">Sin pagos</dd></div>
        </dl>
        {operationalWarningStates.has(selected.orderStatus) && <p className="mt-4 rounded-xl border border-amber-300 bg-amber-50 p-3 font-semibold text-amber-950">Advertencia: el pedido ya avanzó operativamente. Anularlo puede afectar el trabajo de Cocina o Mozo.</p>}
        <p className="mt-4 rounded-xl border border-rose-200 bg-rose-50 p-3 text-sm text-rose-950">La anulación será directa, cambiará el pedido a ANULADO y aplicará la consistencia de mesa definida por el sistema.</p>
        <label className="mt-4 block text-sm font-semibold text-stone-800">Motivo de anulación
          <textarea autoFocus className="mt-1 min-h-24 w-full resize-y rounded-xl border border-stone-300 px-3 py-2 font-normal outline-none focus:border-emerald-700 focus:ring-4 focus:ring-emerald-100" maxLength={500} onChange={(event) => setReason(event.target.value)} placeholder="Describe el motivo obligatorio" value={reason} />
        </label>
        {operationError && <p className="mt-3 rounded-xl bg-rose-50 p-3 text-sm font-semibold text-rose-800" role="alert">{operationError}</p>}
        <div className="mt-5 flex flex-col-reverse gap-2 sm:flex-row sm:justify-end">
          <button className="min-h-11 rounded-xl border border-stone-300 bg-white px-5 text-sm font-semibold disabled:opacity-50" disabled={busy} onClick={closeConfirmation} type="button">Volver</button>
          <button aria-busy={busy} className="min-h-11 rounded-xl bg-rose-700 px-5 text-sm font-bold text-white hover:bg-rose-800 disabled:cursor-not-allowed disabled:opacity-50" disabled={busy || !reason.trim()} onClick={() => void confirmCancellation()} type="button">{busy ? "Anulando…" : "Confirmar anulación"}</button>
        </div>
      </section>
    </div>}
  </main>;
}
