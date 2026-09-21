import { useCallback, useEffect, useMemo, useState } from "react";
import { createAdminCashService, type AdminDiscount } from "../services/cashierService";
import { createCashNotificationService, type CashNotification } from "../services/cashNotificationService";
import type { ValidatedProfileContext } from "../services/profileContext";
import { createSalesService, type DailyCashSummary, type SessionCashReport } from "../services/salesService";
import { getSupabaseClient } from "../services/supabaseClient";

const methods = ["EFECTIVO", "YAPE", "PLIN", "TARJETA"] as const;
const money = new Intl.NumberFormat("es-PE", { style: "currency", currency: "PEN" });
const date = new Intl.DateTimeFormat("es-PE", { timeZone: "America/Lima" });
const time = new Intl.DateTimeFormat("es-PE", { hour: "2-digit", minute: "2-digit", timeZone: "America/Lima" });

export default function AdminHomePage({ context, onCash, onPending }: { readonly context: ValidatedProfileContext; readonly onCash: () => void; readonly onPending: () => void }) {
  const client = useMemo(() => getSupabaseClient(), []);
  const sales = useMemo(() => client.ok ? createSalesService(client.client) : null, [client]);
  const cash = useMemo(() => client.ok ? createAdminCashService(client.client) : null, [client]);
  const notifications = useMemo(() => client.ok ? createCashNotificationService(client.client) : null, [client]);
  const [daily, setDaily] = useState<DailyCashSummary | null>(null);
  const [sessions, setSessions] = useState<readonly SessionCashReport[]>([]);
  const [discounts, setDiscounts] = useState<readonly AdminDiscount[]>([]);
  const [alerts, setAlerts] = useState<readonly CashNotification[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  const load = useCallback(async () => {
    if (!sales || !cash || !notifications) { setError("No pudimos conectar con el resumen del local."); setLoading(false); return; }
    setLoading(true);
    const [day, sessionRows, discountRows, notificationRows] = await Promise.all([
      sales.getDailyCashSummary(context), sales.getSessionReports(context), cash.getDiscounts(context), notifications.getNotifications(context),
    ]);
    if (!day.ok) setError(day.error);
    else if (!sessionRows.ok) setError(sessionRows.error);
    else if (!discountRows.ok) setError(discountRows.error.message);
    else if (!notificationRows.ok) setError(notificationRows.error.message);
    else {
      setDaily(day.data); setSessions(sessionRows.data);
      setDiscounts(discountRows.data.filter((item) => item.estado === "PENDIENTE"));
      setAlerts(notificationRows.data.notifications.filter((item) => item.type === "CIERRE" && item.priority === "ALERTA" && !item.readAt));
      setError(null);
    }
    setLoading(false);
  }, [cash, context, notifications, sales]);
  useEffect(() => { void load(); }, [load]);

  const activeSession = sessions.find((item) => item.status === "ABIERTA") ?? null;
  const attentionCount = discounts.length + alerts.length;
  const average = daily && daily.completedOrders > 0 ? daily.totalSold / daily.completedOrders : 0;
  const maxMethod = Math.max(0, ...methods.map((method) => daily?.salesByMethod[method] ?? 0));

  return <main className="mx-auto max-w-7xl px-3 py-5 sm:px-6 sm:py-7">
    <div className="flex flex-wrap items-end justify-between gap-3"><div><p className="text-sm font-semibold uppercase tracking-[0.16em] text-emerald-700">Inicio</p><h1 className="mt-1 text-2xl font-bold sm:text-3xl">Resumen del local</h1><p className="mt-1 text-sm text-stone-600">{context.local.nombre} · {date.format(new Date())}</p></div><button className="min-h-11 rounded-xl border border-stone-300 bg-white px-4 text-sm font-semibold" disabled={loading} onClick={() => void load()} type="button">Actualizar</button></div>
    {error && <div className="mt-5 rounded-xl border border-rose-200 bg-rose-50 p-4 text-rose-800" role="alert">{error} <button className="font-bold underline" onClick={() => void load()} type="button">Reintentar</button></div>}
    {loading ? <p aria-busy="true" className="mt-6 rounded-2xl bg-white p-6">Cargando Inicio…</p> : daily && <>
      <section aria-label="Indicadores de hoy" className="mt-5 grid gap-3 sm:grid-cols-2 xl:grid-cols-4">
        {[["Ventas netas", money.format(daily.totalSold)], ["Pedidos pagados", String(daily.completedOrders)], ["Ticket promedio", money.format(average)], ["Descuentos autorizados", money.format(daily.discounts)]].map(([label, value]) => <article className="rounded-2xl border border-stone-200 bg-white p-4 shadow-sm" key={label}><p className="text-xs font-bold uppercase tracking-wide text-stone-500">{label}</p><p className="mt-2 text-2xl font-bold">{value}</p></article>)}
      </section>

      <section className="mt-5 rounded-2xl border border-stone-200 bg-white p-4 shadow-sm sm:p-5"><div className="flex items-center justify-between gap-3"><h2 className="text-xl font-bold">Requiere tu atención</h2><span className="rounded-full bg-stone-100 px-3 py-1 text-sm font-bold">{attentionCount}</span></div>
        {attentionCount === 0 ? <p className="mt-4 rounded-xl bg-emerald-50 p-4 font-semibold text-emerald-900">✓ Todo en orden</p> : <div className="mt-4 divide-y divide-stone-200">
          {alerts.map((item) => <article className="flex flex-col gap-3 py-4 sm:flex-row sm:items-center sm:justify-between" key={item.id}><div><p className="font-bold text-amber-900">⚠ Cierre con diferencia · {item.cashboxCode}</p><p className="text-sm text-stone-600">{item.actorName} · {time.format(new Date(item.createdAt))} · Diferencia {money.format(item.difference ?? 0)}</p></div><button className="min-h-11 rounded-xl border border-stone-300 px-4 text-sm font-semibold" onClick={onCash} type="button">Ver cierre</button></article>)}
          {discounts.map((item) => <article className="flex flex-col gap-3 py-4 sm:flex-row sm:items-center sm:justify-between" key={item.id}><div><p className="font-bold text-sky-900">● Descuento pendiente · Pedido #{item.pedido_id}</p><p className="text-sm text-stone-600">{item.tipo} · {item.valor_solicitado} · {item.motivo}</p></div><button className="min-h-11 rounded-xl bg-emerald-800 px-4 text-sm font-bold text-white" onClick={onPending} type="button">Revisar</button></article>)}
        </div>}
      </section>

      <section className="mt-5 rounded-2xl border border-stone-200 bg-white p-4 shadow-sm sm:p-5"><div className="flex flex-wrap items-center justify-between gap-3"><h2 className="text-xl font-bold">Operación de caja</h2><button className="min-h-11 rounded-xl border border-stone-300 px-4 text-sm font-semibold" onClick={onCash} type="button">Ver caja</button></div>
        {activeSession ? <><div className="mt-4 flex flex-wrap items-center gap-3"><b>{activeSession.cashbox}</b><span className="rounded-full bg-emerald-100 px-3 py-1 text-xs font-bold text-emerald-900">ABIERTA</span><span className="text-sm text-stone-600">Abierta por {activeSession.openedBy} · {time.format(new Date(activeSession.openedAt))}</span></div><div className="mt-4 grid grid-cols-2 gap-4 sm:grid-cols-4"><p className="text-sm text-stone-600">Inicial<br/><b className="text-stone-950">{money.format(activeSession.initialAmount)}</b></p><p className="text-sm text-stone-600">Efectivo esperado<br/><b className="text-stone-950">{money.format(activeSession.expectedCash)}</b></p><p className="text-sm text-stone-600">Entradas<br/><b className="text-stone-950">{money.format(activeSession.entries)}</b></p><p className="text-sm text-stone-600">Salidas<br/><b className="text-stone-950">{money.format(activeSession.exits)}</b></p></div></> : <p className="mt-4 rounded-xl bg-stone-50 p-4 text-stone-600">No existe una sesión activa.</p>}
      </section>

      <section className="mt-5 rounded-2xl border border-stone-200 bg-white p-4 shadow-sm sm:p-5"><h2 className="text-xl font-bold">Ventas por medio</h2><div className="mt-4 space-y-4">{methods.map((method) => { const amount = daily.salesByMethod[method] ?? 0; const width = maxMethod > 0 ? amount / maxMethod * 100 : 0; return <div className="grid min-w-0 grid-cols-[5.5rem_minmax(0,1fr)] items-center gap-3 sm:grid-cols-[6rem_8rem_minmax(0,1fr)]" key={method}><b className="text-sm">{method}</b><span className="text-sm font-semibold sm:block">{money.format(amount)}</span><div aria-label={`${method}: ${money.format(amount)}`} className="col-span-2 h-3 overflow-hidden rounded-full bg-stone-100 sm:col-span-1"><div className="h-full rounded-full bg-emerald-700 transition-[width]" style={{ width: `${width}%` }} /></div></div>; })}</div></section>
    </>}
  </main>;
}
