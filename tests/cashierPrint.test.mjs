import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";
const page = readFileSync(
    new URL("../src/pages/CashierPage.tsx", import.meta.url),
    "utf8",
  ),
  css = readFileSync(new URL("../src/index.css", import.meta.url), "utf8");
test("TP48 distingue recibo parcial y ticket consolidado", () => {
  assert.match(page, /payment\?\.balance\s*===\s*0/);
  assert.match(page, /preAccount \? "PRECUENTA" : complete \? "TICKET INTERNO" : "RECIBO INTERNO"/);
  assert.match(page, /No válido como comprobante fiscal/);
  for (const x of [
    "Subtotal",
    "Descuento",
    "TOTAL",
    "SALDO PENDIENTE",
    "Propina",
    "IMPORTE COBRADO",
  ])
    assert.match(page, new RegExp(x));
});
test("precuenta reutiliza el documento con snapshot vigente y sin mutaciones", () => {
  const paymentForm = page.match(/<form\s+className="mt-5 rounded-xl border-2[\s\S]*?<\/form>/)?.[0] ?? "";
  const preAccountButton = paymentForm.match(/<button[^>]*onClick=\{\(\) => \{ setDocumentOrder\(selected\);[\s\S]*?>Precuenta<\/button>/)?.[0] ?? "";
  assert.ok(preAccountButton);
  assert.match(preAccountButton, /setDocument\(null\)/);
  assert.match(preAccountButton, /setDocumentMode\("PRECUENTA"\)/);
  assert.doesNotMatch(preAccountButton, /service\.|registerPayment|rpc|run\(/);
  assert.match(page, /\(preAccount \|\| complete\) && <>[\s\S]*order\.lines\.map/);
  assert.match(page, /TOTAL A PAGAR/);
  assert.match(page, /money\.format\(preAccount \? order\.balance : netTotal\)/);
  assert.match(page, /preAccount && order\.paid > 0[\s\S]*Pagado/);
  assert.match(page, /!preAccount && payment && <>[\s\S]*Formas de pago/);
  assert.match(page, /setDocumentMode\(null\)/);
});
test("ticket final muestra consumo completo y medios repetidos sin identificadores técnicos visibles", () => {
  const documentComponent = page.slice(
    page.indexOf("function InternalDocument"),
    page.indexOf("export default function CashierPage"),
  );
  assert.match(page, /\(preAccount \|\| complete\) && <>[\s\S]*order\.lines\.map/);
  assert.match(page, /line\.quantity/);
  assert.match(page, /line\.productName/);
  assert.match(page, /money\.format\(line\.lineAmount\)/);
  assert.match(page, /displayedPayments\.flatMap\(\(item\) => item\.lines\)\.map/);
  assert.doesNotMatch(documentComponent, />\s*Cobro \{[^}]*chargeId/);
  assert.doesNotMatch(page, /pago_detalle|subcuenta|subpedido/);
});
test("usa identidad disponible con fallback MikuyApp y sede del contexto", () => {
  assert.match(page, />MikuyApp<\/h2>/);
  assert.match(page, /localName\.trim\(\)/);
  assert.match(page, /localName=\{context\.local\.nombre\}/);
  assert.doesNotMatch(page, /MikuyApp Demo/);
  assert.match(page, /Operado con MikuyApp/);
});
test("impresión térmica conserva overlay, permite contenido largo y oculta acciones", () => {
  assert.match(page, /print-overlay/);
  assert.match(page, /print-document flex max-h/);
  assert.match(page, /ticket-scroll overflow-y-auto/);
  assert.match(page, /window\.print/);
  assert.match(page, />\s*Cerrar\s*<\/button>/);
  assert.match(page, />\s*Imprimir\s*<\/button>/);
  assert.match(css, /@media print/);
  assert.match(css, /size: 80mm auto/);
  assert.match(css, /\.ticket-scroll/);
  assert.match(css, /\.no-print/);
});
