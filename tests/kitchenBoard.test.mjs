import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import test from 'node:test'
import { countPendingReception, createKitchenRealtimeService, formatKitchenAge, groupKitchenBoard, groupKitchenCancellations, parseKitchenSnapshot, runKitchenDetailMutation, settleKitchenTransitionsFromSnapshot } from '../src/services/kitchenRealtimeService.ts'
import { getRoleDestination, resolveApplicationRoute } from '../src/services/appRoutes.ts'

const pageSource = readFileSync(new URL('../src/pages/KitchenBoardPage.tsx', import.meta.url), 'utf8')
const appSource = readFileSync(new URL('../src/App.tsx', import.meta.url), 'utf8')
const serviceSource = readFileSync(new URL('../src/services/kitchenRealtimeService.ts', import.meta.url), 'utf8')

function detail(overrides = {}) {
  return {
    pedido_id: 10,
    pedido_estado: 'ENVIADO',
    mesa_id: 'mesa-1',
    mesa_codigo: 'M01',
    mesa_nombre: 'Terraza',
    mesa_estado: 'OCUPADA',
    detalle_id: 101,
    producto_id: 'product-1',
    producto_codigo: 'P01',
    producto_nombre: 'Ceviche clásico',
    cantidad: 2,
    observacion: 'Sin cebolla',
    estado: 'ENVIADO',
    enviado_en: '2026-08-27T12:00:00Z',
    modificado_en: '2026-08-27T12:00:00Z',
    ...overrides,
  }
}

test('H4-T06 protege /cocina y la usa como destino operativo de COCINA', () => {
  assert.equal(getRoleDestination('COCINA'), '/cocina')
  assert.deepEqual(resolveApplicationRoute({
    pathname: '/cocina', authenticationStatus: 'authenticated', contextStatus: 'valid', role: 'COCINA',
  }), { status: 'allowed', pathname: '/cocina' })
  assert.deepEqual(resolveApplicationRoute({
    pathname: '/cocina', authenticationStatus: 'authenticated', contextStatus: 'valid', role: 'MOZO',
  }), { status: 'redirect', pathname: '/403' })
  assert.match(appSource, /<KitchenBoardPage/)
})

test('H4-T06 agrupa por pedido/mesa y ordena grupos y líneas por enviado_en', () => {
  const groups = groupKitchenBoard([
    detail({ pedido_id: 20, detalle_id: 202, enviado_en: '2026-08-27T12:06:00Z' }),
    detail({ pedido_id: 10, detalle_id: 102, enviado_en: '2026-08-27T12:04:00Z' }),
    detail({ pedido_id: 10, detalle_id: 101, enviado_en: '2026-08-27T12:02:00Z' }),
    detail({ pedido_id: 20, detalle_id: 201, enviado_en: '2026-08-27T12:05:00Z' }),
  ])
  assert.deepEqual(groups.map((group) => group.pedidoId), [10, 20])
  assert.deepEqual(groups[0].details.map((item) => item.detalle_id), [101, 102])
})

test('H4-T06 prioriza trabajo no listo y muestra antigüedad legible', () => {
  const groups = groupKitchenBoard([
    detail({ pedido_id: 10, detalle_id: 101, estado: 'LISTO', enviado_en: '2026-08-27T11:00:00Z' }),
    detail({ pedido_id: 10, detalle_id: 102, estado: 'EN_PREPARACION', enviado_en: '2026-08-27T12:00:00Z' }),
  ])
  assert.equal(groups[0].oldestSentAt, '2026-08-27T12:00:00Z')
  assert.deepEqual(groups[0].details.map((item) => item.detalle_id), [102, 101])
  assert.equal(groups[0].allReady, false)
  assert.equal(formatKitchenAge('2026-08-27T12:00:00Z', Date.parse('2026-08-27T13:05:00Z')), 'Enviado hace 1 h 5 min')
})

test('H4-T10 pedido mixto prioriza pendientes y conserva LISTO al final del grupo', () => {
  const groups = groupKitchenBoard([
    detail({ pedido_id: 10, detalle_id: 101, estado: 'LISTO', enviado_en: '2026-08-27T11:00:00Z' }),
    detail({ pedido_id: 10, detalle_id: 102, estado: 'EN_PREPARACION', enviado_en: '2026-08-27T12:00:00Z' }),
    detail({ pedido_id: 10, detalle_id: 103, estado: 'RECIBIDO_COCINA', enviado_en: '2026-08-27T11:30:00Z' }),
  ])
  assert.deepEqual(groups[0].details.map((item) => item.detalle_id), [103, 102, 101])
  assert.equal(groups[0].oldestSentAt, '2026-08-27T11:30:00Z')
})

test('H4-T10 pedidos completamente LISTO van al final y permanecen visibles', () => {
  const groups = groupKitchenBoard([
    detail({ pedido_id: 20, detalle_id: 201, estado: 'LISTO', enviado_en: '2026-08-27T10:00:00Z' }),
    detail({ pedido_id: 10, detalle_id: 101, estado: 'EN_PREPARACION', enviado_en: '2026-08-27T12:00:00Z' }),
    detail({ pedido_id: 30, detalle_id: 301, estado: 'LISTO', enviado_en: '2026-08-27T11:00:00Z' }),
  ])
  assert.deepEqual(groups.map((group) => group.pedidoId), [10, 20, 30])
  assert.deepEqual(groups.map((group) => group.allReady), [false, true, true])
  assert.equal(groups.flatMap((group) => group.details).length, 3)
  assert.match(pageSource, />Listos</)
  assert.match(pageSource, /Permanecen visibles hasta completar la entrega en H5/)
})

test('H4-T06 muestra estados textuales y únicamente acciones adyacentes válidas', () => {
  for (const text of ['Nuevo · Por recibir', 'Recibido', 'En preparación', 'Listo', 'Recibir', 'Iniciar preparación', 'Marcar listo', 'Preparación completada']) {
    assert.match(pageSource, new RegExp(text))
  }
  assert.match(pageSource, /producto_nombre/)
  assert.match(pageSource, /Cantidad:/)
  assert.match(pageSource, /Observación:/)
  assert.match(pageSource, /presentation\.action/)
})

test('H4-T06 transición usa RPC, conserva estados esperados y traduce conflicto', async () => {
  const rpcCalls = []
  const client = {
    async rpc(name, args) {
      rpcCalls.push({ name, args })
      return { data: null, error: { code: '40001' } }
    },
    channel() { throw new Error('No debe suscribirse para esta prueba') },
    async removeChannel() {},
  }
  const result = await createKitchenRealtimeService(client).transitionDetail(101, 'ENVIADO', 'RECIBIDO_COCINA')
  assert.equal(result.ok, false)
  assert.equal(result.error.kind, 'concurrent-conflict')
  assert.deepEqual(rpcCalls, [{
    name: 'actualizar_estado_detalle_cocina',
    args: { p_detalle_id: 101, p_estado_esperado: 'ENVIADO', p_estado_nuevo: 'RECIBIDO_COCINA' },
  }])
})

test('E1-T18 H4-T06 transición traduce conflicto con el código vigente PT409', async () => {
  const rpcCalls = []
  const client = {
    async rpc(name, args) {
      rpcCalls.push({ name, args })
      return { data: null, error: { code: 'PT409' } }
    },
    channel() { throw new Error('No debe suscribirse para esta prueba') },
    async removeChannel() {},
  }
  const result = await createKitchenRealtimeService(client).transitionDetail(101, 'ENVIADO', 'RECIBIDO_COCINA')
  assert.equal(result.ok, false)
  assert.equal(result.error.kind, 'concurrent-conflict')
  assert.deepEqual(rpcCalls, [{
    name: 'actualizar_estado_detalle_cocina',
    args: { p_detalle_id: 101, p_estado_esperado: 'ENVIADO', p_estado_nuevo: 'RECIBIDO_COCINA' },
  }])
})

test('H4-T06 bloquea por detalle, muestra feedback y resincroniza tras éxito o conflicto', () => {
  assert.match(pageSource, /pendingTransitions\.current\.has\(detail\.detalle_id\)/)
  assert.match(pageSource, /pendingTransitions\.current\.set\(detail\.detalle_id/)
  assert.match(pageSource, /pendingTransitions\.current\.delete\(detail\.detalle_id\)/)
  assert.match(pageSource, /Actualizando…/)
  assert.match(pageSource, /runKitchenDetailMutation/)
  assert.match(pageSource, /detailMessages/)
  assert.doesNotMatch(pageSource, /setRows\([^)]*estado/)
})

test('H4-TH06 RPC pendiente + snapshot ganador libera Actualizando inmediatamente', async () => {
  let resolveRpc
  const rpcPending = new Promise((resolve) => { resolveRpc = resolve })
  const token = Symbol('pending-rpc')
  const pending = new Map([[101, { expectedStatus: 'RECIBIDO_COCINA', token }]])

  let rpcFinished = false
  void rpcPending.then(() => { rpcFinished = true })
  const settled = settleKitchenTransitionsFromSnapshot(pending, [
    detail({ detalle_id: 101, estado: 'EN_PREPARACION' }),
  ])

  assert.equal(rpcFinished, false)
  assert.deepEqual(settled, [101])
  assert.equal(pending.has(101), false)

  resolveRpc({ ok: false, error: { kind: 'concurrent-conflict' } })
  await rpcPending
  assert.equal(pending.has(101), false)
  assert.match(pageSource, /settleKitchenTransitionsFromSnapshot\(pendingTransitions\.current, snapshot\)/)
  assert.match(pageSource, /setBusyIds\(\(current\) => current\.filter\(\(id\) => !settledIds\.includes\(id\)\)\)/)
})

test('H4-TH06 respuesta RPC tardía queda invalidada por token y no sobrescribe snapshot', () => {
  assert.match(pageSource, /pendingTransitions\.current\.get\(detail\.detalle_id\)\?\.token !== operationToken/)
  // E7-D08: onSnapshot recibe además el snapshot completo (comandas/cancelaciones).
  assert.match(pageSource, /onSnapshot\(snapshot, board\)[\s\S]*setRows\(snapshot\)/)
  assert.doesNotMatch(pageSource, /setRows\([^)]*result|setRows\([^)]*next/)
})

test('H4-TH06 libera Actualizando al recibir 40001 aunque la resincronización siga pendiente', async () => {
  let resolveResync
  let released = false
  let observedResult = null
  const pendingResync = new Promise((resolve) => { resolveResync = resolve })

  const mutation = runKitchenDetailMutation({
    operation: async () => ({
      ok: false,
      error: {
        kind: 'concurrent-conflict',
        message: 'Este producto fue actualizado desde otro dispositivo. Se cargó la versión más reciente.',
      },
    }),
    onResult(result) { observedResult = result },
    releasePending() { released = true },
    resync: () => pendingResync,
  })

  await new Promise((resolve) => setImmediate(resolve))
  assert.equal(released, true)
  assert.equal(observedResult.error.kind, 'concurrent-conflict')

  let completed = false
  void mutation.then(() => { completed = true })
  await new Promise((resolve) => setImmediate(resolve))
  assert.equal(completed, false)

  resolveResync()
  await mutation
  assert.equal(completed, true)
})

test('H4-TH06 libera guard también ante error y resincro refleja snapshot ganador', async () => {
  const order = []
  await runKitchenDetailMutation({
    operation: async () => ({ ok: false, error: { kind: 'operation-error', message: 'Error recuperable' } }),
    onResult() { order.push('result') },
    releasePending() { order.push('released') },
    async resync() { order.push('resynced') },
  })
  assert.deepEqual(order, ['result', 'released', 'resynced'])
})

test('H4-T06 incluye carga, vacío, error recuperable y responsive táctil', () => {
  for (const text of ['Cargando pedidos de cocina…', 'No hay productos pendientes en cocina.', 'Reintentar']) {
    assert.match(pageSource, new RegExp(text))
  }
  assert.match(pageSource, /min-h-11/)
  assert.match(pageSource, /overflow-x-hidden/)
  assert.match(pageSource, /sm:grid-cols-2/)
  assert.match(pageSource, /xl:grid-cols-2/)
  assert.doesNotMatch(serviceSource, /setInterval|poll/i)
})

test('H4-T07 página reemplaza filas con snapshots y limpia el canal al desmontarse', () => {
  assert.match(pageSource, /service\.start\(\{/)
  // E7-D08: onSnapshot recibe además el snapshot completo (comandas/cancelaciones).
  assert.match(pageSource, /onSnapshot\(snapshot, board\)[\s\S]*setRows\(snapshot\)/)
  assert.match(pageSource, /onError\(message\)/)
  assert.match(pageSource, /activeHandle = handle/)
  assert.match(pageSource, /void activeHandle\.stop\(\)/)
  assert.doesNotMatch(pageSource, /setRows\(\(current\)|\.push\(snapshot|payload\.(new|old)/)
})


// ===== E7-T08 — Cocina: snapshot unificado, recepción completa y cancelaciones (E7-R05, R09–R11, R15, R17)
function rpcClient(response, calls = []) {
  return { calls, client: { async rpc(name, args) { calls.push({ name, args }); return response } } }
}

test('E7-T08 valida el snapshot unificado y rechaza formas inválidas', () => {
  const board = { detalles: [detail()], comandas: [], cancelaciones: [] }
  assert.deepEqual(parseKitchenSnapshot(board), board)
  assert.equal(parseKitchenSnapshot([detail()]), null)
  assert.equal(parseKitchenSnapshot({ detalles: [] }), null)
  assert.equal(parseKitchenSnapshot(null), null)
})

test('E7-T08 cuenta sólo ENVIADO para Recibir pedido (N) y agrupa cancelaciones por pedido', () => {
  assert.equal(countPendingReception([
    detail({ estado: 'ENVIADO' }), detail({ estado: 'ENVIADO' }),
    detail({ estado: 'RECIBIDO_COCINA' }), detail({ estado: 'EN_PREPARACION' }), detail({ estado: 'LISTO' }),
  ]), 2)
  const byOrder = groupKitchenCancellations([
    { pedido_id: 10, detalle_id: 1, producto_nombre: 'A', cantidad: 1, observacion: null, estado_anterior: 'ENVIADO', motivo: 'x', cancelado_en: 't' },
    { pedido_id: 20, detalle_id: 2, producto_nombre: 'B', cantidad: 2, observacion: null, estado_anterior: 'RECIBIDO_COCINA', motivo: 'y', cancelado_en: 't' },
    { pedido_id: 10, detalle_id: 3, producto_nombre: 'C', cantidad: 1, observacion: null, estado_anterior: 'ENVIADO', motivo: 'z', cancelado_en: 't' },
  ])
  assert.deepEqual(byOrder.get(10).map((item) => item.detalle_id), [1, 3])
  assert.equal(byOrder.get(20).length, 1)
})

test('E7-T08 recepción completa usa la RPC transaccional y 0 recibidos es éxito', async () => {
  const ok = rpcClient({ data: [{ pedido_id: 10, detalles_recibidos: 3, detalle_ids: [1, 2, 3], pedido_estado: 'RECIBIDO_COCINA' }], error: null })
  assert.deepEqual(await createKitchenRealtimeService(ok.client).receiveOrder(10), { ok: true, received: 3 })
  assert.deepEqual(ok.calls, [{ name: 'rpc_recibir_pedido_cocina', args: { p_pedido_id: 10 } }])
  const retry = rpcClient({ data: [{ pedido_id: 10, detalles_recibidos: 0, detalle_ids: [], pedido_estado: 'RECIBIDO_COCINA' }], error: null })
  assert.deepEqual(await createKitchenRealtimeService(retry.client).receiveOrder(10), { ok: true, received: 0 })
})

test('E7-T08 recepción completa: PT409 es conflicto recuperable; otros errores no filtran detalles', async () => {
  const conflict = await createKitchenRealtimeService(rpcClient({ data: null, error: { code: 'PT409', message: 'El pedido ya no está en cocina' } }).client).receiveOrder(10)
  assert.equal(conflict.ok, false)
  assert.equal(conflict.error.kind, 'concurrent-conflict')
  const failure = await createKitchenRealtimeService(rpcClient({ data: null, error: { code: '42501', message: 'SQL secret' } }).client).receiveOrder(10)
  assert.equal(failure.error.kind, 'operation-error')
  assert.doesNotMatch(failure.error.message, /SQL|secret/)
})

test('E7-T08 transición individual sobre producto cancelado informa la cancelación', async () => {
  const result = await createKitchenRealtimeService(rpcClient({ data: null, error: { code: 'PT409', message: 'El detalle fue cancelado por el mozo' } }).client)
    .transitionDetail(101, 'ENVIADO', 'RECIBIDO_COCINA')
  assert.equal(result.ok, false)
  assert.equal(result.error.kind, 'concurrent-conflict')
  assert.match(result.error.message, /mozo canceló/)
})

test('E7-T08 pantalla: botón Recibir pedido (N) con guard por pedido y resync', () => {
  assert.match(pageSource, /countPendingReception\(group\.details\) > 0 && <button/)
  assert.match(pageSource, /`Recibir pedido \(\$\{countPendingReception\(group\.details\)\}\)`/)
  assert.match(pageSource, /if \(!service \|\| receivingOrders\.current\.has\(pedidoId\)\) return/)
  assert.match(pageSource, /receivingOrders\.current\.add\(pedidoId\)/)
  assert.match(pageSource, /receivingOrders\.current\.delete\(pedidoId\)/)
  assert.match(pageSource, /disabled=\{receivingIds\.includes\(group\.pedidoId\)\}/)
  assert.match(pageSource, /await handleRef\.current\?\.resync\(\)\n  \}|await handleRef\.current\?\.resync\(\)\r?\n  \}/)
  // las acciones individuales se conservan y se bloquean mientras se recibe el pedido completo
  assert.match(pageSource, /const busy = busyIds\.includes\(detail\.detalle_id\) \|\| receivingIds\.includes\(group\.pedidoId\)/)
  assert.match(pageSource, /receivingOrders\.current\.has\(detail\.pedido_id\)\) return/)
  assert.match(pageSource, /presentation\.action/)
})

test('E7-T08 pantalla: cancelaciones del pedido visibles como sólo lectura', () => {
  assert.match(pageSource, /Cancelado por el mozo · no preparar/)
  assert.match(pageSource, /cancellationsByOrder\.get\(group\.pedidoId\)/)
  assert.match(pageSource, /Productos cancelados por el mozo/)
  assert.match(pageSource, /setCancellations\(board\.cancelaciones\)/)
})

test('E7-T08 cocina lee sólo la RPC unificada, sin polling ni estado calculado localmente', async () => {
  const calls = []
  const handlers = []
  const channel = { on(type, filter) { handlers.push(filter); return channel }, subscribe() { return channel } }
  const client = {
    async rpc(name) { calls.push(name); return { data: { detalles: [detail()], comandas: [], cancelaciones: [] }, error: null } },
    channel() { return channel },
    async removeChannel() {},
  }
  const snapshots = []
  const handle = await createKitchenRealtimeService(client).start({
    onSnapshot: (rows, board) => snapshots.push({ rows, board }),
    onError: () => assert.fail('sin error'),
  })
  assert.deepEqual(calls, ['rpc_obtener_tablero_cocina'])
  assert.equal(snapshots[0].rows.length, 1)
  assert.deepEqual(snapshots[0].board.cancelaciones, [])
  assert.equal(handlers.length, 6)
  await handle.stop()
  assert.doesNotMatch(serviceSource, /setInterval|poll/i)
  assert.doesNotMatch(pageSource, /setInterval|poll/i)
})

test('E7-T08 snapshot inválido se trata como error recuperable y no reemplaza el tablero', async () => {
  const channel = { on() { return channel }, subscribe() { return channel } }
  const client = { async rpc() { return { data: [detail()], error: null } }, channel() { return channel }, async removeChannel() {} }
  const errors = []
  const handle = await createKitchenRealtimeService(client).start({ onSnapshot: () => assert.fail('no debía aplicar'), onError: (m) => errors.push(m) })
  assert.equal(errors.length, 1)
  await handle.stop()
})
