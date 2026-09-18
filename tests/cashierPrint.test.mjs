import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";
const page = readFileSync(
    new URL("../src/pages/CashierPage.tsx", import.meta.url),
    "utf8",
  ),
  css = readFileSync(new URL("../src/index.css", import.meta.url), "utf8");
test("TP48 distingue recibo parcial y ticket consolidado", () => {
  assert.match(page, /payment\.balance\s*===\s*0/);
  assert.match(page, /Ticket consolidado interno/);
  assert.match(page, /Recibo interno de pago parcial/);
  assert.match(page, /Documento interno · No es comprobante fiscal/);
  for (const x of [
    "Subtotal:",
    "Descuento:",
    "Total neto:",
    "Saldo:",
    "propina",
  ])
    assert.match(page, new RegExp(x));
});
test("documento consolida cobros y sus N medios sin detalle persistido", () => {
  assert.match(page, /payments/);
  assert.match(page, /Cobro \{x\.chargeId\.slice/);
  assert.match(page, /x\.lines\.map/);
  assert.doesNotMatch(page, /pago_detalle|subcuenta|subpedido/);
});
test("impresión conserva overlay y oculta acciones", () => {
  assert.match(page, /print-overlay/);
  assert.match(page, /print-document/);
  assert.match(page, /window\.print/);
  assert.match(css, /@media print/);
  assert.match(css, /\.no-print/);
});
