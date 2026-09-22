import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";
import { createAdminCashService } from "../src/services/cashierService.ts";

const page = readFileSync(new URL("../src/pages/AdminOrdersPage.tsx", import.meta.url), "utf8");
const service = readFileSync(new URL("../src/services/cashierService.ts", import.meta.url), "utf8");
const migration = readFileSync(new URL("../supabase/migrations/20260921000400_e1_t17_pedidos_admin_ultima_actualizacion.sql", import.meta.url), "utf8");
const context = {
  profile: { id: "a1", local_id: "l1", rol_id: 1, nombre: "Admin", activo: true },
  role: { id: 1, codigo: "ADMINISTRADOR", activo: true },
  local: { id: "l1", nombre: "Local", activo: true },
};

test("E1-TP63: reutiliza los contratos autoritativos existentes", () => {
  assert.match(service, /client\.rpc\("rpc_obtener_pedidos_operacion_admin"\)/);
  assert.match(service, /client\.rpc\("anular_pedido_supervisado"/);
  assert.match(service, /p_pedido_id: id/);
  assert.match(service, /p_motivo: reason/);
  assert.match(service, /p_idempotency_key: key/);
  assert.match(page, /createAdminCashService/);
});

test("E1-TP63: una solicitud usa una clave estable y bloquea doble envío", () => {
  assert.match(page, /idempotencyKey\.current = crypto\.randomUUID\(\)/);
  assert.match(page, /if \(!service \|\| !selected \|\| !reason\.trim\(\) \|\| requestLock\.current\) return/);
  assert.match(page, /requestLock\.current = true/);
  assert.match(page, /disabled=\{busy \|\| !reason\.trim\(\)\}/);
  assert.equal((page.match(/service\.annul\(/g) ?? []).length, 1);
});

test("E1-TP63: pago o estado terminal bloquean la acción", () => {
  assert.match(page, /if \(order\.hasPayments\) return "Bloqueado por pago"/);
  assert.match(page, /\["PAGADO", "ANULADO"\]\.includes\(order\.orderStatus\)/);
  assert.match(page, /eligible \? <button[\s\S]*?>Anular<\/button> : <span/);
});

test("E1-TP59/63: filtra anulables por defecto y permite consultar todos", () => {
  assert.match(page, /useState\(true\)/);
  assert.match(page, /cancellableOnly \? orders\.filter\(canCancel\) : orders/);
  assert.match(page, /Sólo anulables/);
  assert.match(page, /role="switch"/);
  assert.match(page, /peer-checked:bg-emerald-700/);
  assert.match(page, /visibleOrders\.length\} de \{orders\.length\} pedidos/);
  assert.match(page, /No hay pedidos anulables\. Desactiva el filtro para consultar todos/);
});

test("E1-TP59/63: Cuenta agrupa total y saldo autoritativos en una sola celda", () => {
  assert.match(page, /<dt[^>]*>Total<\/dt><dd[^>]*>\{money\.format\(order\.netTotal\)\}<\/dd>/);
  assert.match(page, /<dt[^>]*>Saldo<\/dt><dd[^>]*>\{money\.format\(order\.balance\)\}<\/dd>/);
  assert.doesNotMatch(page, /\['Mesa', 'Pedido', 'Estado', 'Total', 'Saldo'/);
});

test("E1-TP59/63: permite ordenar sin controles ambiguos por columna", () => {
  assert.match(page, /useState<OrderSort>\("UPDATED_DESC"\)/);
  for (const label of ["Última actualización: reciente primero", "Última actualización: antigua primero", "Mesa", "Estado", "Saldo: mayor primero", "Saldo: menor primero"]) assert.match(page, new RegExp(label));
  assert.match(page, /case "TABLE"/);
  assert.match(page, /case "STATUS"/);
  assert.match(page, /case "BALANCE_DESC"/);
  assert.match(page, /default: return Date\.parse\(right\.updatedAt\) - Date\.parse\(left\.updatedAt\)/);
  assert.doesNotMatch(page, /aria-sort/);
});

test("E1-TP59/63: muestra fecha y hora sin segundos y conserva orden autoritativo", async () => {
  const client = {
    rpc: async () => ({ data: [{ pedido_id: 21, mesa_id: "m1", mesa_codigo: "M01", mesa_nombre: "Mesa 1", pedido_estado: "ENVIADO", mesa_estado: "OCUPADA", creado_en: "2026-09-21T14:00:00Z", ultima_actualizacion_en: "2026-09-21T15:42:00Z", tiene_pagos: false, cantidad_pagos: 0, subtotal: 20, descuento: 0, total_neto: 20, pagado_acumulado: 0, saldo: 20 }], error: null }),
    from: () => { throw new Error("not used"); },
  };
  const result = await createAdminCashService(client).getOrders(context);
  assert.equal(result.ok, true);
  assert.equal(result.data[0].updatedAt, "2026-09-21T15:42:00Z");
  assert.match(page, /hour: "2-digit"/);
  assert.match(page, /minute: "2-digit"/);
  assert.doesNotMatch(page, /second:/);
  assert.match(migration, /order by ultima_actualizacion_en desc, pedido\.id desc/);
});

test("E1-TP61: ampliación de lectura mantiene autoridad, aislamiento y privilegio mínimo", () => {
  assert.match(migration, /from public\.obtener_contexto_autenticado\(\)/);
  assert.match(migration, /v_rol is distinct from 'ADMINISTRADOR'/);
  assert.match(migration, /where pedido\.local_id = v_local/);
  assert.match(migration, /greatest\([\s\S]*pedido\.modificado_en[\s\S]*historial\.ultima_transicion_en/);
  assert.match(migration, /security definer/);
  assert.match(migration, /set search_path = pg_catalog/);
  assert.match(migration, /revoke all[\s\S]*from public, anon, authenticated, service_role/);
  assert.match(migration, /grant execute[\s\S]*to authenticated/);
});
