import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";
import {
  createCashierService,
  groupCashierOrders,
} from "../src/services/cashierService.ts";
import { resolveApplicationRoute } from "../src/services/appRoutes.ts";
const page = readFileSync(
    new URL("../src/pages/CashierPage.tsx", import.meta.url),
    "utf8",
  ),
  admin = readFileSync(
    new URL("../src/components/CashAdministrationPanel.tsx", import.meta.url),
    "utf8",
  ),
  serviceSource = readFileSync(
    new URL("../src/services/cashierService.ts", import.meta.url),
    "utf8",
  );
const context = {
  profile: {
    id: "u1",
    local_id: "l1",
    rol_id: 4,
    nombre: "Caja",
    activo: true,
  },
  role: { id: 4, codigo: "CAJA", activo: true },
  local: { id: "l1", nombre: "Local", activo: true },
};
const row = (x = {}) => ({
  pedido_id: 10,
  pedido_estado: "ENTREGADO",
  pedido_creado_en: "2026-01-01",
  mesa_id: "m1",
  mesa_codigo: "M1",
  mesa_nombre: "Mesa",
  mesa_estado: "PENDIENTE_PAGO",
  detalle_id: 1,
  producto_id: "p1",
  producto_nombre: "Ceviche",
  cantidad: 1,
  precio_unitario: "100",
  importe_linea: "100",
  total_pedido: "100",
  subtotal: "100",
  descuento: "20",
  total_neto: "80",
  pagado_acumulado: "30",
  saldo: "50",
  ...x,
});
test("mantiene /caja exclusiva de CAJA", () => {
  assert.deepEqual(
    resolveApplicationRoute({
      pathname: "/caja",
      authenticationStatus: "authenticated",
      contextStatus: "valid",
      role: "CAJA",
    }),
    { status: "allowed", pathname: "/caja" },
  );
  assert.equal(
    resolveApplicationRoute({
      pathname: "/caja",
      authenticationStatus: "authenticated",
      contextStatus: "valid",
      role: "ADMINISTRADOR",
    }).status,
    "redirect",
  );
});
test("consume importes autoritativos sin reconstruir neto o saldo", () => {
  const [o] = groupCashierOrders([row()]);
  assert.deepEqual(
    [o.subtotal, o.discount, o.netTotal, o.paid, o.balance],
    [100, 20, 80, 30, 50],
  );
  assert.match(serviceSource, /obtener_pedidos_pendientes_pago_caja/);
  assert.match(serviceSource, /rpc_obtener_pagos_pedido_caja/);
  assert.doesNotMatch(page, /selected\.subtotal\s*-/);
  assert.doesNotMatch(page, /selected\.netTotal\s*-/);
});
test("registra pago v2 con sesión importe medio propina e idempotencia", async () => {
  const calls = [];
  const client = {
    rpc: async (name, args) => {
      calls.push({ name, args });
      return {
        data: [
          {
            pago_id: 7,
            pedido_id: 10,
            pedido_estado: "ENTREGADO",
            mesa_id: "m1",
            mesa_estado: "PENDIENTE_PAGO",
            importe: "20",
            propina: "2",
            medio: "TARJETA",
            sesion_caja_id: "s1",
            pagado_en: "2026-01-01",
            subtotal: "100",
            descuento: "20",
            total_neto: "80",
            ya_pagado: "50",
            saldo: "30",
          },
        ],
        error: null,
      };
    },
    from() {
      throw Error("not used");
    },
  };
  const r = await createCashierService(client).registerPayment(
    context,
    10,
    "s1",
    20,
    "TARJETA",
    2,
    "key",
  );
  assert.equal(r.ok, true);
  assert.equal(r.data.balance, 30);
  assert.equal(calls[0].name, "rpc_registrar_pago_pedido_v2");
  assert.deepEqual(calls[0].args, {
    p_pedido_id: 10,
    p_sesion_caja_id: "s1",
    p_importe_aplicar: 20,
    p_medio: "TARJETA",
    p_propina: 2,
    p_idempotency_key: "key",
  });
});
test("TP35, TP45-47 y TP59-60 están representados", () => {
  for (const text of [
    "Caja física",
    "Abrir o recuperar sesión",
    "No hay caja física disponible.",
    "Cargando caja…",
    "Reintentar",
    "Subtotal",
    "Descuento",
    "Total neto",
    "Pagado",
    "Saldo",
    "Dividir por productos",
    "Agregar propina",
    "EFECTIVO",
    "YAPE",
    "TARJETA",
  ])
    assert.match(page, new RegExp(text));
  assert.match(page, /pending\.current/);
  assert.match(page, /disabled=\{busy/);
  assert.match(page, /await refresh\(\)/);
  assert.match(page, /rpc_registrar_movimiento_caja|registerMovement/);
  assert.match(page, /rpc_cerrar_sesion_caja|closeSession/);
});
test("administración queda en shell admin sin capacidad de cobro", () => {
  for (const text of [
    "Operación financiera administrativa",
    "Solicitudes de descuento",
    "Autorizar",
    "Rechazar",
    "Anular pedido",
    "Advertencia",
    "No elegible",
  ])
    assert.match(admin, new RegExp(text));
  assert.doesNotMatch(admin, /registerPayment|rpc_registrar_pago_pedido_v2/);
  assert.match(serviceSource, /rpc_obtener_pedidos_operacion_admin/);
  assert.match(serviceSource, /rpc_decidir_descuento_pedido/);
  assert.match(serviceSource, /anular_pedido_supervisado/);
});

test("TP62 UX separa estado, pedido, cobro y pagos con controles visibles", () => {
  for (const text of [
    "Paso 1",
    "Paso 2",
    "Paso 3",
    "Paso 4",
    "Estado de caja",
    "Pedidos pendientes",
    "Detalle del pedido",
    "Productos del pedido",
    "Cobro",
    "pago realizado",
    "Medio de pago",
  ]) assert.match(page, new RegExp(text));

  assert.match(page, /const fieldClass =/);
  assert.match(page, /border border-stone-300/);
  assert.match(page, /focus:ring-4/);
  assert.match(page, /primaryButtonClass\s*=/);
  assert.match(page, /bg-emerald-700/);
  assert.match(page, /className=\{selectClass\}/);
  assert.match(page, /lg:grid-cols-\[22rem_minmax\(0,1fr\)\]/);
  assert.doesNotMatch(page, /overflow-x-(?:auto|scroll)/);
});

test("TP62 UX prioriza saldo completo y revela excepciones bajo demanda", () => {
  assert.match(page, /paymentToApply = partialMode \? partialAmount : \(selected\?\.balance \?\? 0\)/);
  assert.match(page, /`Cobrar \$\{money\.format\(selected\.balance\)\}`/);
  assert.match(page, /partialMode && <label[^>]*>Importe de esta parte/);
  assert.match(page, /Cobrar una parte/);
  assert.match(page, /tipMode && <label[^>]*>Propina/);
  assert.match(page, /moreOptions && <div/);
  assert.match(page, /selectable=\{divideMode\}/);
  assert.match(page, /suggested > selected\.balance/);
  assert.match(page, /disabled=\{suggested <= 0 \|\| suggested > selected\.balance\}/);
  assert.match(page, /discountMode && <form/);
  assert.match(page, /paymentsOpen && \(/);
});

test("TP62 UX previene importes inválidos y limpia estado transitorio", () => {
  assert.match(page, /partialAmount <= 0 \|\| partialAmount > \(selected\?\.balance \?\? 0\)/);
  assert.match(page, /partialMode && invalidPartial/);
  for (const reset of [
    "setPartialMode(false)",
    'setPaymentAmount("")',
    "setTipMode(false)",
    'setTip("0")',
    "setDivideMode(false)",
    "setSelectedLines(new Set())",
    "setDiscountMode(false)",
  ]) assert.match(page, new RegExp(reset.replace(/[()[\]]/g, "\\$&")));
  assert.match(page, /clearPaymentOptions\(\);[\s\S]*setSelectedId/);
  assert.match(page, /clearPaymentOptions\(\);[\s\S]*setLoading\(false\)/);
  assert.match(page, /\[movementReason, setMovementReason\]/);
  assert.match(page, /\[closeReason, setCloseReason\]/);
  assert.match(page, /\[discountReason, setDiscountReason\]/);
});

test("TP62 UX muestra nombre local y nunca expone el UUID del cajero", () => {
  assert.match(page, /session\?\.abierta_por === context\.profile\.id/);
  assert.match(page, /context\.profile\.nombre/);
  assert.match(page, /Otro cajero autorizado/);
  assert.doesNotMatch(page, /<b[^>]*>\{session\.abierta_por\}<\/b>/);
});
