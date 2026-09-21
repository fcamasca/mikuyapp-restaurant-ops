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
    [reason, setReason] = useState("");
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
      <h2 className="text-xl font-bold">Solicitudes de descuento</h2>
      <p className="text-sm text-stone-600">
        Autoriza o rechaza solicitudes del local. Esta vista no permite cobrar.
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
          {discounts.length === 0 ? (
            <p>Sin solicitudes.</p>
          ) : (
            discounts.map((d) => (
              <div className="mt-2 rounded-xl border p-3" key={d.id}>
                <p>
                  Pedido #{d.pedido_id} · {d.tipo} {d.valor_solicitado} ·{" "}
                  {d.estado}
                </p>
                <p>{d.motivo}</p>
                {d.estado === "PENDIENTE" && (
                  <div className="mt-2 flex gap-2">
                    <button
                      disabled={busy}
                      onClick={() =>
                        service &&
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
                    <button
                      disabled={busy || !reason.trim()}
                      onClick={() =>
                        service &&
                        void run(() =>
                          service.decideDiscount(
                            context,
                            d.pedido_id,
                            "RECHAZAR",
                            reason,
                            crypto.randomUUID(),
                          ),
                        )
                      }
                    >
                      Rechazar
                    </button>
                  </div>
                )}
              </div>
            ))
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
