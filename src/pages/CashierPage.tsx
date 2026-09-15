import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import AuthenticatedUserMenu from "../components/AuthenticatedUserMenu";
import {
  createCashierService,
  type AdminDiscount,
  type Cashbox,
  type CashSession,
  type SessionSummary,
  type CashierPendingOrder,
  type PaymentHistory,
  type PersistedPayment,
} from "../services/cashierService";
import type { ValidatedProfileContext } from "../services/profileContext";
import { getSupabaseClient } from "../services/supabaseClient";
import type { PaymentMethodCode } from "../types/operations";
interface Props {
  context: ValidatedProfileContext;
  isSigningOut: boolean;
  onNavigateToSales: () => void;
  onSignOut: () => void;
}
const money = new Intl.NumberFormat("es-PE", {
    style: "currency",
    currency: "PEN",
  }),
  methods: PaymentMethodCode[] = ["EFECTIVO", "YAPE", "PLIN", "TARJETA"];
const n = (v: string) => Number(v),
  key = () => crypto.randomUUID();
function Lines({
  order,
  select,
  onSelect,
}: {
  order: CashierPendingOrder;
  select: Set<number>;
  onSelect: (id: number) => void;
}) {
  return (
    <ul className="mt-3 divide-y">
      {order.lines.map((x) => (
        <li className="flex gap-3 py-2" key={x.detailId}>
          <input
            aria-label={`Seleccionar ${x.productName}`}
            checked={select.has(x.detailId)}
            onChange={() => onSelect(x.detailId)}
            type="checkbox"
          />
          <span className="grow">
            {x.quantity} × {x.productName}
          </span>
          <b>{money.format(x.lineAmount)}</b>
        </li>
      ))}
    </ul>
  );
}
function InternalDocument({
  payment,
  order,
  payments,
  onClose,
}: {
  payment: PersistedPayment;
  order: CashierPendingOrder;
  payments: readonly PaymentHistory[];
  onClose: () => void;
}) {
  const complete = payment.balance === 0;
  return (
    <div className="print-overlay fixed inset-0 z-50 overflow-auto bg-black/50 p-5">
      <article className="print-document mx-auto max-w-xl rounded-2xl bg-white p-6">
        <h2 className="text-2xl font-bold">
          {complete
            ? "Ticket consolidado interno"
            : "Recibo interno de pago parcial"}
        </h2>
        <p>Documento interno · No es comprobante fiscal</p>
        <hr className="my-4" />
        <p>
          Pedido #{order.orderId} · Mesa {order.tableCode}
        </p>
        <p>Subtotal: {money.format(payment.subtotal)}</p>
        <p>Descuento: {money.format(payment.discount)}</p>
        <p>Total neto: {money.format(payment.netTotal)}</p>
        <ul className="my-3">
          {[
            ...payments,
            {
              paymentId: payment.paymentId,
              amount: payment.amount,
              method: payment.method,
              tip: payment.tip,
              actorName: "Usuario actual",
              paidAt: payment.paidAt,
              subtotal: payment.subtotal,
              discount: payment.discount,
              netTotal: payment.netTotal,
              paid: payment.paid,
              balance: payment.balance,
            },
          ]
            .filter(
              (x, i, a) =>
                a.findIndex((y) => y.paymentId === x.paymentId) === i,
            )
            .map((x) => (
              <li key={x.paymentId}>
                Pago #{x.paymentId}: {money.format(x.amount)} · {x.method} ·
                propina {money.format(x.tip)}
              </li>
            ))}
        </ul>
        <b>Saldo: {money.format(payment.balance)}</b>
        <div className="no-print mt-5 flex gap-2">
          <button onClick={() => window.print()} type="button">
            Imprimir
          </button>
          <button onClick={onClose} type="button">
            Cerrar
          </button>
        </div>
      </article>
    </div>
  );
}
export default function CashierPage({
  context,
  isSigningOut,
  onNavigateToSales,
  onSignOut,
}: Props) {
  const cr = useMemo(() => getSupabaseClient(), []),
    service = useMemo(
      () => (cr.ok ? createCashierService(cr.client) : null),
      [cr],
    );
  const [cashboxes, setCashboxes] = useState<readonly Cashbox[]>([]),
    [cashboxId, setCashboxId] = useState(""),
    [session, setSession] = useState<CashSession | null>(null),
    [summary, setSummary] = useState<SessionSummary | null>(null),
    [history, setHistory] = useState<readonly Record<string, unknown>[]>([]),
    [orders, setOrders] = useState<readonly CashierPendingOrder[]>([]),
    [selectedId, setSelectedId] = useState<number | null>(null),
    [payments, setPayments] = useState<readonly PaymentHistory[]>([]),
    [discount, setDiscount] = useState<AdminDiscount | null>(null),
    [loading, setLoading] = useState(true),
    [busy, setBusy] = useState(false),
    [error, setError] = useState<string | null>(null),
    [attempt, setAttempt] = useState(0);
  const [initial, setInitial] = useState("0"),
    [movement, setMovement] = useState<"ENTRADA" | "SALIDA">("ENTRADA"),
    [movementAmount, setMovementAmount] = useState(""),
    [reason, setReason] = useState(""),
    [counted, setCounted] = useState(""),
    [paymentAmount, setPaymentAmount] = useState(""),
    [tip, setTip] = useState("0"),
    [method, setMethod] = useState<PaymentMethodCode>("EFECTIVO"),
    [discountType, setDiscountType] = useState<"IMPORTE" | "PORCENTAJE">(
      "IMPORTE",
    ),
    [discountValue, setDiscountValue] = useState(""),
    [selectedLines, setSelectedLines] = useState(new Set<number>()),
    [document, setDocument] = useState<PersistedPayment | null>(null),
    [documentOrder, setDocumentOrder] = useState<CashierPendingOrder | null>(
      null,
    );
  const pending = useRef(false);
  const selected = orders.find((x) => x.orderId === selectedId) ?? null;
  const refresh = useCallback(async () => {
    if (!service) return;
    setLoading(true);
    const boxes = await service.getCashboxes(context);
    if (!boxes.ok) {
      setError(boxes.error.message);
      setLoading(false);
      return;
    }
    setCashboxes(boxes.data);
    const chosen = cashboxId || boxes.data[0]?.id || "";
    if (!cashboxId) setCashboxId(chosen);
    const [s, o] = chosen
      ? await Promise.all([
          service.getActiveSession(context, chosen),
          service.getPendingOrders(context),
        ])
      : [null, await service.getPendingOrders(context)];
    if (s && !s.ok) setError(s.error.message);
    else if (s) {
      setSession(s.data);
      if (s.data) {
        const sr = await service.getSummary(context, s.data.id);
        setSummary(sr.ok ? sr.data : null);
      } else setSummary(null);
    }
    if (o.ok) {
      setOrders(o.data);
      setSelectedId((x) =>
        o.data.some((y) => y.orderId === x) ? x : (o.data[0]?.orderId ?? null),
      );
    } else setError(o.error.message);
    setLoading(false);
  }, [cashboxId, context, service]);
  useEffect(() => {
    void refresh();
  }, [attempt, refresh]);
  useEffect(() => {
    if (!service || !cashboxId) {
      setHistory([]);
      return;
    }
    void service.getSessionHistory(context, cashboxId).then((result) => {
      if (result.ok) setHistory(result.data);
    });
  }, [cashboxId, context, service]);
  useEffect(() => {
    if (!service || !selected) {
      setPayments([]);
      setDiscount(null);
      return;
    }
    void Promise.all([
      service.getPayments(context, selected.orderId),
      service.getOrderDiscount(context, selected.orderId),
    ]).then(([p, d]) => {
      if (p.ok) setPayments(p.data);
      if (d.ok) setDiscount(d.data);
    });
  }, [context, selected, service]);
  const run = async (
    action: () => Promise<{ ok: boolean; error?: { message: string } }>,
  ) => {
    if (pending.current) return;
    pending.current = true;
    setBusy(true);
    setError(null);
    try {
      const r = await action();
      if (!r.ok) setError(r.error?.message ?? "Error servidor");
      await refresh();
    } finally {
      pending.current = false;
      setBusy(false);
    }
  };
  const suggested = [...selectedLines].reduce(
    (sum, id) =>
      sum + (selected?.lines.find((x) => x.detailId === id)?.lineAmount ?? 0),
    0,
  );
  return (
    <main className="min-h-screen bg-stone-100 p-3 text-stone-900 sm:p-6">
      <div className="mx-auto max-w-7xl">
        <header className="flex flex-wrap justify-between gap-3">
          <div>
            <p className="font-semibold text-emerald-700">MikuyApp · Caja</p>
            <h1 className="text-3xl font-bold">Sesión y cobros</h1>
            <p>{context.local.nombre}</p>
          </div>
          <div className="flex gap-2">
            <button onClick={onNavigateToSales}>Resumen diario</button>
            <AuthenticatedUserMenu
              context={context}
              isSigningOut={isSigningOut}
              onSignOut={onSignOut}
            />
          </div>
        </header>
        {error && (
          <div className="mt-4 rounded-xl bg-rose-50 p-4">
            <p role="alert">{error}</p>
            <button disabled={loading} onClick={() => setAttempt((x) => x + 1)}>
              Reintentar
            </button>
          </div>
        )}
        <section className="mt-5 rounded-2xl bg-white p-4">
          <h2 className="font-bold">Estado de caja</h2>
          {loading ? (
            <p aria-busy="true">Cargando caja…</p>
          ) : cashboxes.length === 0 ? (
            <p>No hay caja física disponible.</p>
          ) : (
            <>
              <label>
                Caja física
                <select
                  disabled={busy}
                  value={cashboxId}
                  onChange={(e) => {
                    setCashboxId(e.target.value);
                    setSession(null);
                  }}
                >
                  {cashboxes.map((x) => (
                    <option key={x.id} value={x.id}>
                      {x.codigo} · {x.nombre}
                    </option>
                  ))}
                </select>
              </label>
              {session ? (
                <div className="mt-3 grid gap-2 sm:grid-cols-4">
                  <p>
                    Sesión: <b>{session.estado}</b>
                  </p>
                  <p>
                    Abierta por: <b>{session.abierta_por}</b>
                  </p>
                  <p>
                    Monto inicial: <b>{money.format(session.monto_inicial)}</b>
                  </p>
                  <p>
                    Efectivo esperado:{" "}
                    <b>{money.format(summary?.efectivo_esperado ?? 0)}</b>
                  </p>
                </div>
              ) : (
                <div className="mt-3">
                  <label>
                    Monto inicial
                    <input
                      min="0"
                      step="0.01"
                      value={initial}
                      onChange={(e) => setInitial(e.target.value)}
                      type="number"
                    />
                  </label>
                  <button
                    disabled={busy}
                    onClick={() =>
                      service &&
                      void run(() =>
                        service.openSession(
                          context,
                          cashboxId,
                          n(initial),
                          key(),
                        ),
                      )
                    }
                  >
                    Abrir o recuperar sesión
                  </button>
                </div>
              )}
            </>
          )}
        </section>
        {session && (
          <details className="mt-4 rounded-2xl bg-white p-4">
            <summary className="font-bold">
              Movimientos, historial y cierre
            </summary>
            <p className="mt-2 text-sm">
              Historial reciente: {history.length} sesiones.
            </p>
            <div className="mt-3 grid gap-3 md:grid-cols-2">
              <form
                onSubmit={(e) => {
                  e.preventDefault();
                  if (service)
                    void run(() =>
                      service.registerMovement(
                        context,
                        session.id,
                        movement,
                        n(movementAmount),
                        reason,
                        key(),
                      ),
                    );
                }}
              >
                <h3>Movimiento</h3>
                <select
                  value={movement}
                  onChange={(e) =>
                    setMovement(e.target.value as typeof movement)
                  }
                >
                  <option>ENTRADA</option>
                  <option>SALIDA</option>
                </select>
                <input
                  aria-label="Importe movimiento"
                  value={movementAmount}
                  onChange={(e) => setMovementAmount(e.target.value)}
                  type="number"
                />
                <input
                  aria-label="Motivo movimiento"
                  value={reason}
                  onChange={(e) => setReason(e.target.value)}
                />
                <button disabled={busy}>Confirmar movimiento</button>
              </form>
              <form
                onSubmit={(e) => {
                  e.preventDefault();
                  if (service)
                    void run(() =>
                      service.closeSession(
                        context,
                        session.id,
                        n(counted),
                        reason || null,
                        key(),
                      ),
                    );
                }}
              >
                <h3>Cierre de caja</h3>
                <p>
                  Efectivo esperado{" "}
                  {money.format(summary?.efectivo_esperado ?? 0)}
                </p>
                <input
                  aria-label="Efectivo contado"
                  value={counted}
                  onChange={(e) => setCounted(e.target.value)}
                  type="number"
                />
                <p>PostgreSQL calculará y confirmará la diferencia.</p>
                <input
                  aria-label="Motivo de diferencia"
                  value={reason}
                  onChange={(e) => setReason(e.target.value)}
                />
                <button disabled={busy}>Confirmar cierre</button>
              </form>
            </div>
          </details>
        )}
        <div className="mt-5 grid gap-5 lg:grid-cols-[22rem_1fr]">
          <section className="rounded-2xl bg-white p-4">
            <h2 className="font-bold">Pedidos pendientes</h2>
            {loading ? (
              <p>Cargando pedidos pendientes…</p>
            ) : orders.length === 0 ? (
              <p>No hay pedidos pendientes de pago.</p>
            ) : (
              orders.map((x) => (
                <button
                  className="mt-2 block w-full rounded-xl border p-3 text-left"
                  key={x.orderId}
                  onClick={() => {
                    setSelectedId(x.orderId);
                    setSelectedLines(new Set());
                    setPaymentAmount(String(x.balance));
                  }}
                >
                  Mesa {x.tableCode} · Pedido #{x.orderId}
                  <br />
                  Saldo {money.format(x.balance)}
                </button>
              ))
            )}
          </section>
          <section className="rounded-2xl bg-white p-4">
            {selected ? (
              <>
                <h2 className="text-2xl font-bold">
                  Pedido #{selected.orderId}
                </h2>
                <div className="mt-3 grid grid-cols-2 gap-2 sm:grid-cols-5">
                  <p>
                    Subtotal
                    <br />
                    <b>{money.format(selected.subtotal)}</b>
                  </p>
                  <p>
                    Descuento
                    <br />
                    <b>{money.format(selected.discount)}</b>
                  </p>
                  <p>
                    Total neto
                    <br />
                    <b>{money.format(selected.netTotal)}</b>
                  </p>
                  <p>
                    Pagado
                    <br />
                    <b>{money.format(selected.paid)}</b>
                  </p>
                  <p>
                    Saldo
                    <br />
                    <b>{money.format(selected.balance)}</b>
                  </p>
                </div>
                <Lines
                  order={selected}
                  select={selectedLines}
                  onSelect={(id) =>
                    setSelectedLines((old) => {
                      const x = new Set(old);
                      x.has(id) ? x.delete(id) : x.add(id);
                      return x;
                    })
                  }
                />
                <p>Importe sugerido por selección: {money.format(suggested)}</p>
                <button
                  type="button"
                  onClick={() => setPaymentAmount(String(suggested))}
                >
                  Usar importe sugerido
                </button>
                <form
                  className="mt-4 grid gap-2 sm:grid-cols-2"
                  onSubmit={(e) => {
                    e.preventDefault();
                    if (service && session)
                      void run(async () => {
                        const r = await service.registerPayment(
                          context,
                          selected.orderId,
                          session.id,
                          n(paymentAmount),
                          method,
                          n(tip),
                          key(),
                        );
                        if (r.ok) {
                          setDocumentOrder(selected);
                          setDocument(r.data);
                        }
                        return r;
                      });
                  }}
                >
                  <label>
                    Importe a aplicar
                    <input
                      value={paymentAmount}
                      onChange={(e) => setPaymentAmount(e.target.value)}
                      type="number"
                    />
                  </label>
                  <label>
                    Propina separada
                    <input
                      value={tip}
                      onChange={(e) => setTip(e.target.value)}
                      type="number"
                    />
                  </label>
                  <select
                    value={method}
                    onChange={(e) =>
                      setMethod(e.target.value as PaymentMethodCode)
                    }
                  >
                    {methods.map((x) => (
                      <option key={x}>{x}</option>
                    ))}
                  </select>
                  <button aria-busy={busy} disabled={busy || !session}>
                    Registrar pago
                  </button>
                </form>
                {discount && (
                  <p className="mt-3 text-sm">
                    Descuento: <b>{discount.estado}</b> · {discount.tipo}{' '}
                    {discount.valor_solicitado}
                  </p>
                )}
                <form
                  className="mt-4 flex flex-wrap gap-2"
                  onSubmit={(e) => {
                    e.preventDefault();
                    if (service)
                      void run(() =>
                        service.requestDiscount(
                          context,
                          selected.orderId,
                          discountType,
                          n(discountValue),
                          reason,
                          key(),
                        ),
                      );
                  }}
                >
                  <select
                    value={discountType}
                    onChange={(e) =>
                      setDiscountType(e.target.value as typeof discountType)
                    }
                  >
                    <option>IMPORTE</option>
                    <option>PORCENTAJE</option>
                  </select>
                  <input
                    aria-label="Valor descuento"
                    value={discountValue}
                    onChange={(e) => setDiscountValue(e.target.value)}
                  />
                  <input
                    aria-label="Motivo descuento"
                    value={reason}
                    onChange={(e) => setReason(e.target.value)}
                  />
                  <button disabled={busy || selected.paid > 0}>
                    Solicitar descuento
                  </button>
                </form>
                <h3 className="mt-5 font-bold">Pagos confirmados</h3>
                {payments.length === 0 ? (
                  <p>Sin pagos confirmados.</p>
                ) : (
                  <ul>
                    {payments.map((x) => (
                      <li key={x.paymentId}>
                        #{x.paymentId} · {money.format(x.amount)} · {x.method} ·
                        propina {money.format(x.tip)} · {x.actorName} · saldo{" "}
                        {money.format(x.balance)}
                      </li>
                    ))}
                  </ul>
                )}
              </>
            ) : (
              <p>Selecciona un pedido.</p>
            )}
          </section>
        </div>
      </div>
      {document && documentOrder && (
        <InternalDocument
          order={documentOrder}
          payment={document}
          payments={payments}
          onClose={() => {
            setDocument(null);
            setDocumentOrder(null);
          }}
        />
      )}
    </main>
  );
}
