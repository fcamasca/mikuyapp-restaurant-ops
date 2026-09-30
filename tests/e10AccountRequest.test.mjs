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

// ===== E10-TP18: Caja (servicio, orden, huella DH-02 B y pantalla)

const cashierPage = readFileSync(new URL('../src/pages/CashierPage.tsx', import.meta.url), 'utf8')
const cashierSource = readFileSync(new URL('../src/services/cashierService.ts', import.meta.url), 'utf8')
const { billRequestElapsedMinutes, cashierDraftFingerprint, createCashierService, groupCashierOrders, newBillRequests, sortCashierOrders } =
  await import('../src/services/cashierService.ts')

const cashierRow = (x = {}) => ({
  pedido_id: 10, pedido_estado: 'ENTREGADO', pedido_creado_en: '2026-09-30T18:00:00Z', mesa_id: 'm1', mesa_codigo: 'M1',
  mesa_nombre: 'Mesa 1', mesa_estado: 'PENDIENTE_PAGO', detalle_id: 1, producto_id: 'p1', producto_nombre: 'Ceviche',
  cantidad: 1, precio_unitario: '30', importe_linea: '30', total_pedido: '30', subtotal: '30', descuento: '0',
  total_neto: '30', pagado_acumulado: '0', saldo: '30', solicitud_cuenta_id: null, cuenta_solicitada_en: null,
  cuenta_solicitada_por_nombre: null, servidor_ahora: '2026-09-30T20:10:00Z', ...x,
})

test('E10-T05 la lectura de Caja mapea la solicitud y la hora de servidor sin cambiar importes', async () => {
  const [o] = groupCashierOrders([cashierRow({ solicitud_cuenta_id: 5, cuenta_solicitada_en: '2026-09-30T20:00:00Z', cuenta_solicitada_por_nombre: 'Ana' })])
  assert.deepEqual([o.billRequestId, o.billRequestedAt, o.billRequestedBy, o.serverNow], [5, '2026-09-30T20:00:00Z', 'Ana', '2026-09-30T20:10:00Z'])
  assert.deepEqual([o.subtotal, o.netTotal, o.paid, o.balance], [30, 30, 0, 30])
  const [legacy] = groupCashierOrders([{ ...cashierRow(), solicitud_cuenta_id: undefined, cuenta_solicitada_en: undefined, cuenta_solicitada_por_nombre: undefined, servidor_ahora: undefined }])
  assert.deepEqual([legacy.billRequestId, legacy.billRequestedAt, legacy.billRequestedBy, legacy.serverNow], [null, null, null, null])
  const calls = []
  const service = createCashierService({ async rpc(name) { calls.push(name); return { data: [cashierRow()], error: null } } })
  const result = await service.getPendingOrders({ profile: {}, role: { codigo: 'CAJA' }, local: { id: 'l1' } })
  assert.equal(result.ok, true)
  assert.deepEqual(calls, ['obtener_pedidos_pendientes_pago_caja'])
})

test('E10-T05 prioriza cuentas solicitadas por antigüedad y conserva el orden E1 del resto', () => {
  const orders = groupCashierOrders([
    cashierRow({ pedido_id: 1, pedido_creado_en: '2026-09-30T17:00:00Z' }),
    cashierRow({ pedido_id: 2, pedido_creado_en: '2026-09-30T19:00:00Z', solicitud_cuenta_id: 20, cuenta_solicitada_en: '2026-09-30T20:05:00Z' }),
    cashierRow({ pedido_id: 3, pedido_creado_en: '2026-09-30T18:00:00Z', solicitud_cuenta_id: 30, cuenta_solicitada_en: '2026-09-30T20:01:00Z' }),
    cashierRow({ pedido_id: 4, pedido_creado_en: '2026-09-30T16:00:00Z' }),
  ])
  assert.deepEqual(orders.map((o) => o.orderId), [3, 2, 4, 1])
  assert.deepEqual(sortCashierOrders([...orders].reverse()).map((o) => o.orderId), [3, 2, 4, 1])
})

test('E10-T05 DH-02 B: la huella sólo cambia con estado, total, descuento, pagado o saldo del pedido seleccionado', () => {
  const base = groupCashierOrders([cashierRow({ pedido_id: 1 }), cashierRow({ pedido_id: 2, mesa_codigo: 'M2' })])
  const fp = cashierDraftFingerprint(base, 1)
  // Llega o se cierra la solicitud de OTRO pedido: misma huella del seleccionado.
  const otherRequest = groupCashierOrders([cashierRow({ pedido_id: 1 }), cashierRow({ pedido_id: 2, mesa_codigo: 'M2', solicitud_cuenta_id: 9, cuenta_solicitada_en: '2026-09-30T20:00:00Z' })])
  assert.equal(cashierDraftFingerprint(otherRequest, 1), fp)
  const otherGone = groupCashierOrders([cashierRow({ pedido_id: 1 })])
  assert.equal(cashierDraftFingerprint(otherGone, 1), fp)
  // La solicitud del propio pedido no altera importes: tampoco invalida.
  const ownRequest = groupCashierOrders([cashierRow({ pedido_id: 1, solicitud_cuenta_id: 3, cuenta_solicitada_en: '2026-09-30T20:00:00Z' })])
  assert.equal(cashierDraftFingerprint(ownRequest, 1), fp)
  // Cambios autoritativos del seleccionado o su desaparición: invalida.
  for (const change of [{ saldo: '20', pagado_acumulado: '10' }, { descuento: '5', total_neto: '25', saldo: '25' }, { subtotal: '38', total_neto: '38', saldo: '38' }]) {
    assert.notEqual(cashierDraftFingerprint(groupCashierOrders([cashierRow({ pedido_id: 1, ...change })]), 1), fp)
  }
  assert.equal(cashierDraftFingerprint(groupCashierOrders([cashierRow({ pedido_id: 2 })]), 1), null)
})

test('E10-T05 aviso sólo para solicitudes nuevas y tiempo transcurrido con reloj de servidor', () => {
  const before = groupCashierOrders([cashierRow({ pedido_id: 1, solicitud_cuenta_id: 3, cuenta_solicitada_en: '2026-09-30T20:00:00Z' })])
  const after = groupCashierOrders([
    cashierRow({ pedido_id: 1, solicitud_cuenta_id: 3, cuenta_solicitada_en: '2026-09-30T20:00:00Z' }),
    cashierRow({ pedido_id: 2, mesa_codigo: 'M2', solicitud_cuenta_id: 4, cuenta_solicitada_en: '2026-09-30T20:07:00Z' }),
    cashierRow({ pedido_id: 5, mesa_codigo: 'M5' }),
  ])
  assert.deepEqual(newBillRequests(before, after).map((o) => o.tableCode), ['M2'])
  assert.deepEqual(newBillRequests(after, after), [])
  const local = Date.parse('2026-09-30T20:00:00Z')
  // Reloj local 10 min atrasado respecto del servidor: la espera usa el desfase medido.
  assert.equal(billRequestElapsedMinutes('2026-09-30T20:05:00Z', 10 * 60000, local), 5)
  assert.equal(billRequestElapsedMinutes('2026-09-30T20:30:00Z', 0, local), 0)
})

test('E10-T05 CashierPage: Realtime con solicitud_cuenta conserva el borrador salvo cambio del seleccionado', () => {
  assert.match(cashierPage, /\(\) => refresh\(false, \(\) => !disposed, true\)/)
  assert.match(cashierPage, /channelName: "cashier-orders-signals", initialRefresh: false, additionalSignalTables: \["solicitud_cuenta"\]/)
  const refreshBody = cashierPage.slice(cashierPage.indexOf('const refresh = useCallback'), cashierPage.indexOf('useEffect(() => {\n    void refresh();'))
  assert.match(refreshBody, /preserveDraft = false/)
  assert.match(refreshBody, /cashierDraftFingerprint\(previousOrders, selectedIdRef\.current\) ===\s*cashierDraftFingerprint\(o\.data, selectedIdRef\.current\)/)
  assert.match(refreshBody, /preserveDraft &&\s*o\.ok &&\s*previousOrders !== null/)
  assert.match(refreshBody, /if \(!draftUnchanged\) clearPaymentOptions\(\);/)
  // Mutaciones propias y cargas manuales conservan la invalidación E1.
  assert.match(cashierPage, /void refresh\(false\)/)
  assert.match(cashierPage, /El saldo o el pedido cambió\. Revisa los datos antes de confirmar nuevamente\./)
})

test('E10-T05 CashierPage: prioridad visible, tiempo, mozo, contador y aviso accesible sin acciones nuevas de cobro', () => {
  assert.match(cashierPage, /\{requestedBills\} \{requestedBills === 1 \? "cuenta solicitada" : "cuentas solicitadas"\}/)
  assert.match(cashierPage, /Cuenta solicitada · \{billElapsed\(x\.billRequestedAt\)\}/)
  assert.match(cashierPage, /Cuenta solicitada por \{selected\.billRequestedBy \?\? "el mozo"\} a las/)
  assert.match(cashierPage, /<p aria-live="polite" className="sr-only" role="status">\{billAnnouncement\}<\/p>/)
  assert.match(cashierPage, /Mesa \$\{x\.tableCode\} pidió la cuenta\./)
  assert.match(cashierPage, /order\.billRequestedAt && <span aria-hidden="true"/)
  // Reloj de pantalla: no llama al servicio ni a Supabase.
  const tick = cashierPage.slice(cashierPage.indexOf('const timer = setInterval'), cashierPage.indexOf('return () => clearInterval(timer)'))
  assert.match(tick, /setDisplayNowMs\(Date\.now\(\)\)/)
  assert.doesNotMatch(tick, /service|refresh|rpc/)
  assert.doesNotMatch(cashierPage, /rpc_solicitar_cuenta_pedido|Tomar solicitud|Atender solicitud/)
  assert.doesNotMatch(cashierSource, /rpc_solicitar_cuenta_pedido|solicitud_cuenta"/)
})
