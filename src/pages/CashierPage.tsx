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
  type PaymentMediumLine,
  type PersistedPayment,
} from "../services/cashierService";
import type { ValidatedProfileContext } from "../services/profileContext";
import { getSupabaseClient } from "../services/supabaseClient";
import { subscribeToOperationsChanges } from "../services/operationsRealtimeService.ts";
import type { PaymentMethodCode } from "../types/operations";
interface Props {
  context: ValidatedProfileContext;
  isSigningOut: boolean;
  onNavigateToSales: () => void;
  onSignOut: () => void;
}
interface PaymentConfirmation {
  orderId: number;
  tableCode: string;
  amount: number;
  lines: readonly PaymentMediumLine[];
  tip: number;
  currentBalance: number;
  partial: boolean;
}
const money = new Intl.NumberFormat("es-PE", {
    style: "currency",
    currency: "PEN",
  }),
  methods: PaymentMethodCode[] = ["EFECTIVO", "YAPE", "PLIN", "TARJETA"];
const n = (v: string) => Number(v),
  key = () => crypto.randomUUID();
const formatDiscountValue = (discount: AdminDiscount) =>
  discount.tipo === "PORCENTAJE"
    ? `${Number(discount.valor_solicitado).toFixed(2)}%`
    : money.format(discount.valor_solicitado);
const fieldClass =
    "mt-1.5 min-h-12 w-full rounded-xl border border-stone-300 bg-white px-3 py-2.5 text-base font-medium text-stone-950 shadow-sm outline-none transition focus:border-emerald-600 focus:ring-4 focus:ring-emerald-100 disabled:cursor-not-allowed disabled:bg-stone-100",
  selectClass = `${fieldClass} appearance-auto pr-9`,
  primaryButtonClass =
    "min-h-12 rounded-xl bg-emerald-700 px-5 py-3 font-bold text-white shadow-sm transition hover:bg-emerald-800 focus:outline-none focus:ring-4 focus:ring-emerald-200 disabled:cursor-not-allowed disabled:opacity-50",
  secondaryButtonClass =
    "min-h-12 rounded-xl border border-emerald-700 bg-white px-5 py-3 font-bold text-emerald-800 shadow-sm transition hover:bg-emerald-50 focus:outline-none focus:ring-4 focus:ring-emerald-100 disabled:cursor-not-allowed disabled:opacity-50",
  auxiliaryButtonClass =
    "min-h-11 rounded-xl border border-stone-300 bg-stone-50 px-4 py-2.5 font-semibold text-stone-800 transition hover:bg-stone-100 focus:outline-none focus:ring-4 focus:ring-stone-200 disabled:opacity-50",
  compactAuxiliaryButtonClass =
    "min-h-10 whitespace-nowrap rounded-xl border border-stone-300 bg-stone-50 px-2.5 py-2 text-xs font-semibold text-stone-800 transition hover:bg-stone-100 focus:outline-none focus:ring-4 focus:ring-stone-200 disabled:opacity-50",
  compactPrimaryButtonClass =
    "min-h-11 whitespace-nowrap rounded-xl bg-emerald-700 px-3 py-2.5 text-sm font-bold text-white shadow-sm transition hover:bg-emerald-800 focus:outline-none focus:ring-4 focus:ring-emerald-200 disabled:cursor-not-allowed disabled:opacity-50";
function Lines({
  order,
  select,
  onSelect,
  selectable = false,
}: {
  order: CashierPendingOrder;
  select: Set<number>;
  onSelect: (id: number) => void;
  selectable?: boolean;
}) {
  return (
    <ul className="mt-3 divide-y divide-stone-200 rounded-xl border border-stone-200 bg-white">
      {order.lines.map((x) => (
        <li className="flex items-center gap-3 px-3 py-3" key={x.detailId}>
          {selectable && <input aria-label={`Seleccionar ${x.productName}`} checked={select.has(x.detailId)} onChange={() => onSelect(x.detailId)} type="checkbox" />}
          <span className="grow text-base text-stone-700">
            {x.quantity} × {x.productName}
          </span>
          <b className="whitespace-nowrap text-stone-950">{money.format(x.lineAmount)}</b>
        </li>
      ))}
    </ul>
  );
}
function InternalDocument({
  payment,
  order,
  payments,
  localName,
  createdAt,
  onClose,
}: {
  payment: PersistedPayment | null;
  order: CashierPendingOrder;
  payments: readonly PaymentHistory[];
  localName: string;
  createdAt: string;
  onClose: () => void;
}) {
  const preAccount = payment === null;
  const complete = payment?.balance === 0;
  const documentPayments = payment ? [
      ...payments,
      {
        chargeId: payment.chargeId,
        chargeType: complete ? "TOTAL" as const : "PARCIAL" as const,
        amount: payment.amount,
        tip: payment.tip,
        lines: payment.lines,
        actorName: "Usuario actual",
        paidAt: payment.paidAt,
        subtotal: payment.subtotal,
        discount: payment.discount,
        netTotal: payment.netTotal,
        paid: payment.paid,
        balance: payment.balance,
      },
    ].filter(
    (item, index, all) =>
      all.findIndex((candidate) => candidate.chargeId === item.chargeId) === index,
    ) : [];
  const subtotal = payment?.subtotal ?? order.subtotal;
  const discount = payment?.discount ?? order.discount;
  const netTotal = payment?.netTotal ?? order.netTotal;
  const balance = payment?.balance ?? order.balance;
  const paidPreviously = payment ? Math.max(0, payment.paid - payment.amount) : order.paid;
  const title = preAccount ? "PRECUENTA" : complete ? "TICKET INTERNO" : "RECIBO INTERNO";
  return (
    <div className="print-overlay fixed inset-0 z-50 flex items-center justify-center bg-black/50 p-4">
      <article className="print-document ticket-document flex max-h-[calc(100vh-2rem)] w-full max-w-md flex-col overflow-hidden rounded-2xl bg-white shadow-2xl">
        <div className="ticket-scroll overflow-y-auto p-6">
          <header className="text-center">
            <h2 className="ticket-brand tracking-wide">MikuyApp</h2>
            {localName.trim() && <p className="ticket-location mt-1 text-stone-700">{localName}</p>}
            <p className="ticket-type mt-5 tracking-widest">{title}</p>
            <p className="ticket-disclaimer mt-1 text-rose-700">No válido como comprobante fiscal</p>
          </header>
          <div className="ticket-rule my-4 border-t border-dashed border-stone-400" />
          <div className="flex justify-between gap-4 font-medium">
            <span>Pedido #{order.orderId}</span>
            <span>Mesa {order.tableCode}</span>
          </div>
          <p className="mt-1 text-stone-600">{new Date(payment?.paidAt ?? createdAt).toLocaleString("es-PE", { timeZone: "America/Lima" })}</p>

          {(preAccount || complete) && <>
            <div className="ticket-rule my-4 border-t border-dashed border-stone-400" />
            <div className="ticket-section-title grid grid-cols-[3rem_1fr_auto] gap-2 border-b border-stone-300 pb-2 uppercase text-stone-600">
              <span>Cant.</span><span>Producto</span><span>Importe</span>
            </div>
            <ul className="consumption-list divide-y divide-stone-200">
              {order.lines.map((line) => <li className="consumption-item grid grid-cols-[3rem_1fr_auto] gap-2 py-2" key={line.detailId}>
                <span className="quantity-unit">{line.quantity}</span>
                <span className="product-name">{line.productName}</span>
                <span className="line-amount ticket-amount">{money.format(line.lineAmount)}</span>
              </li>)}
            </ul>
            <div className="ticket-rule my-4 border-t border-dashed border-stone-400" />
            <dl className="space-y-1.5">
              <div className="flex justify-between gap-4"><dt>Subtotal</dt><dd>{money.format(subtotal)}</dd></div>
              <div className="flex justify-between gap-4"><dt>Descuento</dt><dd>{money.format(discount)}</dd></div>
              {preAccount && order.paid > 0 && <div className="flex justify-between gap-4"><dt>Pagado</dt><dd>{money.format(order.paid)}</dd></div>}
              <div className="ticket-total flex justify-between gap-4"><dt>{preAccount ? "TOTAL A PAGAR" : "TOTAL"}</dt><dd>{money.format(preAccount ? order.balance : netTotal)}</dd></div>
            </dl>
          </>}

          {!preAccount && payment && !complete && <>
            <div className="ticket-rule my-4 border-t border-dashed border-stone-400" />
            <h3 className="ticket-section-title uppercase tracking-wider">Resumen del pedido</h3>
            <dl className="mt-2 space-y-1.5">
              <div className="flex justify-between gap-4"><dt>Subtotal</dt><dd>{money.format(subtotal)}</dd></div>
              <div className="flex justify-between gap-4"><dt>Descuento</dt><dd>{money.format(discount)}</dd></div>
              <div className="flex justify-between gap-4 font-semibold"><dt>Total del pedido</dt><dd>{money.format(netTotal)}</dd></div>
              <div className="flex justify-between gap-4"><dt>Pagado anteriormente</dt><dd>{money.format(paidPreviously)}</dd></div>
            </dl>
            <div className="ticket-rule my-4 border-t border-dashed border-stone-400" />
            <h3 className="ticket-section-title uppercase tracking-wider">Este cobro</h3>
            <ul className="mt-2 space-y-1.5">
              {payment.lines.map((line, index) => (
                <li className="flex justify-between gap-4" key={`${line.paymentId}-${index}`}>
                  <span className="capitalize">{line.method.toLocaleLowerCase("es-PE")}</span>
                  <span className="ticket-amount">{money.format(line.amount)}</span>
                </li>
              ))}
            </ul>
            <dl className="mt-2 space-y-1.5">
              <div className="flex justify-between gap-4"><dt>Propina</dt><dd>{money.format(payment.tip)}</dd></div>
              <div className="ticket-total flex justify-between gap-4"><dt>IMPORTE COBRADO</dt><dd>{money.format(payment.amount)}</dd></div>
            </dl>
            <div className="ticket-rule my-4 border-t border-dashed border-stone-400" />
            <div className="ticket-total flex justify-between gap-4"><span>SALDO PENDIENTE</span><span>{money.format(balance)}</span></div>
          </>}

          {!preAccount && payment && complete && <>
            <div className="ticket-rule my-4 border-t border-dashed border-stone-400" />
            <h3 className="ticket-section-title uppercase tracking-wider">Cobros del pedido</h3>
            <ol className="mt-2 space-y-3">
              {documentPayments.map((item, paymentIndex) => (
                <li className="payment-summary rounded-lg border border-stone-200 p-3" key={item.chargeId}>
                  <div className="ticket-section-title flex justify-between gap-4">
                    <span>{paymentIndex === documentPayments.length - 1 ? "Cobro final" : `Cobro ${paymentIndex + 1}`}</span>
                    <span>{money.format(item.amount)}</span>
                  </div>
                  <ul className="mt-2 space-y-1">
                    {item.lines.map((line, lineIndex) => (
                      <li className="flex justify-between gap-4" key={`${line.paymentId}-${lineIndex}`}>
                        <span className="capitalize">{line.method.toLocaleLowerCase("es-PE")}</span>
                        <span>{money.format(line.amount)}</span>
                      </li>
                    ))}
                  </ul>
                  <div className="mt-1 flex justify-between gap-4"><span>Propina</span><span>{money.format(item.tip)}</span></div>
                </li>
              ))}
            </ol>
            <div className="ticket-rule my-4 border-t border-dashed border-stone-400" />
            <div className="ticket-total flex justify-between gap-4"><span>SALDO</span><span>{money.format(balance)}</span></div>
          </>}
          <p className="ticket-footer mt-6 text-center text-stone-500">Operado con MikuyApp</p>
        </div>
        <div className="ticket-actions no-print flex shrink-0 gap-3 border-t border-stone-200 bg-white p-4 shadow-[0_-4px_12px_rgba(0,0,0,0.06)]">
          <button className={`${auxiliaryButtonClass} flex-1`} onClick={onClose} type="button">
            Cerrar
          </button>
          <button className={`${primaryButtonClass} flex-1`} onClick={() => window.print()} type="button">
            Imprimir
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
    [movementReason, setMovementReason] = useState(""),
    [closeReason, setCloseReason] = useState(""),
    [discountReason, setDiscountReason] = useState(""),
    [counted, setCounted] = useState(""),
    [paymentAmount, setPaymentAmount] = useState(""),
    [paymentLines, setPaymentLines] = useState([{ method: "EFECTIVO" as PaymentMethodCode, amount: "", tip: "0" }]),
    [discountType, setDiscountType] = useState<"IMPORTE" | "PORCENTAJE">(
      "IMPORTE",
    ),
    [discountValue, setDiscountValue] = useState(""),
    [selectedLines, setSelectedLines] = useState(new Set<number>()),
    [partialMode, setPartialMode] = useState(false),
    [tipMode, setTipMode] = useState(false),
    [divideMode, setDivideMode] = useState(false),
    [productsOpen, setProductsOpen] = useState(false),
    [ordersPanelOpen, setOrdersPanelOpen] = useState(true),
    [discountMode, setDiscountMode] = useState(false),
    [moreOptions, setMoreOptions] = useState(false),
    [paymentsOpen, setPaymentsOpen] = useState(false),
    [cashPanel, setCashPanel] = useState<"MOVEMENT" | "CLOSE" | null>(null),
    [paymentConfirmation, setPaymentConfirmation] = useState<PaymentConfirmation | null>(null),
    [confirmationNotice, setConfirmationNotice] = useState<string | null>(null),
    [paymentFeedback, setPaymentFeedback] = useState<PersistedPayment | null>(null),
    [document, setDocument] = useState<PersistedPayment | null>(null),
    [documentMode, setDocumentMode] = useState<"PRECUENTA" | "PAYMENT" | null>(null),
    [documentCreatedAt, setDocumentCreatedAt] = useState(""),
    [documentOrder, setDocumentOrder] = useState<CashierPendingOrder | null>(
      null,
    );
  const pending = useRef(false),
    paymentConfirmationRef = useRef<PaymentConfirmation | null>(null);
  const selected = orders.find((x) => x.orderId === selectedId) ?? null;
  const clearPaymentOptions = useCallback(() => {
    if (paymentConfirmationRef.current) {
      paymentConfirmationRef.current = null;
      setPaymentConfirmation(null);
      setConfirmationNotice("El saldo o el pedido cambió. Revisa los datos antes de confirmar nuevamente.");
    }
    setPartialMode(false);
    setPaymentAmount("");
    setTipMode(false);
    setPaymentLines([{ method: "EFECTIVO", amount: "", tip: "0" }]);
    setDivideMode(false);
    setProductsOpen(false);
    setSelectedLines(new Set());
    setDiscountMode(false);
    setMoreOptions(false);
    setPaymentsOpen(false);
  }, []);
  const closePaymentConfirmation = () => {
    paymentConfirmationRef.current = null;
    setPaymentConfirmation(null);
  };
  const refresh = useCallback(async (
    showLoading = true,
    isCurrent: () => boolean = () => true,
  ) => {
    if (!service) return;
    if (showLoading) setLoading(true);
    const boxes = await service.getCashboxes(context);
    if (!isCurrent()) return;
    if (!boxes.ok) {
      setError(boxes.error.message);
      setLoading(false);
      return;
    }
    setCashboxes(boxes.data);
    const chosen = boxes.data.length === 1 ? boxes.data[0].id : "";
    setCashboxId(chosen);
    if (!chosen) {
      setSession(null);
      setSummary(null);
    }
    const [s, o] = chosen
      ? await Promise.all([
          service.getActiveSession(context, chosen),
          service.getPendingOrders(context),
        ])
      : [null, await service.getPendingOrders(context)];
    if (!isCurrent()) return;
    if (s && !s.ok) setError(s.error.message);
    else if (s) {
      setSession(s.data);
      if (s.data) {
        const sr = await service.getSummary(context, s.data.id);
        if (!isCurrent()) return;
        setSummary(sr.ok ? sr.data : null);
      } else setSummary(null);
    }
    if (o.ok) {
      setOrders(o.data);
      setSelectedId((x) =>
        o.data.some((y) => y.orderId === x) ? x : (o.data[0]?.orderId ?? null),
      );
    } else setError(o.error.message);
    clearPaymentOptions();
    setLoading(false);
  }, [clearPaymentOptions, context, service]);
  useEffect(() => {
    void refresh();
  }, [attempt, refresh]);
  useEffect(() => {
    if (!cr.ok || !service) return;
    let disposed = false;
    let handle: Awaited<ReturnType<typeof subscribeToOperationsChanges>> | null = null;
    void subscribeToOperationsChanges(
      cr.client,
      () => refresh(false, () => !disposed),
      () => {
        if (disposed) return;
        setError("La conexión en tiempo real se interrumpió. Estamos recuperando Caja.");
      },
      { channelName: "cashier-orders-signals", initialRefresh: false },
    ).then((started) => {
      if (disposed) void started.stop();
      else handle = started;
    });
    return () => {
      disposed = true;
      if (handle) void handle.stop();
    };
  }, [cr, refresh, service]);
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
  const partialAmount = n(paymentAmount);
  const hasPartialObjective = paymentAmount.trim() !== "";
  const invalidPartial = !Number.isFinite(partialAmount) || partialAmount <= 0 || partialAmount >= (selected?.balance ?? 0);
  const paymentToApply = partialMode ? partialAmount : (selected?.balance ?? 0);
  const preparedLines = paymentLines.map((line, index) => {
    const previous = paymentLines.slice(0, index).reduce((sum, item) => sum + (Number(item.amount) || 0), 0);
    const suggestedAmount = index === paymentLines.length - 1 && line.amount === "" ? Math.max(0, paymentToApply - previous) : Number(line.amount);
    return { paymentId: 0, order: index + 1, method: line.method, amount: suggestedAmount, tip: tipMode ? Number(line.tip) : 0 };
  });
  const preparedTotal = preparedLines.reduce((sum, line) => sum + line.amount, 0);
  const preparedTip = preparedLines.reduce((sum, line) => sum + line.tip, 0);
  const invalidLines = preparedLines.some((line) => !Number.isFinite(line.amount) || line.amount <= 0 || !Number.isFinite(line.tip) || line.tip < 0);
  const difference = paymentToApply - preparedTotal;
  const accumulatedPayments = payments.reduce((sum, payment) => sum + payment.amount, 0);
  const chronologicalPayments = [...payments].sort(
    (left, right) => new Date(left.paidAt).getTime() - new Date(right.paidAt).getTime(),
  );
  return (
    <main className="min-h-screen bg-stone-100 p-3 text-stone-900 sm:p-6">
      <div className="mx-auto max-w-7xl">
        <header className="flex flex-wrap items-center justify-between gap-4">
          <div>
            <p className="font-semibold text-emerald-700">MikuyApp · Caja</p>
            <h1 className="text-3xl font-bold">Sesión y cobros</h1>
            <p>{context.local.nombre}</p>
          </div>
          <div className="flex gap-2">
            <button className={auxiliaryButtonClass} onClick={onNavigateToSales}>Resumen diario</button>
            <AuthenticatedUserMenu
              context={context}
              isSigningOut={isSigningOut}
              onSignOut={onSignOut}
            />
          </div>
        </header>
        {error && (
          <div className="mt-4 rounded-xl border border-rose-200 bg-rose-50 p-4">
            <p role="alert">{error}</p>
            <button className={`${secondaryButtonClass} mt-3`} disabled={loading} onClick={() => setAttempt((x) => x + 1)}>
              Reintentar
            </button>
          </div>
        )}
        <section className="mt-3 rounded-xl border border-stone-200 bg-white px-3 py-2 shadow-sm">
          {loading ? (
            <p aria-busy="true">Cargando caja…</p>
          ) : cashboxes.length === 0 ? (
            <p role="alert">No hay una caja activa configurada para este local.</p>
          ) : cashboxes.length > 1 ? (
            <p role="alert">Hay varias cajas activas configuradas. Solicita al administrador dejar una sola caja activa para operar E1.</p>
          ) : (
            <>
              {session ? (
                <div className="flex flex-wrap items-center gap-x-3 gap-y-2 text-sm">
                  <p className="font-bold text-stone-950">{cashboxes[0].codigo} · {cashboxes[0].nombre}</p>
                  <span aria-hidden="true" className="hidden text-stone-300 sm:inline">|</span>
                  <b className="rounded-full bg-emerald-100 px-2.5 py-1 text-emerald-800">{session.estado}</b>
                  <span aria-hidden="true" className="hidden text-stone-300 sm:inline">|</span>
                  <p><span className="text-stone-500">Inicial</span> <b>{money.format(session.monto_inicial)}</b></p>
                  <span aria-hidden="true" className="hidden text-stone-300 sm:inline">|</span>
                  <p><span className="text-stone-500">Esperado</span> <b className="text-emerald-800">{money.format(summary?.efectivo_esperado ?? 0)}</b></p>
                  <div className="flex flex-wrap gap-2 lg:ml-auto">
                    <button className="rounded-lg border border-stone-300 bg-stone-50 px-3 py-2 font-semibold text-stone-800 hover:bg-stone-100 focus:outline-none focus:ring-4 focus:ring-stone-200" onClick={() => setCashPanel(cashPanel === "MOVEMENT" ? null : "MOVEMENT")} type="button">Movimientos</button>
                    <button className="rounded-lg border border-emerald-700 bg-white px-3 py-2 font-bold text-emerald-800 hover:bg-emerald-50 focus:outline-none focus:ring-4 focus:ring-emerald-100" onClick={() => setCashPanel(cashPanel === "CLOSE" ? null : "CLOSE")} type="button">Cerrar caja</button>
                  </div>
                </div>
              ) : (
                <div className="py-1">
                  <div className="flex flex-wrap items-center justify-between gap-2">
                    <div><p className="text-xs font-bold uppercase tracking-wider text-emerald-700">Estado de caja</p><h2 className="text-lg font-bold">{cashboxes[0].codigo} · {cashboxes[0].nombre}</h2></div>
                    <span className="rounded-full bg-stone-100 px-2.5 py-1 text-sm font-bold text-stone-700">SIN SESIÓN</span>
                  </div>
                  <div className="mt-2 flex flex-col gap-2 sm:max-w-md">
                  <label className="block text-sm font-semibold text-stone-700">
                    <span className="block">Monto inicial</span>
                    <input
                      className={fieldClass}
                      min="0"
                      step="0.01"
                      value={initial}
                      onChange={(e) => setInitial(e.target.value)}
                      type="number"
                    />
                  </label>
                  <button
                    className={primaryButtonClass}
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
                </div>
              )}
            </>
          )}
        </section>
        {session && cashPanel && (
          <section className="mt-3 rounded-xl border border-stone-200 bg-white p-4 shadow-sm">
            <p className="mt-2 text-sm">
              Historial reciente: {history.length} sesiones.
            </p>
            <div className="mt-4">
              {cashPanel === "MOVEMENT" &&
              <form
                className="space-y-3 rounded-xl border border-stone-200 bg-stone-50 p-4"
                onSubmit={(e) => {
                  e.preventDefault();
                  if (service)
                    void run(() =>
                      service.registerMovement(
                        context,
                        session.id,
                        movement,
                        n(movementAmount),
                        movementReason,
                        key(),
                      ),
                    );
                }}
              >
                <h3 className="text-lg font-bold">Registrar movimiento</h3>
                <label className="block text-sm font-semibold text-stone-700">Tipo
                <select
                  className={selectClass}
                  value={movement}
                  onChange={(e) =>
                    setMovement(e.target.value as typeof movement)
                  }
                >
                  <option>ENTRADA</option>
                  <option>SALIDA</option>
                </select>
                </label>
                <label className="block text-sm font-semibold text-stone-700">Importe
                <input
                  className={fieldClass}
                  value={movementAmount}
                  onChange={(e) => setMovementAmount(e.target.value)}
                  type="number"
                />
                </label>
                <label className="block text-sm font-semibold text-stone-700">Motivo
                <input
                  className={fieldClass}
                  value={movementReason}
                      onChange={(e) => setMovementReason(e.target.value)}
                />
                </label>
                <button className={secondaryButtonClass} disabled={busy}>Confirmar movimiento</button>
              </form>
              }
              {cashPanel === "CLOSE" &&
              <form
                className="space-y-3 rounded-xl border border-stone-200 bg-stone-50 p-4"
                onSubmit={(e) => {
                  e.preventDefault();
                  if (service)
                    void run(() =>
                      service.closeSession(
                        context,
                        session.id,
                        n(counted),
                            closeReason || null,
                        key(),
                      ),
                    );
                }}
              >
                <h3 className="text-lg font-bold">Cierre de caja</h3>
                <p className="rounded-lg bg-white p-3 text-sm text-stone-600">
                  Efectivo esperado<br />
                  <b className="text-lg text-stone-950">{money.format(summary?.efectivo_esperado ?? 0)}</b>
                </p>
                <label className="block text-sm font-semibold text-stone-700">Efectivo contado
                <input
                  className={fieldClass}
                  value={counted}
                  onChange={(e) => setCounted(e.target.value)}
                  type="number"
                />
                </label>
                <p>PostgreSQL calculará y confirmará la diferencia.</p>
                <label className="block text-sm font-semibold text-stone-700">Motivo de diferencia
                <input
                  className={fieldClass}
                  value={closeReason}
                      onChange={(e) => setCloseReason(e.target.value)}
                />
                </label>
                <button className={primaryButtonClass} disabled={busy}>Confirmar cierre</button>
              </form>
              }
            </div>
          </section>
        )}
        {paymentFeedback && <div className="mt-4 rounded-xl border border-emerald-300 bg-emerald-50 p-4 text-emerald-950" role="status">
          <b>Cobro registrado: {money.format(paymentFeedback.amount)} · {paymentFeedback.lines.length} {paymentFeedback.lines.length === 1 ? "medio" : "medios"}</b>
          <p>Saldo restante: {money.format(paymentFeedback.balance)} · Pedido {paymentFeedback.orderStatus === "PAGADO" ? "PAGADO" : "pendiente de completar"}.</p>
        </div>}
        <div className={`mt-3 grid min-w-0 gap-4 ${ordersPanelOpen ? "lg:grid-cols-[22rem_minmax(0,1fr)]" : "grid-cols-[3.5rem_minmax(0,1fr)]"}`}>
          <section className={`min-w-0 rounded-2xl border border-stone-200 bg-white shadow-sm ${ordersPanelOpen ? "p-4" : "p-1.5"}`}>
            <div className={`flex items-center ${ordersPanelOpen ? "justify-between gap-3" : "justify-center"}`}>
              {ordersPanelOpen && <h2 className="text-xl font-bold">Pedidos pendientes</h2>}
              <button
                aria-expanded={ordersPanelOpen}
                aria-label={ordersPanelOpen ? "Ocultar lista de pedidos pendientes" : "Mostrar lista de pedidos pendientes"}
                className="flex h-9 w-9 shrink-0 items-center justify-center rounded-lg text-stone-600 transition hover:bg-stone-100 hover:text-stone-950 focus:outline-none focus:ring-4 focus:ring-stone-200"
                onClick={() => setOrdersPanelOpen((value) => !value)}
                title={ordersPanelOpen ? "Ocultar lista de pedidos pendientes" : "Mostrar lista de pedidos pendientes"}
                type="button"
              >
                <svg aria-hidden="true" className="h-5 w-5" fill="none" viewBox="0 0 24 24">
                  <rect height="16" rx="2" stroke="currentColor" strokeWidth="1.8" width="18" x="3" y="4" />
                  <path d="M9 4v16" stroke="currentColor" strokeWidth="1.8" />
                  <path d={ordersPanelOpen ? "m6.5 10-2 2 2 2" : "m5.5 10 2 2-2 2"} stroke="currentColor" strokeLinecap="round" strokeLinejoin="round" strokeWidth="1.8" />
                </svg>
              </button>
            </div>
            {ordersPanelOpen && <>
            {loading ? (
              <p>Cargando pedidos pendientes…</p>
            ) : orders.length === 0 ? (
              <p>No hay pedidos pendientes de pago.</p>
            ) : (
              orders.map((x) => (
                <button
                  className={`mt-3 block w-full rounded-xl border p-3 text-left transition focus:outline-none focus:ring-4 focus:ring-emerald-100 ${selectedId === x.orderId ? "border-emerald-600 bg-emerald-50 shadow-sm" : "border-stone-200 hover:border-emerald-300 hover:bg-stone-50"}`}
                      key={x.orderId}
                      onClick={() => {
                        clearPaymentOptions();
                        setPaymentFeedback(null);
                        setSelectedId(x.orderId);
                      }}
                >
                  <span className="block font-bold text-stone-950">Mesa {x.tableCode}</span>
                  <span className="text-sm text-stone-600">Pedido #{x.orderId}</span>
                  <span className="mt-2 block text-sm text-stone-600">Saldo <b className="text-base text-emerald-800">{money.format(x.balance)}</b></span>
                </button>
              ))
            )}
            </>}
            {!ordersPanelOpen && <div className="mt-2 max-h-[calc(100vh-16rem)] space-y-2 overflow-x-hidden overflow-y-auto border-t border-stone-200 pt-2">
              {!loading && orders.map((order) => (
                <button
                  aria-label={`Abrir ${order.tableName}, pedido ${order.orderId}, saldo ${money.format(order.balance)}`}
                  className={`flex h-9 w-9 items-center justify-center rounded-lg border text-xs font-black transition focus:outline-none focus:ring-4 focus:ring-emerald-100 ${selectedId === order.orderId ? "border-emerald-700 bg-emerald-700 text-white shadow-sm" : "border-stone-300 bg-white text-stone-700 hover:border-emerald-500 hover:bg-emerald-50"}`}
                  key={order.orderId}
                  onClick={() => {
                    clearPaymentOptions();
                    setPaymentFeedback(null);
                    setSelectedId(order.orderId);
                  }}
                  title={`${order.tableName} · Pedido #${order.orderId} · Saldo ${money.format(order.balance)}`}
                  type="button"
                >
                  {order.tableCode}
                </button>
              ))}
            </div>}
          </section>
          <section className="min-w-0 rounded-2xl border border-stone-200 bg-white p-5 shadow-sm">
            {selected ? (
              <>
                <div className="flex flex-wrap items-baseline justify-between gap-x-4 gap-y-1 border-b border-stone-200 pb-4">
                  <h2 className="text-2xl font-bold">Detalle del pedido #{selected.orderId}</h2>
                  <p className="rounded-full bg-emerald-100 px-3 py-1 font-bold text-emerald-900">{selected.tableName}</p>
                </div>
                <div className="mt-3 flex flex-wrap items-center gap-x-5 gap-y-2 rounded-xl bg-stone-50 px-3 py-2 text-sm text-stone-600">
                  <p>Subtotal <b className="ml-1 text-stone-950">{money.format(selected.subtotal)}</b></p>
                  <p>Descuento <b className="ml-1 text-stone-950">{money.format(selected.discount)}</b></p>
                  <p>Total neto <b className="ml-1 text-stone-950">{money.format(selected.netTotal)}</b></p>
                  <p>Pagado <b className="ml-1 text-stone-950">{money.format(selected.paid)}</b></p>
                </div>
                <form
                  className="mt-5 rounded-xl border-2 border-emerald-200 bg-emerald-50/40 p-4"
                  onSubmit={(e) => {
                    e.preventDefault();
                    if (!session || busy || invalidLines || difference !== 0 || (partialMode && invalidPartial)) return;
                    const confirmation: PaymentConfirmation = {
                      orderId: selected.orderId,
                      tableCode: selected.tableCode,
                      amount: paymentToApply,
                      lines: preparedLines,
                      tip: preparedTip,
                      currentBalance: selected.balance,
                      partial: partialMode,
                    };
                    setConfirmationNotice(null);
                    paymentConfirmationRef.current = confirmation;
                    setPaymentConfirmation(confirmation);
                  }}
                >
                  <div className="mb-3 flex flex-wrap items-baseline justify-between gap-2">
                    <h3 className="text-xl font-bold">Cobro</h3>
                    <p className="text-sm font-semibold text-stone-600">Saldo: <b className="text-xl text-emerald-800">{money.format(selected.balance)}</b></p>
                  </div>
                  {partialMode && <label className="mt-4 block max-w-sm text-sm font-semibold text-stone-700">Importe a cobrar <span className="font-normal">(menor a {money.format(selected.balance)})</span>
                    <input className={fieldClass} min="0.01" max={Math.max(0.01, selected.balance - 0.01)} step="0.01" value={paymentAmount} onChange={(e) => setPaymentAmount(e.target.value)} type="number" />
                    {invalidPartial && paymentAmount && <span className="mt-1 block text-sm text-rose-700">Ingresa un importe mayor que cero y menor al saldo.</span>}
                  </label>}
                  <div className="mt-4 space-y-3">
                    {paymentLines.map((line, index) => {
                      const prepared = preparedLines[index];
                      return <div className="grid gap-3 rounded-xl border border-stone-200 bg-white p-3 sm:grid-cols-[1fr_1fr_auto]" key={index}>
                        <label className="text-sm font-semibold text-stone-700">Medio
                          <select className={selectClass} value={line.method} onChange={(e) => setPaymentLines((old) => old.map((item, i) => i === index ? { ...item, method: e.target.value as PaymentMethodCode } : item))}>
                            {methods.map((x) => <option key={x}>{x}</option>)}
                          </select>
                        </label>
                        <label className="text-sm font-semibold text-stone-700">Importe
                          <input className={fieldClass} min="0.01" step="0.01" type="number" value={line.amount === "" ? prepared.amount : line.amount} onChange={(e) => setPaymentLines((old) => old.map((item, i) => i === index ? { ...item, amount: e.target.value } : item))} />
                        </label>
                        <div className="flex items-end gap-2 self-end">
                          <button aria-label={`Agregar medio después de la línea ${index + 1}`} className="flex h-10 w-10 items-center justify-center rounded-full bg-emerald-700 text-xl font-bold text-white shadow-sm hover:bg-emerald-800 focus:outline-none focus:ring-4 focus:ring-emerald-200" type="button" onClick={() => setPaymentLines((old) => [...old.slice(0, index + 1), { method: "EFECTIVO", amount: "", tip: "0" }, ...old.slice(index + 1)])}>+</button>
                          {index > 0 && <button aria-label={`Quitar medio ${index + 1}`} className="flex h-10 w-10 items-center justify-center rounded-full bg-rose-700 text-xl font-bold text-white shadow-sm hover:bg-rose-800 focus:outline-none focus:ring-4 focus:ring-rose-200" type="button" onClick={() => setPaymentLines((old) => old.filter((_, i) => i !== index))}>−</button>}
                        </div>
                        {tipMode && <label className="text-sm font-semibold text-stone-700 sm:col-span-2">Propina de este medio
                          <input className={fieldClass} min="0" step="0.01" type="number" value={line.tip} onChange={(e) => setPaymentLines((old) => old.map((item, i) => i === index ? { ...item, tip: e.target.value } : item))} />
                        </label>}
                      </div>;
                    })}
                  </div>
                  <div className="mt-4 grid gap-2 rounded-xl border border-stone-200 bg-white p-3 sm:grid-cols-4">
                    <p>Saldo pendiente<br /><b>{money.format(selected.balance)}</b></p>
                    <p>A cobrar<br /><b>{partialMode && !hasPartialObjective ? "—" : money.format(paymentToApply)}</b></p>
                    <p>Distribuido<br /><b>{money.format(preparedTotal)}</b></p>
                    <p>{difference >= 0 ? "Falta" : "Exceso"}<br /><b className={difference === 0 ? "text-emerald-700" : "text-rose-700"}>{partialMode && !hasPartialObjective ? "—" : money.format(Math.abs(difference))}</b></p>
                  </div>
                  {tipMode && <p className="mt-2 text-sm">Propina total: <b>{money.format(preparedTip)}</b></p>}
                  <div className="mt-4 flex flex-wrap items-center gap-1.5 md:flex-nowrap">
                    <button className={`${compactPrimaryButtonClass} w-full sm:w-auto md:shrink-0`} aria-busy={busy} disabled={busy || !session || selected.balance <= 0 || invalidLines || difference !== 0 || (partialMode && invalidPartial)}>
                      {partialMode ? `Cobrar parte · ${money.format(paymentToApply)}` : `Cobrar · ${money.format(selected.balance)}`}
                    </button>
                    <div className="flex min-w-0 flex-wrap gap-1.5 md:ml-auto md:flex-nowrap md:justify-end">
                      <button className={compactAuxiliaryButtonClass} type="button" onClick={() => { setDocumentOrder(selected); setDocument(null); setDocumentMode("PRECUENTA"); setDocumentCreatedAt(new Date().toISOString()); }}>Precuenta</button>
                      <button className={compactAuxiliaryButtonClass} type="button" onClick={() => { setPartialMode((value) => !value); setPaymentAmount(""); }}>{partialMode ? "Cobro total" : "Cobrar una parte"}</button>
                      <button className={compactAuxiliaryButtonClass} type="button" onClick={() => { setTipMode((value) => !value); setPaymentLines((old) => old.map((line) => ({ ...line, tip: "0" }))); }}>Propina</button>
                      <button className={compactAuxiliaryButtonClass} type="button" onClick={() => setMoreOptions((value) => !value)}>Más opciones</button>
                    </div>
                  </div>
                  {moreOptions && <div className="mt-3 flex flex-wrap gap-2 rounded-xl border border-stone-200 bg-stone-50 p-3">
                    <button className={secondaryButtonClass} type="button" onClick={() => { setProductsOpen(true); setDivideMode(true); setDiscountMode(false); setMoreOptions(false); }}>Dividir por productos</button>
                    <button className={secondaryButtonClass} disabled={selected.paid > 0} type="button" onClick={() => { setDiscountMode(true); setDivideMode(false); setMoreOptions(false); }}>Solicitar descuento</button>
                  </div>}
                </form>
                {confirmationNotice && <p className="mt-3 rounded-xl border border-amber-300 bg-amber-50 p-3 text-sm font-semibold text-amber-900" role="status">{confirmationNotice}</p>}
                {discount && (
                  <p className="mt-4 rounded-xl border border-amber-200 bg-amber-50 p-3 text-sm text-amber-900">
                    Descuento: <b>{discount.estado}</b> · {discount.tipo} · {formatDiscountValue(discount)}
                  </p>
                )}
                {discountMode && <form
                  className="mt-4 rounded-xl border border-stone-200 bg-white p-4"
                  onSubmit={(e) => {
                    e.preventDefault();
                    if (service) void run(async () => {
                      const result = await service.requestDiscount(context, selected.orderId, discountType, n(discountValue), discountReason, key());
                      if (result.ok) setDiscountMode(false);
                      return result;
                    });
                  }}
                >
                  <h3 className="font-bold">Solicitar descuento</h3>
                  <p className="text-sm text-stone-600">Requiere autorización de un administrador antes del primer pago.</p>
                  <div className="mt-3 grid gap-4 sm:grid-cols-3">
                    <label className="block text-sm font-semibold text-stone-700">Tipo
                      <select className={selectClass} value={discountType} onChange={(e) => setDiscountType(e.target.value as typeof discountType)}>
                        <option>IMPORTE</option>
                        <option>PORCENTAJE</option>
                      </select>
                    </label>
                    <label className="block text-sm font-semibold text-stone-700">Valor
                      <input className={fieldClass} value={discountValue} onChange={(e) => setDiscountValue(e.target.value)} />
                    </label>
                    <label className="block text-sm font-semibold text-stone-700">Motivo
                      <input className={fieldClass} value={discountReason} onChange={(e) => setDiscountReason(e.target.value)} />
                    </label>
                  </div>
                  <button className={`${secondaryButtonClass} mt-4 w-full sm:w-auto`} disabled={busy || selected.paid > 0}>
                    Solicitar descuento
                  </button>
                </form>}
                <section className="mt-5 border-t border-stone-200 pt-5">
                  <div className="flex flex-wrap items-center justify-between gap-2">
                    <h3 className="text-lg font-bold">{payments.length} {payments.length === 1 ? "cobro realizado" : "cobros realizados"} · {money.format(accumulatedPayments)} acumulado</h3>
                    {payments.length > 0 && <button className={auxiliaryButtonClass} type="button" onClick={() => setPaymentsOpen((value) => !value)}>{paymentsOpen ? "Ocultar pagos" : "Ver pagos"}</button>}
                  </div>
                  {payments.length === 0 ? (
                    <p className="mt-3 rounded-xl bg-stone-50 p-4 text-stone-600">Sin pagos confirmados.</p>
                  ) : paymentsOpen && (
                    <div className="mt-3 max-h-72 overflow-y-auto rounded-xl border border-stone-200">
                      <table className="w-full table-fixed text-left text-xs sm:text-sm">
                        <colgroup>
                          <col className="w-14 sm:w-16" />
                          <col />
                          <col className="w-[4.75rem] sm:w-24" />
                          <col className="w-[4.75rem] sm:w-24" />
                          <col className="w-[4.75rem] sm:w-24" />
                        </colgroup>
                        <thead className="sticky top-0 bg-stone-100 text-stone-600">
                          <tr>
                            <th className="px-2 py-2 font-semibold" scope="col">Hora</th>
                            <th className="px-2 py-2 font-semibold" scope="col">Medio(s)</th>
                            <th className="px-2 py-2 text-right font-semibold" scope="col">Importe</th>
                            <th className="px-2 py-2 text-right font-semibold" scope="col">Propina</th>
                            <th className="px-2 py-2 text-right font-semibold" scope="col">Saldo</th>
                          </tr>
                        </thead>
                        <tbody className="divide-y divide-stone-200 bg-white">
                          {chronologicalPayments.map((payment) => (
                            <tr key={payment.chargeId}>
                              <td className="px-2 py-2 align-top text-stone-600">{new Date(payment.paidAt).toLocaleTimeString("es-PE", { hour: "2-digit", minute: "2-digit" })}</td>
                              <td className="break-words px-2 py-2 align-top font-medium">
                                {payment.lines.map((line, index) => (
                                  <span key={line.paymentId}>{index > 0 && " + "}{line.method} {money.format(line.amount)}</span>
                                ))}
                              </td>
                              <td className="whitespace-nowrap px-2 py-2 text-right align-top font-semibold">{money.format(payment.amount)}</td>
                              <td className="whitespace-nowrap px-2 py-2 text-right align-top">{money.format(payment.tip)}</td>
                              <td className="whitespace-nowrap px-2 py-2 text-right align-top font-semibold">{money.format(payment.balance)}</td>
                            </tr>
                          ))}
                        </tbody>
                      </table>
                    </div>
                  )}
                </section>
                <section className="mt-5 border-t border-stone-200 pt-4">
                  <div className="flex flex-wrap items-center justify-between gap-2">
                    <h3 className="font-bold">Productos del pedido ({selected.lines.length})</h3>
                    <button
                      className={auxiliaryButtonClass}
                      type="button"
                      onClick={() => {
                        if (productsOpen) {
                          setDivideMode(false);
                          setSelectedLines(new Set());
                        }
                        setProductsOpen((value) => !value);
                      }}
                    >
                      {productsOpen ? "Ocultar detalle" : "Ver detalle"}
                    </button>
                  </div>
                  {productsOpen && <div className="mt-3 rounded-xl bg-stone-50 p-4">
                    <Lines
                      order={selected}
                      select={selectedLines}
                      selectable={divideMode}
                      onSelect={(id) =>
                        setSelectedLines((old) => {
                          const x = new Set(old);
                          x.has(id) ? x.delete(id) : x.add(id);
                          return x;
                        })
                      }
                    />
                    {divideMode && <div className="mt-3 rounded-xl border border-stone-200 bg-white p-3">
                      <p className="text-sm">Total seleccionado <b>{money.format(suggested)}</b> · Saldo <b>{money.format(selected.balance)}</b></p>
                      {suggested > selected.balance && <p className="mt-1 text-sm font-semibold text-rose-700">La selección excede el saldo por {money.format(suggested - selected.balance)}.</p>}
                      <div className="mt-3 flex flex-wrap gap-2">
                        <button className={secondaryButtonClass} disabled={suggested <= 0 || suggested > selected.balance} type="button" onClick={() => { setPartialMode(true); setPaymentAmount(String(suggested)); setDivideMode(false); setSelectedLines(new Set()); }}>Usar importe seleccionado</button>
                        <button className={auxiliaryButtonClass} type="button" onClick={() => { setDivideMode(false); setSelectedLines(new Set()); }}>Cerrar</button>
                      </div>
                    </div>}
                  </div>}
                </section>
              </>
            ) : (
              <p>Selecciona un pedido.</p>
            )}
          </section>
        </div>
        </div>
        {paymentConfirmation && selected && (
          <div className="fixed inset-0 z-40 flex items-center justify-center bg-black/50 p-4" role="presentation">
            <section aria-labelledby="payment-confirmation-title" aria-modal="true" className="w-full max-w-lg rounded-2xl bg-white p-5 shadow-2xl" role="dialog">
              <p className="text-xs font-bold uppercase tracking-wider text-emerald-700">Confirmación requerida</p>
              <h2 className="mt-1 text-2xl font-bold" id="payment-confirmation-title">Confirmar cobro</h2>
              <dl className="mt-4 grid grid-cols-2 gap-3 rounded-xl bg-stone-50 p-4 text-sm">
                <div><dt className="text-stone-600">Mesa</dt><dd className="font-bold">{paymentConfirmation.tableCode}</dd></div>
                <div><dt className="text-stone-600">Pedido</dt><dd className="font-bold">#{paymentConfirmation.orderId}</dd></div>
                <div><dt className="text-stone-600">Importe</dt><dd className="font-bold text-emerald-800">{money.format(paymentConfirmation.amount)}</dd></div>
                <div className="col-span-2"><dt className="text-stone-600">Medios de pago</dt><dd><ul className="mt-1 divide-y divide-stone-200 rounded-lg border border-stone-200 bg-white px-3">{paymentConfirmation.lines.map((line, index) => <li className="flex justify-between gap-3 py-2 font-bold" key={`${line.method}-${index}`}><span>{line.method}</span><span>{money.format(line.amount)}{line.tip > 0 ? ` · propina ${money.format(line.tip)}` : ""}</span></li>)}</ul></dd></div>
                <div><dt className="text-stone-600">Propina</dt><dd className="font-bold">{money.format(paymentConfirmation.tip)}</dd></div>
                <div><dt className="text-stone-600">Saldo actual</dt><dd className="font-bold">{money.format(paymentConfirmation.currentBalance)}</dd></div>
              </dl>
              {paymentConfirmation.partial ? (
                <p className="mt-4 rounded-xl border border-amber-200 bg-amber-50 p-3 font-semibold text-amber-950">Después del pago quedará un saldo de {money.format(paymentConfirmation.currentBalance - paymentConfirmation.amount)}.</p>
              ) : (
                <p className="mt-4 rounded-xl border border-emerald-200 bg-emerald-50 p-3 font-semibold text-emerald-950">Este cobro completará el pedido y liberará la mesa.</p>
              )}
              <div className="mt-5 flex flex-col-reverse gap-2 sm:flex-row sm:justify-end">
                <button className={auxiliaryButtonClass} disabled={busy} onClick={closePaymentConfirmation} type="button">Volver</button>
                <button
                  aria-busy={busy}
                  className={primaryButtonClass}
                  disabled={busy}
                  onClick={() => {
                    const confirmation = paymentConfirmationRef.current;
                    if (!service || !session || !confirmation || selected.orderId !== confirmation.orderId || selected.balance !== confirmation.currentBalance) {
                      closePaymentConfirmation();
                      setConfirmationNotice("El saldo cambió. Actualiza y revisa el cobro antes de confirmar nuevamente.");
                      void refresh(false);
                      return;
                    }
                    void run(async () => {
                      const r = await service.registerPayment(
                        context,
                        confirmation.orderId,
                        session.id,
                        confirmation.partial ? "PARCIAL" : "TOTAL",
                        confirmation.lines.map(({ method, amount, tip }) => ({ method, amount, tip })),
                        key(),
                      );
                      if (r.ok) {
                        setDocumentOrder(selected);
                        setDocument(r.data);
                        setDocumentMode("PAYMENT");
                        setDocumentCreatedAt(r.data.paidAt);
                        setPaymentFeedback(r.data);
                        closePaymentConfirmation();
                      }
                      return r;
                    });
                  }}
                  type="button"
                >
                  {busy ? "Registrando cobro…" : `Confirmar cobro ${money.format(paymentConfirmation.amount)}`}
                </button>
              </div>
            </section>
          </div>
        )}
        {documentMode && documentOrder && (documentMode === "PRECUENTA" || document) && (
        <InternalDocument
          order={documentOrder}
          payment={documentMode === "PAYMENT" ? document : null}
          payments={payments}
          localName={context.local.nombre}
          createdAt={documentCreatedAt}
          onClose={() => {
            setDocument(null);
            setDocumentMode(null);
            setDocumentCreatedAt("");
            setDocumentOrder(null);
          }}
        />
      )}
    </main>
  );
}
