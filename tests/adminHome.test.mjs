import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";

const home = readFileSync(new URL("../src/pages/AdminHomePage.tsx", import.meta.url), "utf8");
const shell = readFileSync(new URL("../src/components/AdminShell.tsx", import.meta.url), "utf8");
const app = readFileSync(new URL("../src/App.tsx", import.meta.url), "utf8");
const pending = readFileSync(new URL("../src/pages/AdminPendingPage.tsx", import.meta.url), "utf8");

test("E1-TP59: Inicio conserva KPI, vacíos, caja cerrada y medios en cero", () => {
  for (const label of ["Ventas netas", "Pedidos pagados", "Ticket promedio", "Descuentos autorizados", "Requiere tu atención", "Operación de caja", "Ventas por medio", "Todo en orden", "No existe una sesión activa."]) assert.match(home, new RegExp(label));
  for (const method of ["EFECTIVO", "YAPE", "PLIN", "TARJETA"]) assert.match(home, new RegExp(`\\"${method}\\"`));
  assert.match(home, /daily\.completedOrders > 0 \? daily\.totalSold \/ daily\.completedOrders : 0/);
  assert.match(home, /sales\.getDailyCashSummary\(context\)/);
  assert.match(home, /sales\.getSessionReports\(context\)/);
  assert.match(home, /sales\.getCurrentOrderFlow\(context\)/);
  assert.match(home, /amount \/ maxMethod \* 100/);
  assert.match(home, /rounded-full bg-emerald-700/);
  assert.match(home, /Flujo actual de pedidos/);
  assert.match(home, /POR_RECIBIR: "Pendiente de Cocina"/);
  assert.match(home, /EN_PREPARACION: "Trabajo en Cocina"/);
  assert.match(home, /LISTOS_PARA_ENTREGAR: "Pendiente de Mozo"/);
  assert.match(home, /Mayor espera/);
  assert.match(home, /Promedio/);
  assert.match(home, /Ver pedidos/);
  assert.match(home, /disabled=\{group\.count === 0\}/);
  assert.match(home, /group\.count > 0 && selectedFlow === group\.code/);
  assert.match(home, /attentionCount === 1 \? "p-3 sm:p-4" : "p-4 sm:p-5"/);
  assert.match(home, /role="table"/);
  assert.match(home, /setSelectedFlow\(null\)/);
  assert.doesNotMatch(home, /Actualizar estado|Recibir pedido|Marcar listo/);
  const sections = ["Indicadores de hoy", "Requiere tu atención", "Flujo actual de pedidos", "Ventas por medio", "Operación de caja"].map((label) => home.indexOf(label));
  assert.deepEqual(sections, [...sections].sort((left, right) => left - right));
  assert.match(home, /grid-cols-2[\s\S]*sm:grid-cols-\[1fr_1fr_2fr_1fr\]/);
});

test("E1-TP60: atención diferencia decisiones de descuentos y consulta de cierres", () => {
  assert.match(home, /item\.type === "CIERRE" && item\.priority === "ALERTA" && !item\.readAt/);
  assert.match(home, /item\.estado === "PENDIENTE"/);
  assert.match(home, />Ver cierre</);
  assert.match(home, />Revisar</);
  assert.match(pending, /Los cierres con diferencia se consultan desde Inicio o Caja y nunca requieren aprobación/);
  assert.match(pending, /discountsOnly/);
});

test("E1-TP60/64: navegación usa sidebar desktop y drawer accesible en anchos menores", () => {
  for (const label of ["Inicio", "OPERACIÓN", "Pendientes por aprobar", "REPORTES", "Caja", "Ventas", "CONFIGURACIÓN", "Carta", "Mesas", "Usuarios"]) assert.match(shell, new RegExp(label));
  assert.match(shell, /hidden[^"\n]*lg:block/);
  assert.match(shell, /lg:hidden/);
  assert.match(shell, /aria-label="Abrir menú de Administración"/);
  assert.match(shell, /aria-modal="true"/);
  assert.match(shell, /event\.key === "Escape"/);
  assert.match(shell, /overflow-x-hidden/);
  assert.match(shell, /sidebarCollapsed \? "lg:grid-cols-\[4\.5rem_minmax\(0,1fr\)\]"/);
  assert.match(shell, /"Mostrar menú lateral" : "Ocultar menú lateral"/);
  assert.match(shell, /navigation\(sidebarCollapsed\)/);
  assert.match(shell, /navigation\(\)/);
  assert.match(shell, /ml-3 border-l border-stone-200 pl-2/);
  assert.match(shell, /border-emerald-700 bg-emerald-100/);
  assert.match(app, /mode="cash"/);
  assert.match(app, /mode="sales"/);
});

test("E1-T16: Usuarios permanece visible pero deshabilitado al no existir contrato", () => {
  assert.match(shell, /Gestión de usuarios no disponible en T16/);
  assert.match(shell, /aria-disabled="true"/);
  assert.doesNotMatch(shell, /route: "\/admin\/usuarios"/);
});
