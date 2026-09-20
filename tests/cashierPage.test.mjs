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
  assert.match(serviceSource, /rpc_obtener_cobros_pedido_caja/);
  assert.doesNotMatch(page, /selected\.subtotal\s*-/);
  assert.doesNotMatch(page, /selected\.netTotal\s*-/);
});
test("registra un cobro atómico con N medios, propinas e idempotencia", async () => {
  const calls = [];
  const client = {
    rpc: async (name, args) => {
      calls.push({ name, args });
      return {
        data: [
          {
            cobro_id: "c1",
            pedido_id: 10,
            pedido_estado: "ENTREGADO",
            mesa_id: "m1",
            mesa_estado: "PENDIENTE_PAGO",
            total_aplicado: "20",
            propina_total: "2",
            medios: [
              { pago_id: 7, orden: 1, medio: "TARJETA", importe: 10, propina: 2 },
              { pago_id: 8, orden: 2, medio: "TARJETA", importe: 10, propina: 0 },
            ],
            cobrado_en: "2026-01-01",
            subtotal: "100",
            descuento: "20",
            total_neto: "80",
            ya_pagado: "50",
            saldo_posterior: "30",
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
    "PARCIAL",
    [
      { method: "TARJETA", amount: 10, tip: 2 },
      { method: "TARJETA", amount: 10, tip: 0 },
    ],
    "key",
  );
  assert.equal(r.ok, true);
  assert.equal(r.data.balance, 30);
  assert.equal(r.data.lines.length, 2);
  assert.equal(calls[0].name, "rpc_registrar_cobro_pedido");
  assert.deepEqual(calls[0].args, {
    p_pedido_id: 10,
    p_sesion_caja_id: "s1",
    p_tipo_cobro: "PARCIAL",
    p_medios: [
      { medio: "TARJETA", importe: 10, propina: 2 },
      { medio: "TARJETA", importe: 10, propina: 0 },
    ],
    p_idempotency_key: "key",
  });
});
test("lee movimientos con actor y registra siempre mediante lote", async () => {
  const calls = [];
  const client = {
    rpc: async (name, args) => {
      calls.push({ name, args });
      return { data: [{ id: "m1", sesion_caja_id: "s1", tipo: "ENTRADA", importe: "15", motivo: "Cambio", actor_id: "u1", actor_nombre: "Caja", creado_en: "2026-09-19T10:00:00Z" }], error: null };
    },
    from() { throw Error("not used"); },
  };
  const service = createCashierService(client);
  const read = await service.getMovements(context, "s1");
  const saved = await service.registerMovements(context, "s1", [
    { type: "ENTRADA", amount: 15, reason: "Cambio" },
    { type: "SALIDA", amount: 3, reason: "Compra menor" },
  ], "batch-key");
  assert.equal(read.ok, true);
  assert.deepEqual(read.data[0], { id: "m1", sessionId: "s1", type: "ENTRADA", amount: 15, reason: "Cambio", actorId: "u1", actorName: "Caja", createdAt: "2026-09-19T10:00:00Z" });
  assert.equal(saved.ok, true);
  assert.deepEqual(calls, [
    { name: "rpc_obtener_movimientos_sesion_caja", args: { p_sesion_caja_id: "s1" } },
    { name: "registrar_movimientos_caja", args: { p_sesion_caja_id: "s1", p_movimientos: [{ tipo: "ENTRADA", importe: 15, motivo: "Cambio" }, { tipo: "SALIDA", importe: 3, motivo: "Compra menor" }], p_idempotency_key: "batch-key" } },
  ]);
});
test("TP35, TP45-47 y TP59-60 están representados", () => {
  for (const text of [
    "Estado de caja",
    "Abrir o recuperar sesión",
    "No hay una caja activa configurada para este local.",
    "Hay varias cajas activas configuradas.",
    "Cargando caja…",
    "Reintentar",
    "Subtotal",
    "Descuento",
    "Total neto",
    "Pagado",
    "Saldo",
    "Dividir por productos",
    "Propina",
    "EFECTIVO",
    "YAPE",
    "TARJETA",
  ])
    assert.match(page, new RegExp(text));
  assert.match(page, /pending\.current/);
  assert.match(page, /disabled=\{busy/);
  assert.match(page, /await refresh\(\)/);
  assert.match(serviceSource, /registerMovements|registrar_movimientos_caja/i);
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
  assert.doesNotMatch(admin, /registerPayment|rpc_registrar_cobro_pedido/);
  assert.match(serviceSource, /rpc_obtener_pedidos_operacion_admin/);
  assert.match(serviceSource, /rpc_decidir_descuento_pedido/);
  assert.match(serviceSource, /anular_pedido_supervisado/);
});

test("TP62 UX separa estado, pedido, cobro y pagos con controles visibles", () => {
  for (const text of [
    "Estado de caja",
    "Pedidos pendientes",
    "Detalle del pedido",
    "Productos del pedido",
    "Cobro",
    "cobro realizado",
  ]) assert.match(page, new RegExp(text));
  assert.doesNotMatch(page, /Paso [1-4]/i);

  assert.match(page, /const fieldClass =/);
  assert.match(page, /border border-stone-300/);
  assert.match(page, /focus:ring-4/);
  assert.match(page, /primaryButtonClass\s*=/);
  assert.match(page, /bg-emerald-700/);
  assert.match(page, /className=\{selectClass\}/);
  assert.match(page, /lg:grid-cols-\[22rem_minmax\(0,1fr\)\]/);
  assert.doesNotMatch(page, /min-w-screen|w-screen/);
});

test("TP62 permite ocultar y mostrar la lista de pedidos sin perder el detalle", () => {
  assert.match(page, /\[ordersPanelOpen, setOrdersPanelOpen\] = useState\(true\)/);
  assert.match(page, /aria-expanded=\{ordersPanelOpen\}/);
  assert.match(page, /aria-label=\{ordersPanelOpen \? "Ocultar lista de pedidos pendientes" : "Mostrar lista de pedidos pendientes"\}/);
  assert.match(page, /Ocultar lista de pedidos pendientes/);
  assert.match(page, /Mostrar lista de pedidos pendientes/);
  assert.match(page, /ordersPanelOpen \? "lg:grid-cols-\[22rem_minmax\(0,1fr\)\]" : "grid-cols-\[3\.5rem_minmax\(0,1fr\)\]"/);
  assert.match(page, /ordersPanelOpen \? "p-4" : "p-1\.5"/);
  assert.match(page, /ordersPanelOpen && <h2[^>]*>Pedidos pendientes<\/h2>/);
  assert.match(page, /<svg aria-hidden="true"/);
  assert.match(page, /!ordersPanelOpen && <div[^>]*overflow-x-hidden overflow-y-auto/);
  assert.match(page, /\{order\.tableCode\}/);
  assert.match(page, /selectedId === order\.orderId \? "border-emerald-700 bg-emerald-700 text-white/);
  assert.match(page, /title=\{`\$\{order\.tableName\} · Pedido #\$\{order\.orderId\} · Saldo \$\{money\.format\(order\.balance\)\}`\}/);
  assert.match(page, /aria-label=\{`Abrir \$\{order\.tableName\}, pedido \$\{order\.orderId\}, saldo \$\{money\.format\(order\.balance\)\}`\}/);
});

test("TP62 usa automáticamente la única caja activa y no muestra selector ni cajero duplicado", () => {
  assert.match(page, /boxes\.data\.length === 1 \? boxes\.data\[0\]\.id : ""/);
  assert.match(page, /cashboxes\.length > 1/);
  assert.match(page, /varias cajas activas configuradas/);
  assert.match(page, /\{cashboxes\[0\]\.codigo\} · \{cashboxes\[0\]\.nombre\}/);
  assert.doesNotMatch(page, />Caja física</);
  assert.doesNotMatch(page, />Cajero</);
  assert.doesNotMatch(page, /setCashboxId\(e\.target\.value\)/);
});

test("TP62 UX prioriza saldo completo, N medios y revela excepciones bajo demanda", () => {
  assert.match(page, /paymentToApply = partialMode \? partialAmount : \(selected\?\.balance \?\? 0\)/);
  assert.match(page, /`Cobrar \$\{money\.format\(totalToReceive\)\}`/);
  assert.match(page, /partialMode && <label[^>]*>Importe a cobrar/);
  assert.match(page, /Cobrar una parte/);
  assert.match(page, /paymentLines\.map/);
  assert.match(page, /tipMode && <label[^>]*>Propina de este medio/);
  assert.match(page, /moreOptions && <div/);
  assert.match(page, /selectable=\{divideMode\}/);
  assert.match(page, /suggested > selected\.balance/);
  assert.match(page, /disabled=\{suggested <= 0 \|\| suggested > selected\.balance\}/);
  assert.match(page, /discountMode && <form/);
  assert.match(page, /paymentsOpen && \(/);
});

test("TP62 compacta saldo y controles por fila sin permitir eliminar la primera", () => {
  assert.match(page, />Cobro<\/h3>[\s\S]*Saldo: <b/);
  assert.doesNotMatch(page, /Saldo objetivo/);
  assert.match(page, /aria-label=\{`Agregar medio después de la línea \$\{index \+ 1\}`\}/);
  assert.match(page, /index > 0 && <button aria-label=\{`Quitar medio/);
  assert.match(page, /rounded-full bg-emerald-700/);
  assert.match(page, /rounded-full bg-rose-700/);
  assert.doesNotMatch(page, />Agregar medio de pago<\/button>/);
  assert.doesNotMatch(page, /Preparar cobro/);
});

test("TP62 prioriza cobro e historial, compacta el resumen y colapsa productos", () => {
  const panel = page.slice(page.indexOf("Detalle del pedido #"));
  const header = panel.indexOf("Detalle del pedido #");
  const summary = panel.indexOf("Subtotal <b");
  const charge = panel.indexOf(">Cobro</h3>");
  const products = panel.indexOf("Productos del pedido ({selected.lines.length})");
  const history = panel.indexOf("cobro realizado");

  assert.ok(header < summary && summary < charge && charge < history && history < products);
  assert.match(panel, /flex flex-wrap items-center gap-x-5[\s\S]*Subtotal <b[\s\S]*Descuento <b[\s\S]*Total neto <b[\s\S]*Pagado <b/);
  assert.doesNotMatch(panel.slice(summary, charge), /SALDO/);
  assert.doesNotMatch(panel, /grid grid-cols-2 gap-3 sm:grid-cols-3 xl:grid-cols-5/);
  assert.match(page, /\[productsOpen, setProductsOpen\] = useState\(false\)/);
  assert.match(page, /\{productsOpen \? "Ocultar detalle" : "Ver detalle"\}/);
  assert.match(page, /productsOpen && <div/);
  assert.match(page, /setProductsOpen\(true\); setDivideMode\(true\)/);
  assert.doesNotMatch(page, /Selecciona productos sólo para calcular un importe sugerido/);
  assert.match(page, /grow text-base text-stone-700/);
});

test("TP62 presenta el historial como una tabla compacta por acto de cobro", () => {
  assert.match(page, /chronologicalPayments = \[\.\.\.payments\]\.sort/);
  assert.match(page, /<table className="w-full table-fixed/);
  for (const heading of ["Hora", "Medio\\(s\\)", "Importe", "Propina", "Saldo"])
    assert.match(page, new RegExp(`>${heading}<`));
  assert.match(page, /chronologicalPayments\.map\(\(payment\) =>/);
  assert.match(page, /payment\.lines\.map\(\(line, index\) =>/);
  assert.match(page, /index > 0 && " \+ "/);
  assert.match(page, /toLocaleTimeString\("es-PE", \{ hour: "2-digit", minute: "2-digit", hour12: false \}\)/);
  assert.match(page, /<col className="w-\[12%\]" \/>[\s\S]*<col className="w-\[34%\]" \/>[\s\S]*<col className="w-\[18%\]" \/>/);
  assert.match(page, /max-h-72 overflow-y-auto/);
  assert.match(page, /paymentsOpen \? "Ocultar pagos" : "Ver pagos"/);
  assert.doesNotMatch(page, /Cobro \{x\.chargeId\.slice/);
  assert.doesNotMatch(page, /Registrado por \{x\.actorName\}/);
  assert.doesNotMatch(page, />\{x\.chargeType\}<\/span>/);
});

test("TP62 integra las acciones auxiliares dentro de Cobro y las alinea a la derecha", () => {
  const paymentForm = page.match(/<form\s+className="mt-5 rounded-xl border-2[\s\S]*?<\/form>/)?.[0] ?? "";
  assert.match(paymentForm, /md:flex-nowrap/);
  assert.match(paymentForm, /min-w-0 flex-wrap gap-1\.5 md:ml-auto md:flex-nowrap md:justify-end/);
  assert.match(page, /compactPrimaryButtonClass/);
  assert.match(page, /compactAuxiliaryButtonClass/);
  assert.match(paymentForm, /Precuenta[\s\S]*Cobrar una parte[\s\S]*Propina[\s\S]*Más opciones/);
  assert.doesNotMatch(paymentForm, /overflow-x-(?:auto|scroll)/);
  assert.match(page, /compactAuxiliaryButtonClass =\s*"min-h-11[^"]*text-sm/);
  assert.match(page, /className=\{compactAuxiliaryButtonClass\} type="button" onClick=\{\(\) => setPaymentsOpen/);
  assert.match(page, /\{paymentsOpen \? "Ocultar pagos" : "Ver pagos"\}<\/button>/);
  assert.match(page, /className=\{compactAuxiliaryButtonClass\}[\s\S]*\{productsOpen \? "Ocultar detalle" : "Ver detalle"\}/);
});

test("TP62 usa el mismo lenguaje operativo en cobro total y parcial", () => {
  const paymentForm = page.match(/<form\s+className="mt-5 rounded-xl border-2[\s\S]*?<\/form>/)?.[0] ?? "";
  assert.match(paymentForm, /Saldo: <b[^>]*>\{money\.format\(selected\.balance\)\}/);
  assert.match(paymentForm, /Importe a cobrar[\s\S]*\(menor a \{money\.format\(selected\.balance\)\}\)/);
  assert.match(paymentForm, /Saldo pendiente[\s\S]*money\.format\(selected\.balance\)/);
  assert.match(paymentForm, /A cobrar[\s\S]*partialMode && !hasPartialObjective \? "—" : money\.format\(paymentToApply\)/);
  assert.match(paymentForm, /Distribuido[\s\S]*money\.format\(preparedTotal\)/);
  assert.match(paymentForm, /difference >= 0 \? "Falta" : "Exceso"/);
  assert.match(paymentForm, /partialMode && !hasPartialObjective \? "—" : money\.format\(Math\.abs\(difference\)\)/);
  assert.match(paymentForm, /\{partialMode \? "Cobro total" : "Cobrar una parte"\}/);
  assert.doesNotMatch(paymentForm, /Objetivo parcial|Total preparado|Importe de esta parte/);
});

test("TP62 alinea la mesa a la derecha del encabezado del pedido", () => {
  assert.match(page, /flex flex-wrap items-baseline justify-between[\s\S]*<h2 className="text-xl font-bold">Detalle del pedido #\{selected\.orderId\}<\/h2>[\s\S]*bg-emerald-100[\s\S]*\{selected\.tableName\}/);
  assert.doesNotMatch(page, /Mesa \{selected\.tableCode\} · \{selected\.tableName\}/);
});

test("TP62 UX previene importes inválidos y limpia estado transitorio", () => {
  assert.match(page, /partialAmount <= 0 \|\| partialAmount >= \(selected\?\.balance \?\? 0\)/);
  assert.match(page, /partialMode && invalidPartial/);
  for (const reset of [
    "setPartialMode(false)",
    'setPaymentAmount("")',
    "setTipMode(false)",
    'setPaymentLines([{ method: "EFECTIVO", amount: "", tip: "0" }])',
    "setDivideMode(false)",
    "setProductsOpen(false)",
    "setSelectedLines(new Set())",
    "setDiscountMode(false)",
  ]) assert.match(page, new RegExp(reset.replace(/[()[\]]/g, "\\$&")));
  assert.match(page, /clearPaymentOptions\(\);[\s\S]*setSelectedId/);
  assert.match(page, /clearPaymentOptions\(\);[\s\S]*setLoading\(false\)/);
  assert.match(page, /\[movementDrafts, setMovementDrafts\]/);
  assert.match(page, /\[closeReason, setCloseReason\]/);
  assert.match(page, /\[discountReason, setDiscountReason\]/);
});

test("TP62 presenta movimientos históricos bloqueados y altas batch en una sola grilla", () => {
  for (const heading of ["Hora", "Tipo", "Importe", "Motivo", "Registrado por"])
    assert.match(page, new RegExp(`>${heading}<`));
  assert.match(page, /movements\.map\(\(item, index\) => <tr className="bg-stone-100 text-stone-700"/);
  assert.match(page, /index === movements\.length - 1 && movementDrafts\.length === 0/);
  assert.match(page, /aria-label="Agregar primer movimiento"/);
  assert.match(page, /movementDrafts\.map\(\(draft\) => <tr className="bg-white"/);
  assert.match(page, /aria-label="Agregar otra fila de movimiento"/);
  assert.match(page, /aria-label="Eliminar fila de movimiento"/);
  assert.match(page, /context\.profile\.nombre/);
  assert.match(page, />Guardar<\/button>[\s\S]*>Cancelar<\/button>/);
  assert.match(page, /service\.registerMovements\([\s\S]*movementDrafts\.map/);
  assert.match(page, /setMovementDrafts\(\[\]\)[\s\S]*setMovementNotice\("Movimientos registrados correctamente"\)/);
  assert.match(page, /getSummary\(context, s\.data\.id\)[\s\S]*getMovements\(context, s\.data\.id\)/);
  assert.match(page, /min-w-\[42rem\] table-fixed/);
  assert.doesNotMatch(page, /<th[^>]*>Acción<\/th>/);
});

test("TP62 UX no repite cajero ni expone el UUID de quien abrió", () => {
  assert.doesNotMatch(page, /openedByName/);
  assert.doesNotMatch(page, /Otro cajero autorizado/);
  assert.doesNotMatch(page, /<b[^>]*>\{session\.abierta_por\}<\/b>/);
});

test("TP62 cobro prepara una confirmación y no invoca la RPC desde el formulario", () => {
  const paymentForm = page.match(/<form\s+className="mt-5 rounded-xl border-2[\s\S]*?<\/form>/)?.[0] ?? "";
  assert.match(paymentForm, /setPaymentConfirmation\(confirmation\)/);
  assert.match(paymentForm, /paymentConfirmationRef\.current = confirmation/);
  assert.doesNotMatch(paymentForm, /service\.registerPayment/);
  assert.match(page, /Confirmación requerida/);
  assert.match(page, /Confirmar cobro/);
});

test("TP62 modal resume el cobro total, parcial y sus medios antes de registrar", () => {
  for (const text of ["Mesa", "Pedido", "Importe del pedido", "Medios de pago", "Propina", "Total a recibir", "Saldo actual", "Volver"])
    assert.match(page, new RegExp(`>${text}<`));
  assert.match(page, /Este cobro completará el pedido y liberará la mesa\./);
  assert.match(page, /Después del pago quedará un saldo de/);
  assert.match(page, /`Confirmar cobro \$\{money\.format\(paymentConfirmation\.totalToReceive\)\}`/);
});

test("TP62 separa venta, propina y total físico a recibir", () => {
  assert.match(page, /saleAmount = preparedTotal/);
  assert.match(page, /totalTip = preparedTip/);
  assert.match(page, /totalToReceive = saleAmount \+ totalTip/);
  assert.match(page, /Importe del pedido[\s\S]*money\.format\(saleAmount\)[\s\S]*Propina[\s\S]*money\.format\(totalTip\)[\s\S]*TOTAL A RECIBIR[\s\S]*money\.format\(totalToReceive\)/);
  assert.match(page, /amount: saleAmount,[\s\S]*tip: totalTip,[\s\S]*totalToReceive/);
  assert.match(page, /difference = paymentToApply - preparedTotal/);
  assert.match(page, /currentBalance - paymentConfirmation\.amount/);
  assert.match(page, /confirmation\.lines\.map\(\(\{ method, amount, tip \}\) => \(\{ method, amount, tip \}\)\)/);
  assert.doesNotMatch(page, /currentBalance - paymentConfirmation\.totalToReceive/);
});

test("TP62 confirmar registra una sola vez y Volver no registra", () => {
  assert.match(page, /if \(pending\.current\) return;/);
  assert.match(page, /disabled=\{busy\}[\s\S]*onClick=\{closePaymentConfirmation\}[\s\S]*>Volver<\/button>/);
  assert.match(page, /disabled=\{busy\}[\s\S]*service\.registerPayment\([\s\S]*confirmation\.orderId/);
  assert.match(page, /confirmation\.lines\.map/);
  assert.match(page, /r\.data\.balance === 0[\s\S]*service\.getPayments\(context, confirmation\.orderId\)/);
  assert.match(page, /historySnapshot = history\?\.ok \? history\.data : payments/);
  assert.match(page, /setDocumentPaymentHistory\(historySnapshot\)[\s\S]*setDocumentMode\("PAYMENT"\)[\s\S]*closePaymentConfirmation\(\)/);
  assert.match(page, /payments=\{documentPaymentHistory\}/);
  assert.match(page, /busy \? "Registrando cobro…"/);
});

test("TP62 resync invalida una confirmación obsoleta", () => {
  assert.match(page, /if \(paymentConfirmationRef\.current\)/);
  assert.match(page, /El saldo o el pedido cambió\. Revisa los datos antes de confirmar nuevamente\./);
  assert.match(page, /selected\.balance !== confirmation\.currentBalance/);
  assert.match(page, /El saldo cambió\. Actualiza y revisa el cobro antes de confirmar nuevamente\./);
  assert.match(page, /void refresh\(false\)/);
});
