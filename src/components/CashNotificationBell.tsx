import { useEffect, useMemo, useState } from "react";
import type { ValidatedProfileContext } from "../services/profileContext";
import { createCashNotificationService, type CashNotification } from "../services/cashNotificationService";
import { getSupabaseClient } from "../services/supabaseClient";

const money = new Intl.NumberFormat("es-PE", { style: "currency", currency: "PEN" });
const dateTime = new Intl.DateTimeFormat("es-PE", { dateStyle: "short", timeStyle: "short" });

export default function CashNotificationBell({ context }: { readonly context: ValidatedProfileContext }) {
  const clientResult = useMemo(() => getSupabaseClient(), []);
  const service = useMemo(
    () => clientResult.ok ? createCashNotificationService(clientResult.client) : null,
    [clientResult],
  );
  const [notifications, setNotifications] = useState<readonly CashNotification[]>([]);
  const [unreadCount, setUnreadCount] = useState(0);
  const [open, setOpen] = useState(false);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  async function load(): Promise<void> {
    if (!service) {
      setLoading(false);
      setError("No pudimos establecer la conexión con las notificaciones.");
      return;
    }
    setLoading(true);
    const result = await service.getNotifications(context);
    setLoading(false);
    if (!result.ok) {
      setError(result.error.message);
      return;
    }
    setNotifications(result.data.notifications);
    setUnreadCount(result.data.unreadCount);
    setError(null);
  }

  useEffect(() => { void load(); }, [context, service]);

  async function markAsRead(notification: CashNotification): Promise<void> {
    if (!service || notification.readAt) return;
    const result = await service.markAsRead(context, notification.id);
    if (!result.ok) {
      setError(result.error.message);
      return;
    }
    setNotifications((current) => current.map((item) => item.id === notification.id
      ? { ...item, readAt: result.data.readAt }
      : item));
    setUnreadCount((current) => Math.max(0, current - 1));
    setError(null);
  }

  return (
    <div className="relative">
      <button
        aria-expanded={open}
        aria-label={`Notificaciones${unreadCount > 0 ? `, ${unreadCount} no leídas` : ""}`}
        className="relative flex h-11 w-11 items-center justify-center rounded-xl border border-stone-300 bg-white text-xl text-stone-800 hover:bg-stone-50 focus:outline-none focus:ring-4 focus:ring-emerald-100"
        onClick={() => setOpen((value) => !value)}
        title="Notificaciones de caja"
        type="button"
      >
        <span aria-hidden="true">🔔</span>
        {unreadCount > 0 && <span className="absolute -right-1.5 -top-1.5 min-w-5 rounded-full bg-rose-700 px-1.5 py-0.5 text-center text-xs font-bold text-white">{unreadCount > 99 ? "99+" : unreadCount}</span>}
      </button>
      {open && (
        <section aria-label="Notificaciones recientes" className="absolute right-0 z-30 mt-2 max-h-[32rem] w-[min(24rem,calc(100vw-2rem))] overflow-y-auto rounded-2xl border border-stone-200 bg-white p-3 shadow-xl">
          <div className="flex items-center justify-between gap-3 border-b border-stone-200 pb-3">
            <div><h2 className="font-bold">Notificaciones</h2><p className="text-xs text-stone-500">{unreadCount} no leídas</p></div>
            <button className="rounded-lg px-2 py-1 text-sm font-semibold text-emerald-800 hover:bg-emerald-50" disabled={loading} onClick={() => { void load(); }} type="button">Actualizar</button>
          </div>
          {error && <p className="mt-3 rounded-lg bg-rose-50 p-3 text-sm text-rose-800" role="alert">{error}</p>}
          {loading ? <p aria-busy="true" className="py-5 text-center text-sm text-stone-500">Cargando notificaciones…</p>
            : notifications.length === 0 ? <p className="py-5 text-center text-sm text-stone-500">No hay notificaciones recientes.</p>
              : <ul className="divide-y divide-stone-200">{notifications.map((notification) => {
                const alert = notification.priority === "ALERTA";
                return <li className={`py-3 ${notification.readAt ? "opacity-70" : ""}`} key={notification.id}>
                  <button className={`w-full rounded-xl border p-3 text-left ${alert ? "border-amber-300 bg-amber-50" : "border-sky-200 bg-sky-50"}`} disabled={Boolean(notification.readAt)} onClick={() => { void markAsRead(notification); }} type="button">
                    <span className="flex items-center justify-between gap-2"><b>{notification.type === "APERTURA" ? "Caja abierta" : alert ? "Cierre con diferencia" : "Caja cerrada"}</b><span className="text-xs">{notification.readAt ? "Leída" : "Marcar como leída"}</span></span>
                    <span className="mt-1 block text-sm">{notification.cashboxCode} · {notification.cashboxName}</span>
                    <span className="block text-sm">{notification.actorName} · {dateTime.format(new Date(notification.createdAt))}</span>
                    {notification.type === "APERTURA" ? <span className="mt-2 block text-sm">Monto inicial: <b>{money.format(notification.initialAmount ?? 0)}</b></span>
                      : <span className="mt-2 block text-sm">Esperado {money.format(notification.expectedCash ?? 0)} · Contado {money.format(notification.countedCash ?? 0)}<br />Diferencia: <b>{money.format(notification.difference ?? 0)}</b>{notification.reason && <><br />Motivo: {notification.reason}</>}</span>}
                  </button>
                </li>;
              })}</ul>}
        </section>
      )}
    </div>
  );
}
