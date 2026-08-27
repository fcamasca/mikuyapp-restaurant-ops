import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import test from 'node:test'
import { createKitchenRealtimeService, formatKitchenAge, groupKitchenBoard } from '../src/services/kitchenRealtimeService.ts'
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
  assert.match(pageSource, /pendingIds\.current\.has\(detail\.detalle_id\)/)
  assert.match(pageSource, /pendingIds\.current\.add\(detail\.detalle_id\)/)
  assert.match(pageSource, /pendingIds\.current\.delete\(detail\.detalle_id\)/)
  assert.match(pageSource, /Actualizando…/)
  assert.match(pageSource, /await handleRef\.current\?\.resync\(\)/)
  assert.match(pageSource, /detailMessages/)
  assert.doesNotMatch(pageSource, /setRows\([^)]*estado/)
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
