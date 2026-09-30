import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import test from 'node:test'
import { subscribeToOperationsChanges } from '../src/services/operationsRealtimeService.ts'
import { canRequestBill, createWaiterOrderService, formatBillRequestTime } from '../src/services/waiterOrderService.ts'

const orderPage = readFileSync(new URL('../src/pages/WaiterOrderPage.tsx', import.meta.url), 'utf8')
const tablesPage = readFileSync(new URL('../src/pages/WaiterTablesPage.tsx', import.meta.url), 'utf8')
const kitchenPage = readFileSync(new URL('../src/pages/KitchenBoardPage.tsx', import.meta.url), 'utf8')
const kitchenService = readFileSync(new URL('../src/services/kitchenRealtimeService.ts', import.meta.url), 'utf8')
const realtimeSource = readFileSync(new URL('../src/services/operationsRealtimeService.ts', import.meta.url), 'utf8')
const waiterService = readFileSync(new URL('../src/services/waiterOrderService.ts', import.meta.url), 'utf8')

function context(role = 'MOZO') {
  return {
    profile: { id: 'user-own', local_id: 'local-own', rol_id: 2, nombre: 'Mozo', activo: true },
    role: { id: 2, codigo: role, activo: true },
    local: { id: 'local-own', activo: true },
  }
}

function createClient({ tables = [], orders = [], details = [], rpcData = [], rpcError = null } = {}) {
  const calls = []
  const rpcCalls = []
  return {
    calls,
    rpcCalls,
    client: {
      from(resource) {
        const call = { resource, columns: '', filters: [], inFilters: [] }
        calls.push(call)
        const query = {
          select(columns) { call.columns = columns; return query },
          eq(column, value) { call.filters.push({ column, value }); return query },
          in(column, values) { call.inFilters.push({ column, values }); return query },
          async returns() {
            return { data: resource === 'mesa' ? tables : resource === 'pedido' ? orders : details, error: null }
          },
        }
        return query
      },
      async rpc(name, args) {
        rpcCalls.push({ name, args })
        return name === 'obtener_creadores_pedidos_vigentes' ? { data: [], error: null } : { data: rpcData, error: rpcError }
      },
    },
  }
}

// ===== E10-TP17 / TP13: servicio del mozo

test('E10-T04 solicita la cuenta sólo vía RPC con el pedido, sin actor, local, mesa ni hora del cliente', async () => {
  const fixture = createClient({ rpcData: [{ solicitud_id: 7, pedido_id: 12, estado: 'PENDIENTE', solicitada_en: '2026-09-30T20:00:00Z', solicitada_por: 'user-own', ya_existia: false }] })
  const result = await createWaiterOrderService(fixture.client).requestBill(context(), 12)
  assert.deepEqual(fixture.rpcCalls, [{ name: 'rpc_solicitar_cuenta_pedido', args: { p_pedido_id: 12 } }])
  assert.deepEqual(result, { ok: true, data: { solicitudId: 7, solicitadaEn: '2026-09-30T20:00:00Z', yaExistia: false } })
  assert.equal(fixture.calls.length, 0)
})

test('E10-T04 una repetición devuelve la solicitud existente (ya_existia) sin error', async () => {
  const fixture = createClient({ rpcData: [{ solicitud_id: 7, solicitada_en: '2026-09-30T20:00:00Z', ya_existia: true }] })
  const result = await createWaiterOrderService(fixture.client).requestBill(context(), 12)
  assert.equal(result.ok, true)
  assert.equal(result.data.yaExistia, true)
})

test('E10-T04 PT409 es conflicto recuperable; otros errores y roles ajenos no muestran éxito', async () => {
  const conflict = await createWaiterOrderService(createClient({ rpcError: { code: 'PT409', message: 'x' } }).client).requestBill(context(), 12)
  assert.equal(conflict.ok, false)
  assert.equal(conflict.error.kind, 'concurrent-conflict')
  const failure = await createWaiterOrderService(createClient({ rpcError: { code: '42501', message: 'x' } }).client).requestBill(context(), 12)
  assert.deepEqual(failure, { ok: false, error: { kind: 'operation-error', message: 'No pudimos solicitar la cuenta. Intenta nuevamente.', recoverable: true } })
  const empty = await createWaiterOrderService(createClient({ rpcData: [] }).client).requestBill(context(), 12)
  assert.equal(empty.ok, false)
  const foreign = createClient()
  const denied = await createWaiterOrderService(foreign.client).requestBill(context('CAJA'), 12)
  assert.equal(denied.ok, false)
  assert.equal(foreign.rpcCalls.length, 0)
})

test('E10-TP13 la revisión del pedido lee la solicitud PENDIENTE embebida en la misma petición', async () => {
  const fixture = createClient({
    tables: [{ id: 'table-1', codigo: 'M-01', nombre: 'Terraza', estado: 'PENDIENTE_PAGO' }],
    orders: [{ id: 12, mesa_id: 'table-1', estado: 'ENTREGADO', solicitud_cuenta: [{ id: 7, solicitada_en: '2026-09-30T20:00:00Z' }] }],
  })
  const result = await createWaiterOrderService(fixture.client).getOrderReview(context(), 12)
  assert.equal(result.ok, true)
  assert.equal(result.data.cuentaSolicitadaEn, '2026-09-30T20:00:00Z')
  assert.equal(fixture.calls[0].columns, 'id,mesa_id,estado,solicitud_cuenta(id,solicitada_en)')
  assert.deepEqual(fixture.calls[0].filters.find((filter) => filter.column === 'solicitud_cuenta.estado'), { column: 'solicitud_cuenta.estado', value: 'PENDIENTE' })
  assert.equal(fixture.calls.length, 2)
  const without = await createWaiterOrderService(createClient({
    tables: [{ id: 'table-1', codigo: 'M-01', nombre: 'Terraza', estado: 'PENDIENTE_PAGO' }],
    orders: [{ id: 12, mesa_id: 'table-1', estado: 'ENTREGADO', solicitud_cuenta: [] }],
  }).client).getOrderReview(context(), 12)
  assert.equal('cuentaSolicitadaEn' in without.data, false)
})

test('E10-TP13 el tablero de mesas muestra la solicitud sin viajes de red adicionales', async () => {
  const fixture = createClient({
    tables: [{ id: 'table-1', codigo: 'M-01', nombre: 'Mesa 1', estado: 'PENDIENTE_PAGO', activo: true }, { id: 'table-2', codigo: 'M-02', nombre: 'Mesa 2', estado: 'PENDIENTE_PAGO', activo: true }],
    orders: [
      { id: 21, mesa_id: 'table-1', estado: 'ENTREGADO', creado_por: 'x', solicitud_cuenta: [{ id: 3, solicitada_en: '2026-09-30T20:05:00Z' }] },
      { id: 22, mesa_id: 'table-2', estado: 'ENTREGADO', creado_por: 'x', solicitud_cuenta: [] },
    ],
    details: [{ pedido_id: 21, cantidad: 1, precio_unitario: 8 }, { pedido_id: 22, cantidad: 1, precio_unitario: 8 }],
  })
  const result = await createWaiterOrderService(fixture.client).getTableBoard(context())
  assert.equal(result.ok, true)
  assert.equal(result.data[0].pedido.cuentaSolicitadaEn, '2026-09-30T20:05:00Z')
  assert.equal('cuentaSolicitadaEn' in result.data[1].pedido, false)
  assert.deepEqual(fixture.calls.map((call) => call.resource), ['mesa', 'pedido', 'detalle_pedido'])
  assert.match(fixture.calls[1].columns, /solicitud_cuenta\(id,solicitada_en\)$/)
})

test('E10-T04 la solicitud sólo se ofrece para ENTREGADO sin solicitud pendiente', () => {
  assert.equal(canRequestBill({ estado: 'ENTREGADO' }), true)
  assert.equal(canRequestBill({ estado: 'ENTREGADO', cuentaSolicitadaEn: '2026-09-30T20:00:00Z' }), false)
  for (const estado of ['ABIERTO', 'ENVIADO', 'RECIBIDO_COCINA', 'EN_PREPARACION', 'LISTO', 'PAGADO', 'ANULADO']) {
    assert.equal(canRequestBill({ estado }), false)
  }
  assert.equal(canRequestBill(null), false)
  assert.match(formatBillRequestTime('2026-09-30T20:05:00Z'), /^0?3:05|15:05|03:05/)
})

// ===== E10-TP17: pantallas del mozo

test('E10-T04 WaiterOrderPage: botón Solicitar cuenta con confirmación, guard y estado persistido', () => {
  assert.match(orderPage, /\{canRequestBill\(review\) && <button[^>]*disabled=\{requestingBill\}[^>]*onClick=\{\(\) => setConfirmingBill\(true\)\}[^>]*>Solicitar cuenta<\/button>\}/)
  assert.match(orderPage, /const requestingBillRef = useRef\(false\)/)
  const fn = orderPage.slice(orderPage.indexOf('async function requestBill()'), orderPage.indexOf('return <main'))
  assert.match(fn, /if \(!orders \|\| requestingBillRef\.current \|\| !canRequestBill\(review\)\) return/)
  assert.match(fn, /await orders\.requestBill\(context, orderId\)\s*await reloadOrderSnapshot\(\)/)
  assert.match(fn, /finally \{\s*requestingBillRef\.current = false; setRequestingBill\(false\)/)
  assert.match(fn, /yaExistia/)
  assert.match(orderPage, /Cuenta solicitada a caja · \{formatBillRequestTime\(review\.cuentaSolicitadaEn\)\}/)
  assert.match(orderPage, /role="dialog" aria-modal="true" aria-labelledby="request-bill-title"/)
  assert.match(orderPage, /min-h-11 w-full rounded-xl bg-amber-700/)
})

test('E10-T04 WaiterOrderPage: PT409 resincroniza y un pedido no vigente vuelve a mesas por el flujo E7-T12', () => {
  const fn = orderPage.slice(orderPage.indexOf('async function requestBill()'), orderPage.indexOf('return <main'))
  assert.ok(fn.indexOf('await reloadOrderSnapshot()') < fn.indexOf('if (!result.ok)'))
  assert.match(orderPage, /if \(!reviewResult\.ok && reviewResult\.error\.kind === 'order-not-current'\) \{ onBackRef\.current\(\); return \}/)
})

test('E10-T04 aviso de reapertura con solicitud pendiente, sin bloquear la reapertura H5', () => {
  assert.match(orderPage, /review\?\.estado === 'ENTREGADO' && review\.cuentaSolicitadaEn && <p[^>]*role="note">Si agregas productos, la solicitud de cuenta quedará sin efecto/)
  const add = orderPage.slice(orderPage.indexOf('async function add('), orderPage.indexOf('async function quantity('))
  assert.doesNotMatch(add, /cuentaSolicitadaEn|canRequestBill/)
})

test('E10-T04 WaiterTablesPage muestra la etiqueta Cuenta solicitada en la tarjeta', () => {
  assert.match(tablesPage, /\{table\.pedido\?\.cuentaSolicitadaEn && <p[^>]*>Cuenta solicitada · \{formatBillRequestTime\(table\.pedido\.cuentaSolicitadaEn\)\}<\/p>\}/)
})

// ===== E10-TP16: Realtime

function realtimeFixture(channelName) {
  const handlers = []
  const topics = []
  const channel = {
    on(type, filter, callback) { handlers.push({ type, filter, callback }); return channel },
    subscribe() { return channel },
  }
  return {
    handlers,
    topics,
    client: { channel(name) { topics.push(name); return channel }, async removeChannel() {} },
    options: { channelName, debounceMs: 1, setTimeoutFn(callback) { callback(); return 1 }, clearTimeoutFn() {} },
  }
}

test('E10-TP16 por defecto se conservan las seis señales base (cocina sin cambios)', async () => {
  const f = realtimeFixture('kitchen-test')
  await subscribeToOperationsChanges(f.client, async () => {}, () => {}, f.options)
  assert.equal(f.handlers.length, 6)
  assert.deepEqual([...new Set(f.handlers.map((handler) => handler.filter.table))], ['detalle_pedido', 'pedido', 'mesa'])
  assert.doesNotMatch(kitchenPage, /additionalSignalTables|solicitud_cuenta/)
  assert.doesNotMatch(kitchenService, /additionalSignalTables|solicitud_cuenta/)
})

test('E10-TP16 mozo agrega solicitud_cuenta (INSERT/UPDATE) al mismo canal con topic único y sin polling', async () => {
  const f = realtimeFixture('waiter-e10')
  let refreshes = 0
  await subscribeToOperationsChanges(f.client, async () => { refreshes += 1 }, () => {}, { ...f.options, additionalSignalTables: ['solicitud_cuenta'] })
  assert.equal(f.handlers.length, 8)
  assert.deepEqual(f.handlers.filter((handler) => handler.filter.table === 'solicitud_cuenta').map((handler) => handler.filter.event), ['INSERT', 'UPDATE'])
  assert.equal(f.topics.length, 1)
  assert.match(f.topics[0], /^waiter-e10:\d+$/)
  const before = refreshes
  f.handlers.find((handler) => handler.filter.table === 'solicitud_cuenta' && handler.filter.event === 'INSERT').callback({ new: { ignored: true } })
  await new Promise((resolve) => setImmediate(resolve))
  assert.equal(refreshes, before + 1)
  assert.doesNotMatch(realtimeSource, /setInterval|poll/i)
  assert.match(orderPage, /additionalSignalTables: \['solicitud_cuenta'\]/)
  assert.match(tablesPage, /additionalSignalTables: \['solicitud_cuenta'\]/)
  assert.doesNotMatch(waiterService, /setInterval|poll/i)
})
