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
    [rejectionReasons, setRejectionReasons] = useState<Record<string, string>>({});
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
    const r = await f();
    if (!r.ok) setError(r.error?.message ?? "Error servidor");
    await load();
    setBusy(false);
    lock.current = false;
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
                      onClick={() =>
                        service &&
                        window.confirm(`¿Rechazar el descuento del pedido #${d.pedido_id}?`) &&
                        void run(() =>
                          service.decideDiscount(
                            context,
                            d.pedido_id,
                            "RECHAZAR",
                            rejectionReasons[d.id],
                            crypto.randomUUID(),
                          ),
                        )
                      }
                    >
                      Rechazar
                    </button>
                    <button
                      className="min-h-11 rounded-xl bg-emerald-800 px-5 text-sm font-bold text-white shadow-sm hover:bg-emerald-900 disabled:cursor-not-allowed disabled:opacity-50"
                      disabled={busy}
                      onClick={() =>
                        service &&
                        window.confirm(`¿Autorizar el descuento del pedido #${d.pedido_id}?`) &&
                        void run(() =>
                          service.decideDiscount(
                            context,
                            d.pedido_id,
                            "AUTORIZAR",
                            null,
                            crypto.randomUUID(),
                          ),
                        )
                      }
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
    </section>
  );
}
