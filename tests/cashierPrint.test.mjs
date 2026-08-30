import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import test from 'node:test'

const pageSource = readFileSync(new URL('../src/pages/CashierPage.tsx', import.meta.url), 'utf8')
const cssSource = readFileSync(new URL('../src/index.css', import.meta.url), 'utf8')

test('H5-T07 precuenta y ticket reutilizan un único documento visible', () => {
  assert.match(pageSource, /function DocumentView/)
  assert.match(pageSource, /kind: 'PRECUENTA' \| 'TICKET'/)
  assert.match(pageSource, /className="print-document/)
  assert.match(pageSource, /kind === 'PRECUENTA' \? 'Precuenta' : 'Ticket interno'/)
  assert.match(pageSource, /Documento informativo · Pedido pendiente de pago/)
})

test('H5-T07 imprime exclusivamente bajo acción explícita del navegador', () => {
  assert.match(pageSource, /onClick=\{\(\) => window\.print\(\)\}/)
  assert.match(pageSource, />Imprimir<\/button>/)
  assert.equal(pageSource.match(/window\.print\(\)/g)?.length, 1)
  assert.doesNotMatch(pageSource, /setTimeout\([^)]*window\.print|useEffect\([^)]*window\.print/)
  assert.match(pageSource, /onClick=\{onClose\}/)
})

test('H5-T07 conserva todos los campos obligatorios en es-PE y America/Lima', () => {
  for (const expression of [
    /\{localName\}/,
    /Pedido #\{order\.orderId\}/,
    /Mesa \{order\.tableCode\}/,
    /order\.tableName/,
    /Fecha\/hora:/,
    /dateTime\.format\(new Date\(documentDate\)\)/,
    /line\.productName/,
    /line\.quantity/,
    /money\.format\(line\.unitPrice\)/,
    /money\.format\(line\.lineAmount\)/,
    /money\.format\(payment\?\.amount \?\? order\.total\)/,
  ]) assert.match(pageSource, expression)
  assert.match(pageSource, /Intl\.NumberFormat\('es-PE'/)
  assert.match(pageSource, /Intl\.DateTimeFormat\('es-PE'/)
  assert.match(pageSource, /timeZone: 'America\/Lima'/)
})

test('H5-T07 ticket incluye medio y precuenta no recibe pago', () => {
  assert.match(pageSource, /Medio de pago: <strong>\{payment\.method\}<\/strong>/)
  assert.match(pageSource, /document === 'TICKET' \? payment : null/)
  assert.match(pageSource, /documentDate = payment\?\.paidAt \?\? order\.createdAt/)
  assert.match(pageSource, /kind === 'PRECUENTA' \? <p[\s\S]*: payment && <div className="payment-summary/)
})

test('H5-T07 contrato térmico usa 80 mm, monocromo y saltos controlados', () => {
  assert.match(cssSource, /@media print/)
  assert.match(cssSource, /@page\s*\{[\s\S]*size: 80mm auto/)
  assert.match(cssSource, /width: 72mm/)
  assert.match(cssSource, /max-width: 72mm/)
  assert.match(cssSource, /background: #fff !important/)
  assert.match(cssSource, /color: #000 !important/)
  assert.match(cssSource, /break-inside: avoid/)
  assert.match(cssSource, /page-break-inside: avoid/)
})

test('H5-TH06 usa dos líneas legibles por producto sin tabla comprimida', () => {
  assert.match(pageSource, /className="product-name/)
  assert.match(pageSource, /className="line-metadata/)
  assert.match(pageSource, /\{line\.quantity\} × \{money\.format\(line\.unitPrice\)\}/)
  assert.match(pageSource, /className="line-amount[^"]*">\{money\.format\(line\.lineAmount\)\}/)
  assert.doesNotMatch(pageSource, /document-table|<table|P\. unitario/)
  assert.match(cssSource, /\.print-document \.line-metadata\s*\{[\s\S]*display: flex[\s\S]*justify-content: space-between/)
  assert.match(cssSource, /\.print-document \.line-amount\s*\{[\s\S]*white-space: nowrap/)
  assert.match(cssSource, /\.print-document \.consumption-item\s*\{[\s\S]*break-inside: avoid[\s\S]*page-break-inside: avoid/)
})

test('H5-T07 oculta aplicación y acciones al imprimir', () => {
  assert.match(cssSource, /body \*\s*\{[\s\S]*visibility: hidden !important/)
  assert.match(cssSource, /\.print-document,\s*\.print-document \*\s*\{[\s\S]*visibility: visible !important/)
  assert.match(cssSource, /\.print-document \.no-print\s*\{[\s\S]*display: none !important/)
  assert.match(pageSource, /className="no-print/)
})
