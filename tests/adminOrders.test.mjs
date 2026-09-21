import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";

const page = readFileSync(new URL("../src/pages/AdminOrdersPage.tsx", import.meta.url), "utf8");
const service = readFileSync(new URL("../src/services/cashierService.ts", import.meta.url), "utf8");

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
