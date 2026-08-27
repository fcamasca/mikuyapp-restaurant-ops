import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import test from 'node:test'
import { createKitchenRealtimeService, formatKitchenAge, groupKitchenBoard, runKitchenDetailMutation, settleKitchenTransitionsFromSnapshot } from '../src/services/kitchenRealtimeService.ts'
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
  assert.equal(formatKitchenAge('2026-08-27T12:00:00Z', Date.parse('2026-08-27T13:05:00Z')), 'Enviado hace 1 h 5 min')
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
  assert.match(pageSource, /onSnapshot\(snapshot\)[\s\S]*setRows\(snapshot\)/)
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
  assert.match(pageSource, /onSnapshot\(snapshot\)[\s\S]*setRows\(snapshot\)/)
  assert.match(pageSource, /onError\(message\)/)
  assert.match(pageSource, /activeHandle = handle/)
  assert.match(pageSource, /void activeHandle\.stop\(\)/)
  assert.doesNotMatch(pageSource, /setRows\(\(current\)|\.push\(snapshot|payload\.(new|old)/)
})
