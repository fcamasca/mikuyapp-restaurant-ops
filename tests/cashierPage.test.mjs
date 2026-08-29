import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import test from 'node:test'
import { createCashierService, groupCashierOrders } from '../src/services/cashierService.ts'
import { getRoleDestination, resolveApplicationRoute } from '../src/services/appRoutes.ts'

const pageSource = readFileSync(new URL('../src/pages/CashierPage.tsx', import.meta.url), 'utf8')
const appSource = readFileSync(new URL('../src/App.tsx', import.meta.url), 'utf8')
const serviceSource = readFileSync(new URL('../src/services/cashierService.ts', import.meta.url), 'utf8')
const context = (role = 'CAJA') => ({ profile: { id: 'u1', local_id: 'l1', rol_id: 4, nombre: 'Caja', activo: true }, role: { id: 4, codigo: role, activo: true }, local: { id: 'l1', nombre: 'Mikuy Centro', activo: true } })
const row = (overrides = {}) => ({ pedido_id: 10, pedido_estado: 'ENTREGADO', pedido_creado_en: '2026-08-29T15:00:00Z', mesa_id: 'm1', mesa_codigo: 'M01', mesa_nombre: 'Terraza', mesa_estado: 'PENDIENTE_PAGO', detalle_id: 101, producto_id: 'p1', producto_nombre: 'Ceviche', cantidad: 2, precio_unitario: '12.50', importe_linea: '25.00', total_pedido: '31.00', ...overrides })

function client(responses) {
  const calls = []
  return { calls, rpc: async (name, args) => { calls.push({ name, args }); return responses[name] } }
}

test('H5-T05 protege /caja y la convierte en destino exclusivo de CAJA', () => {
  assert.equal(getRoleDestination('CAJA'), '/caja')
  assert.deepEqual(resolveApplicationRoute({ pathname: '/caja', authenticationStatus: 'authenticated', contextStatus: 'valid', role: 'CAJA' }), { status: 'allowed', pathname: '/caja' })
  for (const role of ['MOZO', 'COCINA', 'ADMINISTRADOR']) assert.deepEqual(resolveApplicationRoute({ pathname: '/caja', authenticationStatus: 'authenticated', contextStatus: 'valid', role }), { status: 'redirect', pathname: '/403' })
  assert.match(appSource, /<CashierPage/)
})

test('agrupa líneas por pedido y conserva total autoritativo de PostgreSQL', () => {
  const orders = groupCashierOrders([row(), row({ detalle_id: 102, producto_id: 'p2', producto_nombre: 'Chicha', cantidad: 1, precio_unitario: 6, importe_linea: 6 })])
  assert.equal(orders.length, 1)
  assert.equal(orders[0].total, 31)
  assert.deepEqual(orders[0].lines.map((line) => line.lineAmount), [25, 6])
})

test('consulta pendientes y cobra exclusivamente mediante las RPC H5 aprobadas', async () => {
  const fixture = client({ obtener_pedidos_pendientes_pago_caja: { data: [row()], error: null }, registrar_pago_pedido: { data: [{ pago_id: 7, pedido_id: 10, pedido_estado: 'PAGADO', mesa_id: 'm1', mesa_estado: 'LIBRE', importe: '31.00', medio: 'YAPE', pagado_en: '2026-08-29T16:00:00Z' }], error: null } })
  const service = createCashierService(fixture)
  const pending = await service.getPendingOrders(context())
  const paid = await service.registerPayment(context(), 10, 'YAPE')
  assert.equal(pending.ok, true)
  assert.deepEqual(paid, { ok: true, data: { paymentId: 7, orderId: 10, orderStatus: 'PAGADO', tableId: 'm1', tableStatus: 'LIBRE', amount: 31, method: 'YAPE', paidAt: '2026-08-29T16:00:00Z' } })
  assert.deepEqual(fixture.calls, [{ name: 'obtener_pedidos_pendientes_pago_caja', args: undefined }, { name: 'registrar_pago_pedido', args: { p_pedido_id: 10, p_medio: 'YAPE' } }])
  assert.doesNotMatch(serviceSource, /p_importe|from\(['"]pago|from\(['"]pedido/)
})

test('rechaza otros roles y traduce conflicto sin falso éxito', async () => {
  const fixture = client({ registrar_pago_pedido: { data: null, error: { code: '40001' } } })
  const service = createCashierService(fixture)
  assert.equal((await service.registerPayment(context('MOZO'), 10, 'EFECTIVO')).ok, false)
  const conflict = await service.registerPayment(context(), 10, 'EFECTIVO')
  assert.equal(conflict.ok, false)
  assert.equal(conflict.error.kind, 'conflict')
  assert.match(conflict.error.message, /ya fue procesado/)
})

test('UI cubre carga, vacío, error, confirmación, doble clic y cuatro medios', () => {
  for (const text of ['Cargando pedidos pendientes…', 'No hay pedidos pendientes de pago.', 'Reintentar', 'Confirmar y cobrar', 'Registrando pago…', 'EFECTIVO', 'YAPE', 'PLIN', 'TARJETA']) assert.match(pageSource, new RegExp(text))
  assert.match(pageSource, /payingRef\.current/)
  assert.match(pageSource, /disabled=\{paying\}/)
  assert.match(pageSource, /await load\(false\)/)
  assert.match(pageSource, /!refreshed\.some\(\(order\) => order\.orderId === selected\.orderId\)/)
  assert.match(pageSource, /Este pedido ya fue procesado\. La lista de caja está actualizada\./)
  assert.match(pageSource, /sm:grid-cols-2/)
  assert.match(pageSource, /lg:grid-cols-/)
})

test('precuenta usa ENTREGADO y ticket aparece únicamente después de PAGADO', () => {
  assert.match(pageSource, /Abrir precuenta/)
  assert.match(pageSource, /Pedido pendiente de pago/)
  assert.match(pageSource, /setPayment\(result\.data\)/)
  assert.match(pageSource, /payment && paidOrder &&/)
  assert.match(pageSource, /Abrir ticket interno/)
  assert.match(pageSource, /document === 'TICKET' \? payment : null/)
})

test('presenta local, moneda, locale y zona horaria aprobados', () => {
  assert.match(pageSource, /context\.local\.nombre/)
  assert.match(pageSource, /Intl\.NumberFormat\('es-PE'/)
  assert.match(pageSource, /Intl\.DateTimeFormat\('es-PE'/)
  assert.match(pageSource, /timeZone: 'America\/Lima'/)
})
