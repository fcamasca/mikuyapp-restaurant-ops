import type { SupabaseClient } from "@supabase/supabase-js";
import type { ValidatedProfileContext } from "./profileContext";
import type { PaymentMethodCode } from "../types/operations";
export interface Cashbox {
  id: string;
  codigo: string;
  nombre: string;
  activo: boolean;
}
export interface CashSession {
  id: string;
  caja_id: string;
  abierta_por: string;
  abierta_en: string;
  monto_inicial: number;
  estado: "ABIERTA" | "CERRADA";
}
export interface SessionSummary {
  sesion_caja_id: string;
  estado: string;
  monto_inicial: number;
  efectivo_esperado: number;
  pago_efectivo: number;
  propina_efectivo: number;
  entradas: number;
  salidas: number;
}
export interface CloseSnapshot {
  sesion_caja_id: string;
  caja_id: string;
  local_id: string;
  cerrado_por: string;
  cerrado_en: string;
  tipo_cierre: "NORMAL" | "SUPERVISOR";
  pago_efectivo: number;
  propina_efectivo: number;
  pago_yape: number;
  propina_yape: number;
  pago_plin: number;
  propina_plin: number;
  pago_tarjeta: number;
  propina_tarjeta: number;
  entradas: number;
  salidas: number;
  efectivo_esperado: number;
  efectivo_contado: number;
  diferencia: number;
  motivo: string | null;
}
export interface SessionCashReport {
  sessionId: string;
  cashboxCode: string;
  cashboxName: string;
  openedBy: string;
  closedBy: string | null;
  openedAt: string;
  closedAt: string | null;
  initialAmount: number;
  salesByMethod: Readonly<Record<PaymentMethodCode, number>>;
  tipsByMethod: Readonly<Record<PaymentMethodCode, number>>;
  entries: number;
  exits: number;
  expectedCash: number;
  countedCash: number | null;
  difference: number | null;
}
export interface CashMovement {
  id: string;
  sessionId: string;
  type: "ENTRADA" | "SALIDA";
  amount: number;
  reason: string;
  actorId: string;
  actorName: string;
  createdAt: string;
}
export interface NewCashMovement {
  type: "ENTRADA" | "SALIDA";
  amount: number;
  reason: string;
}
export interface CashierLine {
  detailId: number;
  productId: string;
  productName: string;
  quantity: number;
  unitPrice: number;
  lineAmount: number;
}
export interface CashierPendingOrder {
  orderId: number;
  orderStatus: "ENTREGADO";
  createdAt: string;
  tableId: string;
  tableCode: string;
  tableName: string;
  tableStatus: "PENDIENTE_PAGO";
  lines: readonly CashierLine[];
  total: number;
  subtotal: number;
  discount: number;
  netTotal: number;
  paid: number;
  balance: number;
}
export interface PaymentMediumLine {
  paymentId: number;
  order: number;
  amount: number;
  tip: number;
  method: PaymentMethodCode;
}
export interface PersistedPayment {
  chargeId: string;
  orderId: number;
  orderStatus: "ENTREGADO" | "PAGADO";
  tableId: string;
  tableStatus: "PENDIENTE_PAGO" | "LIBRE";
  amount: number;
  tip: number;
  lines: readonly PaymentMediumLine[];
  paidAt: string;
  subtotal: number;
  discount: number;
  netTotal: number;
  paid: number;
  balance: number;
}
export interface PaymentHistory {
  chargeId: string;
  chargeType: "TOTAL" | "PARCIAL";
  amount: number;
  tip: number;
  lines: readonly PaymentMediumLine[];
  actorName: string;
  paidAt: string;
  subtotal: number;
  discount: number;
  netTotal: number;
  paid: number;
  balance: number;
}
export interface AdminOrder {
  orderId: number;
  tableCode: string;
  tableName: string;
  orderStatus: string;
  tableStatus: string;
  hasPayments: boolean;
  paymentCount: number;
  subtotal: number;
  discount: number;
  netTotal: number;
  paid: number;
  balance: number;
}
export interface AdminDiscount {
  id: string;
  pedido_id: number;
  tipo: "IMPORTE" | "PORCENTAJE";
  valor_solicitado: number;
  motivo: string;
  estado: "PENDIENTE" | "AUTORIZADO" | "RECHAZADO";
}
export type CashierResult<T> =
  | { ok: true; data: T }
  | {
      ok: false;
      error: {
        kind: "unauthorized" | "conflict" | "operation-error";
        message: string;
      };
    };
type Client = Pick<SupabaseClient, "rpc" | "from">;
interface PendingRow {
  pedido_id: number;
  pedido_estado: string;
  pedido_creado_en: string;
  mesa_id: string;
  mesa_codigo: string;
  mesa_nombre: string;
  mesa_estado: string;
  detalle_id: number;
  producto_id: string;
  producto_nombre: string;
  cantidad: number;
  precio_unitario: number | string;
  importe_linea: number | string;
  total_pedido: number | string;
  subtotal: number | string;
  descuento: number | string;
  total_neto: number | string;
  pagado_acumulado: number | string;
  saldo: number | string;
}
const methods = new Set<PaymentMethodCode>([
  "EFECTIVO",
  "YAPE",
  "PLIN",
  "TARJETA",
]);
const fail = (message: string, code?: string): CashierResult<never> => ({
  ok: false,
  error: {
    kind: code === "40001" || code === "23505" ? "conflict" : "operation-error",
    message,
  },
});
const allow = (c: ValidatedProfileContext, roles: string[]) =>
  roles.includes(c.role.codigo);
export function groupCashierOrders(
  rows: readonly PendingRow[],
): readonly CashierPendingOrder[] {
  const m = new Map<number, CashierPendingOrder>();
  for (const r of rows) {
    const line = {
        detailId: r.detalle_id,
        productId: r.producto_id,
        productName: r.producto_nombre,
        quantity: r.cantidad,
        unitPrice: Number(r.precio_unitario),
        lineAmount: Number(r.importe_linea),
      },
      old = m.get(r.pedido_id);
    if (old) m.set(r.pedido_id, { ...old, lines: [...old.lines, line] });
    else
      m.set(r.pedido_id, {
        orderId: r.pedido_id,
        orderStatus: "ENTREGADO",
        createdAt: r.pedido_creado_en,
        tableId: r.mesa_id,
        tableCode: r.mesa_codigo,
        tableName: r.mesa_nombre,
        tableStatus: "PENDIENTE_PAGO",
        lines: [line],
        total: Number(r.total_pedido),
        subtotal: Number(r.subtotal),
        discount: Number(r.descuento),
        netTotal: Number(r.total_neto),
        paid: Number(r.pagado_acumulado),
        balance: Number(r.saldo),
      });
  }
  return [...m.values()].sort(
    (a, b) => a.createdAt.localeCompare(b.createdAt) || a.orderId - b.orderId,
  );
}
export function createCashierService(client: Client) {
  const rpc = async <T>(
    name: string,
    args?: Record<string, unknown>,
  ): Promise<CashierResult<T>> => {
    try {
      const r = await client.rpc(name, args);
      return r.error
        ? fail(
            "La operación cambió o no pudo completarse. Recarga los datos.",
            r.error.code,
          )
        : { ok: true, data: r.data as T };
    } catch {
      return fail("No pudimos completar la operación. Intenta nuevamente.");
    }
  };
  return {
    async getCashboxes(c: ValidatedProfileContext) {
      if (!allow(c, ["CAJA"])) return fail("No autorizado.");
      const r = await client
        .from("caja")
        .select("id,codigo,nombre,activo")
        .eq("local_id", c.local.id)
        .eq("activo", true)
        .order("codigo");
      return r.error
        ? fail("No pudimos cargar las cajas.")
        : { ok: true as const, data: r.data as Cashbox[] };
    },
    async getActiveSession(c: ValidatedProfileContext, id: string) {
      if (!allow(c, ["CAJA"])) return fail("No autorizado.");
      const r = await rpc<Record<string, unknown> | null>(
        "rpc_obtener_sesion_caja_activa",
        { p_caja_id: id, p_sesion_id: null },
      );
      return r.ok
        ? { ok: true as const, data: r.data ? session(r.data) : null }
        : r;
    },
    async openSession(
      c: ValidatedProfileContext,
      id: string,
      amount: number,
      key: string,
    ) {
      if (!allow(c, ["CAJA"])) return fail("No autorizado.");
      const r = await rpc<Record<string, unknown>>("rpc_abrir_sesion_caja", {
        p_caja_id: id,
        p_monto_inicial: amount,
        p_idempotency_key: key,
      });
      return r.ok ? { ok: true as const, data: session(r.data) } : r;
    },
    async getSummary(c: ValidatedProfileContext, id: string) {
      if (!allow(c, ["CAJA", "ADMINISTRADOR"])) return fail("No autorizado.");
      const r = await rpc<Record<string, unknown>>(
        "rpc_obtener_resumen_sesion_caja",
        { p_sesion_caja_id: id },
      );
      return r.ok ? { ok: true as const, data: summary(r.data) } : r;
    },
    async getSessionReport(c: ValidatedProfileContext, id: string) {
      if (!allow(c, ["CAJA", "ADMINISTRADOR"])) return fail("No autorizado.");
      const r = await rpc<Record<string, unknown>[]>("rpc_obtener_reportes_sesion_caja", {
        p_sesion_caja_id: id,
      });
      return r.ok && r.data?.[0]
        ? { ok: true as const, data: sessionReport(r.data[0]) }
        : r.ok ? fail("No pudimos cargar el reporte de la sesión.") : r;
    },
    async getMovements(c: ValidatedProfileContext, id: string) {
      if (!allow(c, ["CAJA", "ADMINISTRADOR"])) return fail("No autorizado.");
      const r = await rpc<Record<string, unknown>[]>(
        "rpc_obtener_movimientos_sesion_caja",
        { p_sesion_caja_id: id },
      );
      return r.ok
        ? { ok: true as const, data: (r.data ?? []).map(cashMovement) }
        : r;
    },
    async getPendingOrders(c: ValidatedProfileContext) {
      if (!allow(c, ["CAJA"])) return fail("No autorizado.");
      const r = await rpc<PendingRow[]>("obtener_pedidos_pendientes_pago_caja");
      return r.ok
        ? { ok: true as const, data: groupCashierOrders(r.data ?? []) }
        : r;
    },
    async getPayments(c: ValidatedProfileContext, id: number) {
      if (!allow(c, ["CAJA"])) return fail("No autorizado.");
      const r = await rpc<Record<string, unknown>[]>(
        "rpc_obtener_cobros_pedido_caja",
        { p_pedido_id: id },
      );
      return r.ok
        ? { ok: true as const, data: (r.data ?? []).map(paymentHistory) }
        : r;
    },
    async getOrderDiscount(c: ValidatedProfileContext, id: number) {
      if (!allow(c, ["CAJA"])) return fail("No autorizado.");
      const r = await client
        .from("descuento_pedido")
        .select("id,pedido_id,tipo,valor_solicitado,motivo,estado")
        .eq("local_id", c.local.id)
        .eq("pedido_id", id)
        .maybeSingle();
      return r.error
        ? fail("No pudimos cargar el descuento.")
        : { ok: true as const, data: r.data as AdminDiscount | null };
    },
    async getSessionHistory(c: ValidatedProfileContext, cashboxId: string) {
      if (!allow(c, ["CAJA"])) return fail("No autorizado.");
      return rpc<Record<string, unknown>[]>(
        "rpc_obtener_historial_sesiones_caja",
        { p_caja_id: cashboxId, p_limite: 10, p_offset: 0 },
      );
    },
    registerMovement(
      c: ValidatedProfileContext,
      sid: string,
      type: "ENTRADA" | "SALIDA",
      amount: number,
      reason: string,
      key: string,
    ) {
      return allow(c, ["CAJA"])
        ? rpc("rpc_registrar_movimiento_caja", {
            p_sesion_caja_id: sid,
            p_tipo: type,
            p_importe: amount,
            p_motivo: reason,
            p_idempotency_key: key,
          })
        : Promise.resolve(fail("No autorizado."));
    },
    registerMovements(
      c: ValidatedProfileContext,
      sid: string,
      movements: readonly NewCashMovement[],
      key: string,
    ) {
      return allow(c, ["CAJA"])
        ? rpc<Record<string, unknown>[]>("registrar_movimientos_caja", {
            p_sesion_caja_id: sid,
            p_movimientos: movements.map((movement) => ({
              tipo: movement.type,
              importe: movement.amount,
              motivo: movement.reason,
            })),
            p_idempotency_key: key,
          }).then((r) => r.ok
            ? { ok: true as const, data: (r.data ?? []).map(cashMovement) }
            : r)
        : Promise.resolve(fail("No autorizado."));
    },
    closeSession(
      c: ValidatedProfileContext,
      sid: string,
      counted: number,
      reason: string | null,
      key: string,
    ) {
      return allow(c, ["CAJA"])
        ? rpc<Record<string, unknown>>("rpc_cerrar_sesion_caja", {
            p_sesion_caja_id: sid,
            p_efectivo_contado: counted,
            p_motivo_diferencia: reason,
            p_idempotency_key: key,
          }).then((r) => r.ok ? { ok: true as const, data: closeSnapshot(r.data) } : r)
        : Promise.resolve(fail("No autorizado."));
    },
    requestDiscount(
      c: ValidatedProfileContext,
      id: number,
      type: "IMPORTE" | "PORCENTAJE",
      value: number,
      reason: string,
      key: string,
    ) {
      return allow(c, ["CAJA"])
        ? rpc("rpc_solicitar_descuento_pedido", {
            p_pedido_id: id,
            p_importe: type === "IMPORTE" ? value : null,
            p_porcentaje: type === "PORCENTAJE" ? value : null,
            p_motivo: reason,
            p_idempotency_key: key,
          })
        : Promise.resolve(fail("No autorizado."));
    },
    async registerPayment(
      c: ValidatedProfileContext,
      id: number,
      sid: string,
      chargeType: "TOTAL" | "PARCIAL",
      paymentLines: readonly Omit<PaymentMediumLine, "paymentId" | "order">[],
      key: string,
    ): Promise<CashierResult<PersistedPayment>> {
      if (!allow(c, ["CAJA"]) || paymentLines.length === 0 || paymentLines.some((line) => !methods.has(line.method)))
        return fail("Pago inválido.");
      const r = await rpc<Record<string, unknown>[]>(
        "rpc_registrar_cobro_pedido",
        {
          p_pedido_id: id,
          p_sesion_caja_id: sid,
          p_tipo_cobro: chargeType,
          p_medios: paymentLines.map((line) => ({ medio: line.method, importe: line.amount, propina: line.tip })),
          p_idempotency_key: key,
        },
      );
      if (!r.ok) return r;
      const x = r.data?.[0];
      return x
        ? { ok: true, data: payment(x) }
        : fail("No pudimos confirmar el pago.");
    },
  };
}
export function createAdminCashService(client: Client) {
  return {
    async getOrders(c: ValidatedProfileContext) {
      if (!allow(c, ["ADMINISTRADOR"])) return fail("No autorizado.");
      const r = await client.rpc("rpc_obtener_pedidos_operacion_admin");
      return r.error
        ? fail("No pudimos cargar la operación.", r.error.code)
        : {
            ok: true as const,
            data: ((r.data ?? []) as Record<string, unknown>[]).map(adminOrder),
          };
    },
    async getDiscounts(c: ValidatedProfileContext) {
      if (!allow(c, ["ADMINISTRADOR"])) return fail("No autorizado.");
      const r = await client
        .from("descuento_pedido")
        .select("id,pedido_id,tipo,valor_solicitado,motivo,estado")
        .eq("local_id", c.local.id)
        .order("solicitado_en", { ascending: false });
      return r.error
        ? fail("No pudimos cargar descuentos.")
        : { ok: true as const, data: (r.data ?? []) as AdminDiscount[] };
    },
    async decideDiscount(
      c: ValidatedProfileContext,
      id: number,
      decision: "AUTORIZAR" | "RECHAZAR",
      reason: string | null,
      key: string,
    ) {
      if (!allow(c, ["ADMINISTRADOR"])) return fail("No autorizado.");
      const r = await client.rpc("rpc_decidir_descuento_pedido", {
        p_pedido_id: id,
        p_decision: decision,
        p_motivo_decision: reason,
        p_idempotency_key: key,
      });
      return r.error
        ? fail("No se pudo decidir.", r.error.code)
        : { ok: true as const, data: r.data };
    },
    async annul(
      c: ValidatedProfileContext,
      id: number,
      reason: string,
      key: string,
    ) {
      if (!allow(c, ["ADMINISTRADOR"])) return fail("No autorizado.");
      const r = await client.rpc("anular_pedido_supervisado", {
        p_pedido_id: id,
        p_motivo: reason,
        p_idempotency_key: key,
      });
      return r.error
        ? fail("No se pudo anular.", r.error.code)
        : { ok: true as const, data: r.data };
    },
  };
}
const session = (x: Record<string, unknown>): CashSession => ({
  id: String(x.id),
  caja_id: String(x.caja_id),
  abierta_por: String(x.abierta_por),
  abierta_en: String(x.abierta_en),
  monto_inicial: Number(x.monto_inicial),
  estado: x.estado as CashSession["estado"],
});
const summary = (x: Record<string, unknown>): SessionSummary => ({
  sesion_caja_id: String(x.sesion_caja_id),
  estado: String(x.estado),
  monto_inicial: Number(x.monto_inicial),
  efectivo_esperado: Number(x.efectivo_esperado),
  pago_efectivo: Number(x.pago_efectivo),
  propina_efectivo: Number(x.propina_efectivo),
  entradas: Number(x.entradas),
  salidas: Number(x.salidas),
});
const closeSnapshot = (x: Record<string, unknown>): CloseSnapshot => ({
  sesion_caja_id: String(x.sesion_caja_id),
  caja_id: String(x.caja_id), local_id: String(x.local_id), cerrado_por: String(x.cerrado_por),
  cerrado_en: String(x.cerrado_en), tipo_cierre: x.tipo_cierre as CloseSnapshot["tipo_cierre"],
  pago_efectivo: Number(x.pago_efectivo), propina_efectivo: Number(x.propina_efectivo),
  pago_yape: Number(x.pago_yape), propina_yape: Number(x.propina_yape),
  pago_plin: Number(x.pago_plin), propina_plin: Number(x.propina_plin),
  pago_tarjeta: Number(x.pago_tarjeta), propina_tarjeta: Number(x.propina_tarjeta),
  entradas: Number(x.entradas), salidas: Number(x.salidas), efectivo_esperado: Number(x.efectivo_esperado),
  efectivo_contado: Number(x.efectivo_contado), diferencia: Number(x.diferencia),
  motivo: x.motivo == null ? null : String(x.motivo),
});
const sessionReport = (x: Record<string, unknown>): SessionCashReport => ({
  sessionId: String(x.sesion_caja_id), cashboxCode: String(x.caja_codigo), cashboxName: String(x.caja_nombre),
  openedBy: String(x.abierta_por_nombre), closedBy: x.cerrada_por_nombre == null ? null : String(x.cerrada_por_nombre),
  openedAt: String(x.abierta_en), closedAt: x.cerrada_en == null ? null : String(x.cerrada_en),
  initialAmount: Number(x.monto_inicial),
  salesByMethod: { EFECTIVO: Number(x.venta_efectivo), YAPE: Number(x.venta_yape), PLIN: Number(x.venta_plin), TARJETA: Number(x.venta_tarjeta) },
  tipsByMethod: { EFECTIVO: Number(x.propina_efectivo), YAPE: Number(x.propina_yape), PLIN: Number(x.propina_plin), TARJETA: Number(x.propina_tarjeta) },
  entries: Number(x.entradas), exits: Number(x.salidas), expectedCash: Number(x.efectivo_esperado),
  countedCash: x.efectivo_contado == null ? null : Number(x.efectivo_contado),
  difference: x.diferencia == null ? null : Number(x.diferencia),
});
const cashMovement = (x: Record<string, unknown>): CashMovement => ({
  id: String(x.id),
  sessionId: String(x.sesion_caja_id),
  type: x.tipo as CashMovement["type"],
  amount: Number(x.importe),
  reason: String(x.motivo),
  actorId: String(x.actor_id),
  actorName: String(x.actor_nombre),
  createdAt: String(x.creado_en),
});
const payment = (x: Record<string, unknown>): PersistedPayment => ({
  chargeId: String(x.cobro_id),
  orderId: Number(x.pedido_id),
  orderStatus: x.pedido_estado as PersistedPayment["orderStatus"],
  tableId: String(x.mesa_id),
  tableStatus: x.mesa_estado as PersistedPayment["tableStatus"],
  amount: Number(x.total_aplicado),
  tip: Number(x.propina_total),
  lines: paymentLines(x.medios),
  paidAt: String(x.cobrado_en),
  subtotal: Number(x.subtotal),
  discount: Number(x.descuento),
  netTotal: Number(x.total_neto),
  paid: Number(x.ya_pagado),
  balance: Number(x.saldo_posterior),
});
const paymentHistory = (x: Record<string, unknown>): PaymentHistory => ({
  chargeId: String(x.cobro_id),
  chargeType: x.tipo_cobro as PaymentHistory["chargeType"],
  amount: Number(x.total_aplicado),
  tip: Number(x.propina_total),
  lines: paymentLines(x.medios),
  actorName: String(x.actor_nombre),
  paidAt: String(x.cobrado_en),
  subtotal: Number(x.subtotal),
  discount: Number(x.descuento),
  netTotal: Number(x.total_neto),
  paid: Number(x.total_neto) - Number(x.saldo_posterior),
  balance: Number(x.saldo_posterior),
});
const paymentLines = (value: unknown): PaymentMediumLine[] =>
  (Array.isArray(value) ? value : []).map((line) => {
    const x = line as Record<string, unknown>;
    return {
      paymentId: Number(x.pago_id),
      order: Number(x.orden),
      amount: Number(x.importe),
      tip: Number(x.propina),
      method: x.medio as PaymentMethodCode,
    };
  });
const adminOrder = (x: Record<string, unknown>): AdminOrder => ({
  orderId: Number(x.pedido_id),
  tableCode: String(x.mesa_codigo),
  tableName: String(x.mesa_nombre),
  orderStatus: String(x.pedido_estado),
  tableStatus: String(x.mesa_estado),
  hasPayments: Boolean(x.tiene_pagos),
  paymentCount: Number(x.cantidad_pagos),
  subtotal: Number(x.subtotal),
  discount: Number(x.descuento),
  netTotal: Number(x.total_neto),
  paid: Number(x.pagado_acumulado),
  balance: Number(x.saldo),
});
