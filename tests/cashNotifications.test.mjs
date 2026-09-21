import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { test } from "node:test";
import { createCashNotificationService } from "../src/services/cashNotificationService.ts";

const context = (role = "ADMINISTRADOR") => ({
  profile: { id: "admin-a", local_id: "local-a", rol_id: 1, nombre: "Admin A", activo: true },
  role: { id: 1, codigo: role, activo: true },
  local: { id: "local-a", nombre: "Local A", activo: true },
});

test("mapea contador, actor legible y alerta de cierre", async () => {
  const calls = [];
  const client = { rpc: async (name, args) => {
    calls.push([name, args]);
    return { error: null, data: { no_leidas: 1, notificaciones: [{
      id: "notification-1", tipo: "CIERRE", prioridad: "ALERTA", creado_en: "2026-09-21T01:00:00Z",
      leida_en: null, caja_codigo: "CAJA-01", caja_nombre: "Principal", actor_nombre: "Caja Uno",
      monto_inicial: null, efectivo_esperado: "100", efectivo_contado: "90", diferencia: "-10", motivo: "Faltante",
    }] } };
  } };
  const result = await createCashNotificationService(client).getNotifications(context());
  assert.equal(result.ok, true);
  assert.equal(result.data.unreadCount, 1);
  assert.deepEqual(result.data.notifications[0], {
    id: "notification-1", type: "CIERRE", priority: "ALERTA", createdAt: "2026-09-21T01:00:00Z",
    readAt: null, cashboxCode: "CAJA-01", cashboxName: "Principal", actorName: "Caja Uno",
    initialAmount: null, expectedCash: 100, countedCash: 90, difference: -10, reason: "Faltante",
  });
  assert.deepEqual(calls, [["rpc_obtener_notificaciones_caja", undefined]]);
});

test("marca la entrega propia mediante RPC y rechaza roles no administradores localmente", async () => {
  const calls = [];
  const client = { rpc: async (name, args) => {
    calls.push([name, args]);
    return { error: null, data: { id: "notification-1", leida_en: "2026-09-21T01:05:00Z" } };
  } };
  const service = createCashNotificationService(client);
  const marked = await service.markAsRead(context(), "notification-1");
  assert.equal(marked.ok, true);
  assert.deepEqual(calls, [["rpc_marcar_notificacion_caja_leida", { p_notificacion_id: "notification-1" }]]);
  assert.equal((await service.getNotifications(context("CAJA"))).ok, false);
  assert.equal((await service.markAsRead(context("MOZO"), "notification-1")).ok, false);
  assert.equal(calls.length, 1);
});

test("la campana ofrece estados informativo/alerta, contador y lectura; Caja avisa la diferencia", () => {
  const bell = readFileSync(new URL("../src/components/CashNotificationBell.tsx", import.meta.url), "utf8");
  const page = readFileSync(new URL("../src/pages/CashierPage.tsx", import.meta.url), "utf8");
  assert.match(bell, /Notificaciones de caja/);
  assert.match(bell, /no leídas/);
  assert.match(bell, /Marcar como leída/);
  assert.match(bell, /Cierre con diferencia/);
  assert.match(bell, /bg-amber-50/);
  assert.match(bell, /bg-sky-50/);
  assert.match(page, /Se registrará la diferencia y se notificará al administrador\./);
});

test("la UI administrativa incorpora la campana sin ampliar lecturas directas de perfiles", () => {
  const page = readFileSync(new URL("../src/pages/CategoryAdministrationPage.tsx", import.meta.url), "utf8");
  const service = readFileSync(new URL("../src/services/cashNotificationService.ts", import.meta.url), "utf8");
  assert.match(page, /<CashNotificationBell context=\{context\}/);
  assert.doesNotMatch(service, /\.from\(["']perfil_usuario["']\)/);
  assert.match(service, /rpc_obtener_notificaciones_caja/);
  assert.match(service, /rpc_marcar_notificacion_caja_leida/);
});
