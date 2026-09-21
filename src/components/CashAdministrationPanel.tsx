import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import {
  createAdminCashService,
  type AdminDiscount,
  type AdminOrder,
} from "../services/cashierService";
import type { ValidatedProfileContext } from "../services/profileContext";
import { getSupabaseClient } from "../services/supabaseClient";
const warning = new Set(["EN_PREPARACION", "LISTO", "ENTREGADO"]),
  money = new Intl.NumberFormat("es-PE", {
    style: "currency",
    currency: "PEN",
  });
const formatDiscount = (discount: AdminDiscount) =>
  discount.tipo === "IMPORTE"
    ? money.format(discount.valor_solicitado)
    : `${discount.valor_solicitado}%`;
type DiscountDecision = {
  discount: AdminDiscount;
  decision: "AUTORIZAR" | "RECHAZAR";
};
export default function CashAdministrationPanel({
  context,
  discountsOnly = false,
}: {
  context: ValidatedProfileContext;
  discountsOnly?: boolean;
}) {
  const cr = useMemo(() => getSupabaseClient(), []),
    service = useMemo(
      () => (cr.ok ? createAdminCashService(cr.client) : null),
      [cr],
    );
  const [orders, setOrders] = useState<readonly AdminOrder[]>([]),
    [discounts, setDiscounts] = useState<readonly AdminDiscount[]>([]),
    [loading, setLoading] = useState(true),
    [busy, setBusy] = useState(false),
    [error, setError] = useState<string | null>(null),
    [reason, setReason] = useState(""),
    [rejectionReasons, setRejectionReasons] = useState<Record<string, string>>({}),
    [confirmation, setConfirmation] = useState<DiscountDecision | null>(null),
    [feedback, setFeedback] = useState<string | null>(null);
  const lock = useRef(false);
  const load = useCallback(async () => {
    if (!service) return;
    setLoading(true);
    const [o, d] = await Promise.all([
      discountsOnly ? Promise.resolve({ ok: true as const, data: [] as readonly AdminOrder[] }) : service.getOrders(context),
      service.getDiscounts(context),
    ]);
    if (o.ok) setOrders(o.data);
    else setError(o.error.message);
    if (d.ok) setDiscounts(d.data);
    else setError(d.error.message);
    setLoading(false);
  }, [context, discountsOnly, service]);
  useEffect(() => {
    void load();
  }, [load]);
  const visibleDiscounts = discountsOnly
    ? discounts.filter((discount) => discount.estado === "PENDIENTE")
    : discounts;
  const run = async (
    f: () => Promise<{ ok: boolean; error?: { message: string } }>,
  ) => {
    if (lock.current) return;
    lock.current = true;
    setBusy(true);
    setError(null);
    const r = await f();
    if (!r.ok) setError(r.error?.message ?? "Error servidor");
    await load();
    setBusy(false);
    lock.current = false;
    return r.ok;
  };
  return (
    <section className="mt-6 rounded-3xl border border-stone-200 bg-white p-4 shadow-sm sm:p-6">
      <div className="flex flex-wrap items-center justify-between gap-3">
        <h2 className="text-xl font-bold">Solicitudes de descuento ({visibleDiscounts.length})</h2>
        {visibleDiscounts.length > 0 && <span className="rounded-full bg-amber-100 px-3 py-1 text-xs font-bold text-amber-900">Pendientes</span>}
      </div>
      <p className="mt-1 text-sm text-stone-600">
        Revisa y decide las solicitudes de descuento del local. Esta vista no permite cobrar.
      </p>
      {error && (
        <p role="alert" className="mt-3 text-rose-800">
          {error} <button onClick={() => void load()}>Reintentar</button>
        </p>
      )}
      {feedback && <p className="mt-3 rounded-xl bg-emerald-50 p-3 font-semibold text-emerald-900" role="status">{feedback}</p>}
      {loading ? (
        <p aria-busy="true">Cargando operación…</p>
      ) : (
        <>
          {visibleDiscounts.length === 0 ? (
            <p className="mt-4 rounded-2xl bg-emerald-50 p-4 font-semibold text-emerald-900">✓ No hay descuentos pendientes de aprobación.</p>
          ) : (
            <div className="mt-4 divide-y divide-stone-200 border-y border-stone-200">
            {visibleDiscounts.map((d) => (
              <article className="py-5" key={d.id}>
                <div className="flex flex-wrap items-start justify-between gap-3">
                  <div>
                    <h3 className="text-lg font-bold">Pedido #{d.pedido_id}</h3>
                    <p className="mt-1 text-sm text-stone-600">Descuento solicitado</p>
                  </div>
                  <span className="rounded-full bg-amber-100 px-3 py-1 text-xs font-bold text-amber-900">{d.estado}</span>
                </div>
                <dl className="mt-4 grid gap-3 rounded-2xl bg-stone-50 p-4 sm:grid-cols-[10rem_minmax(0,1fr)]">
                  <dt className="text-sm text-stone-600">Valor solicitado</dt><dd className="font-bold">{formatDiscount(d)}</dd>
                  <dt className="text-sm text-stone-600">Motivo</dt><dd className="break-words">{d.motivo}</dd>
                </dl>
                {d.estado === "PENDIENTE" && (
                  <div className="mt-4 flex flex-col gap-3 lg:flex-row lg:items-end lg:justify-between">
                    <label className="min-w-0 flex-1 text-sm font-semibold text-stone-700">Motivo del rechazo
                      <input className="mt-1 min-h-11 w-full rounded-xl border border-stone-300 bg-white px-3 font-normal outline-none focus:border-emerald-700 focus:ring-4 focus:ring-emerald-100" onChange={(event) => setRejectionReasons((current) => ({ ...current, [d.id]: event.target.value }))} placeholder="Obligatorio sólo para rechazar" value={rejectionReasons[d.id] ?? ""} />
                    </label>
                    <div className="flex flex-wrap justify-end gap-2">
                    <button
                      className="min-h-11 rounded-xl border border-rose-300 bg-white px-5 text-sm font-bold text-rose-800 hover:bg-rose-50 disabled:cursor-not-allowed disabled:opacity-50"
                      disabled={busy || !(rejectionReasons[d.id] ?? "").trim()}
                      onClick={() => { setFeedback(null); setConfirmation({ discount: d, decision: "RECHAZAR" }); }}
                    >
                      Rechazar
                    </button>
                    <button
                      className="min-h-11 rounded-xl bg-emerald-800 px-5 text-sm font-bold text-white shadow-sm hover:bg-emerald-900 disabled:cursor-not-allowed disabled:opacity-50"
                      disabled={busy}
                      onClick={() => { setFeedback(null); setConfirmation({ discount: d, decision: "AUTORIZAR" }); }}
                    >
                      Autorizar
                    </button>
                    </div>
                  </div>
                )}
              </article>
            ))}
            </div>
          )}
          {!discountsOnly && <><h3 className="mt-5 font-bold">Pedidos del local</h3>
          <input
            aria-label="Motivo administrativo"
            placeholder="Motivo obligatorio"
            value={reason}
            onChange={(e) => setReason(e.target.value)}
          />
          <div className="mt-3 grid gap-2 lg:grid-cols-2">
            {orders.map((o) => {
              const eligible =
                !o.hasPayments &&
                !["PAGADO", "ANULADO"].includes(o.orderStatus);
              return (
                <article className="rounded-xl border p-3" key={o.orderId}>
                  <b>
                    Pedido #{o.orderId} · Mesa {o.tableCode}
                  </b>
                  <p>
                    {o.orderStatus} · neto {money.format(o.netTotal)} · pagado{" "}
                    {money.format(o.paid)}
                  </p>
                  {warning.has(o.orderStatus) && (
                    <p className="text-amber-800">
                      Advertencia: el pedido ya avanzó operativamente.
                    </p>
                  )}
                  <button
                    disabled={busy || !eligible || !reason.trim()}
                    onClick={() =>
                      service &&
                      window.confirm(`¿Anular pedido #${o.orderId}?`) &&
                      void run(() =>
                        service.annul(
                          context,
                          o.orderId,
                          reason,
                          crypto.randomUUID(),
                        ),
                      )
                    }
                  >
                    Anular pedido
                  </button>
                  {!eligible && <span> · No elegible</span>}
                </article>
              );
            })}
          </div></>}
        </>
      )}
      {confirmation && (
        <div className="fixed inset-0 z-40 flex items-center justify-center bg-black/50 p-4" role="presentation">
          <section aria-labelledby="discount-confirmation-title" aria-modal="true" className="w-full max-w-lg rounded-2xl bg-white p-5 shadow-2xl" role="dialog">
            <p className="text-xs font-bold uppercase tracking-wider text-emerald-700">Confirmación requerida</p>
            <h2 className="mt-1 text-2xl font-bold" id="discount-confirmation-title">{confirmation.decision === "AUTORIZAR" ? "Autorizar descuento" : "Rechazar descuento"}</h2>
            <dl className="mt-4 grid gap-3 rounded-xl bg-stone-50 p-4 text-sm sm:grid-cols-[9rem_minmax(0,1fr)]">
              <dt className="text-stone-600">Pedido</dt><dd className="font-bold">#{confirmation.discount.pedido_id}</dd>
              <dt className="text-stone-600">Valor solicitado</dt><dd className="font-bold">{formatDiscount(confirmation.discount)}</dd>
              <dt className="text-stone-600">Motivo</dt><dd className="break-words">{confirmation.discount.motivo}</dd>
              {confirmation.decision === "RECHAZAR" && <><dt className="text-stone-600">Motivo del rechazo</dt><dd className="break-words font-semibold">{rejectionReasons[confirmation.discount.id]}</dd></>}
            </dl>
            <p className={`mt-4 rounded-xl border p-3 font-semibold ${confirmation.decision === "AUTORIZAR" ? "border-amber-200 bg-amber-50 text-amber-950" : "border-rose-200 bg-rose-50 text-rose-950"}`}>Esta decisión es definitiva y no puede revertirse.</p>
            {error && <p className="mt-3 rounded-xl bg-rose-50 p-3 text-sm font-semibold text-rose-800" role="alert">{error}</p>}
            <div className="mt-5 flex flex-col-reverse gap-2 sm:flex-row sm:justify-end">
              <button className="min-h-11 rounded-xl border border-stone-300 bg-white px-5 text-sm font-semibold" disabled={busy} onClick={() => { setConfirmation(null); setError(null); }} type="button">Volver</button>
              <button aria-busy={busy} className={`min-h-11 rounded-xl px-5 text-sm font-bold text-white disabled:cursor-not-allowed disabled:opacity-50 ${confirmation.decision === "AUTORIZAR" ? "bg-emerald-800 hover:bg-emerald-900" : "bg-rose-700 hover:bg-rose-800"}`} disabled={busy} onClick={() => {
                if (!service) return;
                const current = confirmation;
                void (async () => {
                  const succeeded = await run(() => service.decideDiscount(context, current.discount.pedido_id, current.decision, current.decision === "RECHAZAR" ? rejectionReasons[current.discount.id] : null, crypto.randomUUID()));
                  if (succeeded) {
                    setConfirmation(null);
                    setFeedback(current.decision === "AUTORIZAR" ? "Descuento autorizado correctamente." : "Solicitud de descuento rechazada.");
                  }
                })();
              }} type="button">{busy ? "Procesando…" : confirmation.decision === "AUTORIZAR" ? "Autorizar descuento" : "Rechazar descuento"}</button>
            </div>
          </section>
        </div>
      )}
    </section>
  );
}
