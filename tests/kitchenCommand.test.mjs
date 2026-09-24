import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import test from 'node:test'
import { buildCommandDocument, commandCopyLabel, commandPrintAction, createKitchenCommandService } from '../src/services/kitchenCommandService.ts'

// E7-T09 — Comandas (E7-R23–R28, E7-TP23/TP24 partes Node)
const pageSource = readFileSync(new URL('../src/pages/KitchenBoardPage.tsx', import.meta.url), 'utf8')
const documentSource = readFileSync(new URL('../src/components/KitchenCommandDocument.tsx', import.meta.url), 'utf8')
const serviceSource = readFileSync(new URL('../src/services/kitchenCommandService.ts', import.meta.url), 'utf8')

function command(overrides = {}) {
  return {
    comanda_id: 7, pedido_id: 10, numero: 2, mesa_codigo: 'M01', mesa_nombre: 'Terraza',
    enviado_en: '2026-09-24T17:00:00Z', creado_en: '2026-09-24T17:00:00Z', creado_por_nombre: 'Mozo Ana',
    lineas: [
      { detalle_id: 101, producto_codigo: 'CEV', producto_nombre: 'Ceviche', cantidad: 2, observacion: 'Sin ají' },
      { detalle_id: 102, producto_codigo: 'ARR', producto_nombre: 'Arroz', cantidad: 1, observacion: null },
    ],
    impresiones: 0, primera_impresion_en: null, ultima_impresion_en: null,
    ...overrides,
  }
}

function rpcClient(response, calls = []) {
  return { calls, client: { async rpc(name, args) { calls.push({ name, args }); return response } } }
}

test('E7-T09 una sola primera solicitud: Imprimir y luego Reimprimir', () => {
  assert.equal(commandPrintAction(command({ impresiones: 0 })), 'Imprimir')
  assert.equal(commandPrintAction(command({ impresiones: 1 })), 'Reimprimir')
  assert.equal(commandPrintAction(command({ impresiones: 3 })), 'Reimprimir')
})

test('E7-T09 identifica COPIA n en reimpresiones', () => {
  assert.equal(commandCopyLabel(1), null)
  assert.equal(commandCopyLabel(2), 'COPIA 1')
  assert.equal(commandCopyLabel(3), 'COPIA 2')
})

test('E7-T09 documento: líneas históricas, canceladas marcadas y datos de mesa/pedido/mozo', () => {
  const doc = buildCommandDocument(command(), [{ detalle_id: 102 }, { detalle_id: 999 }], 3)
  assert.equal(doc.title, 'COMANDA #2')
  assert.equal(doc.copyLabel, 'COPIA 2')
  assert.equal(doc.mesa, 'M01 · Terraza')
  assert.equal(doc.pedidoId, 10)
  assert.equal(doc.mozo, 'Mozo Ana')
  assert.deepEqual(doc.lines.map((line) => [line.detalle_id, line.cancelado]), [[101, false], [102, true]])
  assert.equal(doc.lines.length, 2) // contenido inmutable: no agrega ni quita líneas
})

test('E7-T09 registra la primera solicitud y las reimpresiones vía RPC', async () => {
  const first = rpcClient({ data: [{ comanda_id: 7, impresiones: 1, es_reimpresion: false }], error: null })
  assert.deepEqual(await createKitchenCommandService(first.client).registerPrint(7, false), { ok: true, impresiones: 1 })
  assert.deepEqual(first.calls, [{ name: 'rpc_registrar_impresion_comanda', args: { p_comanda_id: 7, p_reimpresion: false } }])
  const again = rpcClient({ data: [{ comanda_id: 7, impresiones: 3, es_reimpresion: true }], error: null })
  assert.deepEqual(await createKitchenCommandService(again.client).registerPrint(7, true), { ok: true, impresiones: 3 })
  assert.equal(again.calls[0].args.p_reimpresion, true)
})

test('E7-T09 primera solicitud ya registrada en otro dispositivo es conflicto recuperable', async () => {
  const conflict = await createKitchenCommandService(rpcClient({ data: null, error: { code: 'PT409', message: 'La comanda ya fue impresa' } }).client).registerPrint(7, false)
  assert.equal(conflict.ok, false)
  assert.equal(conflict.error.kind, 'concurrent-conflict')
  assert.match(conflict.error.message, /Reimprimir/)
  const failure = await createKitchenCommandService(rpcClient({ data: null, error: { code: '42501', message: 'SQL secret' } }).client).registerPrint(7, true)
  assert.equal(failure.error.kind, 'operation-error')
  assert.doesNotMatch(failure.error.message, /SQL|secret/)
})

test('E7-T09 pantalla: comandas en el tablero con Imprimir/Reimprimir, guard y registro previo a window.print()', () => {
  assert.match(pageSource, /Comandas \(opcional\)/)
  assert.match(pageSource, /commandPrintAction\(command\)/)
  assert.match(pageSource, /'Sin imprimir'/)
  assert.match(pageSource, /if \(!commandService \|\| printingCommands\.current\.has\(command\.comanda_id\)\) return/)
  assert.match(pageSource, /commandService\.registerPrint\(command\.comanda_id, commandPrintAction\(command\) === 'Reimprimir'\)/)
  assert.match(pageSource, /if \(result\.ok\) \{\s*setPrintDocument\(buildCommandDocument\(/)
  assert.match(pageSource, /if \(printDocument\) window\.print\(\)/)
  assert.match(pageSource, /\{printDocument && <KitchenCommandDocument/)
  // el registro de impresión no escribe estados ni el snapshot local
  assert.doesNotMatch(serviceSource, /actualizar_estado|recibir|enviar|setRows/)
})

test('E7-T09 documento 80 mm reutiliza estilos de impresión y no ofrece imprimir sin registrar', () => {
  assert.match(documentSource, /print-overlay/)
  assert.match(documentSource, /print-document/)
  assert.match(documentSource, /\{document\.copyLabel && /)
  assert.match(documentSource, /CANCELADO/)
  assert.match(documentSource, /no-print/)
  assert.doesNotMatch(documentSource, /window\.print/)
  assert.match(documentSource, /usa Reimprimir/)
})

test('E7-T09 sin preferencias, almacenamiento del navegador ni infraestructura de impresión', () => {
  for (const source of [pageSource, documentSource, serviceSource]) {
    assert.doesNotMatch(source, /localStorage|sessionStorage|indexedDB/i)
    assert.doesNotMatch(source, /escpos|ESC\/POS|bluetooth|usb|serial|WebSocket|fetch\(/i)
  }
})
