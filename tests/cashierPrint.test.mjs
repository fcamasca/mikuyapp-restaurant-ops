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
  assert.match(page, /!preAccount && payment && !complete && <>[\s\S]*Este cobro/);
  assert.match(page, /setDocumentMode\(null\)/);
});
test("recibo parcial muestra resumen y exclusivamente el acto vigente", () => {
  assert.match(page, /paidPreviously = payment \? Math\.max\(0, payment\.paid - payment\.amount\) : order\.paid/);
  assert.match(page, /!preAccount && payment && !complete && <>/);
  for (const text of [
    "Resumen del pedido",
    "Total del pedido",
    "Pagado anteriormente",
    "Este cobro",
    "IMPORTE COBRADO",
    "SALDO PENDIENTE",
  ]) assert.match(page, new RegExp(text));
  assert.match(page, /payment\.lines\.map/);
  assert.match(page, /money\.format\(payment\.tip\)/);
  assert.match(page, /money\.format\(payment\.amount\)/);
  assert.match(page, /money\.format\(balance\)/);
  assert.doesNotMatch(page, /!preAccount && payment && !complete[\s\S]*order\.lines\.map/);
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
  assert.match(page, /!preAccount && payment && complete && <>/);
  assert.match(page, /documentPayments\.map/);
  assert.match(page, /new Date\(item\.paidAt\)\.toLocaleTimeString/);
  assert.match(page, /item\.lines\.map/);
  assert.match(page, /money\.format\(item\.tip\)/);
  assert.match(page, /ticket-payments-table mt-2 w-full table-fixed/);
  for (const heading of ["Hora", "Medio\\(s\\)", "Importe", "Propina"])
    assert.match(page, new RegExp(`>${heading}<`));
  assert.match(page, /lineIndex > 0 && " \+ "/);
  assert.match(page, /break-words px-1 py-2 align-top/);
  assert.doesNotMatch(documentComponent, /payment-summary rounded-lg/);
  assert.doesNotMatch(documentComponent, /ticket-payments-table[^]*?<th[^>]*>Total<\/th>/);
  assert.doesNotMatch(documentComponent, /ticket-payments-table[^]*?overflow-x-(?:auto|scroll)/);
  assert.match(page, /TOTAL PAGADO/);
  assert.match(page, /PROPINA TOTAL/);
  assert.match(page, /totalPaid = documentPayments\.reduce\(\(sum, item\) => sum \+ item\.amount, 0\)/);
  assert.match(page, /totalTips = documentPayments\.reduce\(\(sum, item\) => sum \+ item\.tip, 0\)/);
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
  assert.match(page, /print-document ticket-document flex max-h/);
  assert.match(page, /ticket-scroll overflow-y-auto/);
  assert.match(page, /window\.print/);
  assert.match(page, />\s*Cerrar\s*<\/button>/);
  assert.match(page, />\s*Imprimir\s*<\/button>/);
  assert.match(css, /@media print/);
  assert.match(css, /size: 80mm auto/);
  assert.match(css, /\.ticket-scroll/);
  assert.match(css, /\.no-print/);
});
test("impresión renderiza una sola copia y elimina el layout de aplicación", () => {
  assert.equal((page.match(/<InternalDocument/g) ?? []).length, 1);
  assert.equal((page.match(/className="print-document/g) ?? []).length, 2);
  assert.match(page, /\{closeReport && <CloseReportDocument/);
  assert.match(css, /#root > main > :not\(\.print-overlay\)[\s\S]*display: none !important/);
  assert.match(css, /\.print-overlay \{[\s\S]*position: static !important[\s\S]*overflow: visible !important/);
  assert.match(css, /\.print-document \{[\s\S]*position: static !important/);
  assert.doesNotMatch(css, /\.print-document \{[\s\S]*position: absolute/);
});
test("los tres documentos comparten una jerarquía tipográfica térmica compacta", () => {
  const documentComponent = page.slice(
    page.indexOf("function InternalDocument"),
    page.indexOf("export default function CashierPage"),
  );
  assert.match(documentComponent, /className="print-document ticket-document/);
  for (const className of [
    "ticket-brand",
    "ticket-type",
    "ticket-location",
    "ticket-disclaimer",
    "ticket-section-title",
    "ticket-amount",
    "ticket-total",
    "ticket-footer",
  ]) assert.match(documentComponent, new RegExp(className));
  assert.doesNotMatch(documentComponent, /text-(?:sm|lg|xl|2xl)|font-black/);
  assert.match(css, /\.ticket-document \{[\s\S]*font-size: 11px;[\s\S]*font-weight: 400/);
  assert.match(css, /\.ticket-document \.ticket-brand \{[\s\S]*font-size: 14px;[\s\S]*font-weight: 700/);
  assert.match(css, /\.ticket-document \.ticket-type \{[\s\S]*font-size: 12px;[\s\S]*font-weight: 700/);
  assert.match(css, /\.ticket-document \.ticket-location \{[\s\S]*font-size: 11px;[\s\S]*font-weight: 500/);
  assert.match(css, /\.ticket-document \.ticket-disclaimer \{[\s\S]*font-size: 11px/);
  assert.match(css, /\.ticket-document \.ticket-section-title \{[\s\S]*font-size: 11px;[\s\S]*font-weight: 600/);
  assert.match(css, /\.ticket-document \.ticket-total \{[\s\S]*font-size: 12px;[\s\S]*font-weight: 700/);
  assert.match(css, /\.ticket-document \.ticket-footer \{[\s\S]*font-size: 11px;[\s\S]*font-weight: 400/);
  assert.match(css, /\.ticket-document \.ticket-actions \{[\s\S]*font-size: 14px;[\s\S]*font-weight: 600/);
  const typography = css.slice(css.indexOf(".ticket-document {"), css.indexOf("@media print"));
  assert.deepEqual(
    [...new Set([...typography.matchAll(/font-size: (\d+)px/g)].map((match) => Number(match[1])))].sort((a, b) => a - b),
    [11, 12, 14],
  );
  assert.match(css, /@media print[\s\S]*\.print-document \{[\s\S]*font-size: 11px;[\s\S]*line-height: 1\.35/);
});
