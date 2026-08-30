import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import test from 'node:test'
import { subscribeToOperationsChanges } from '../src/services/operationsRealtimeService.ts'

const cashierPage = readFileSync(new URL('../src/pages/CashierPage.tsx', import.meta.url), 'utf8')
const waiterPage = readFileSync(new URL('../src/pages/WaiterTablesPage.tsx', import.meta.url), 'utf8')
const realtimeSource = readFileSync(new URL('../src/services/operationsRealtimeService.ts', import.meta.url), 'utf8')

function fixture() {
  const handlers = []
  const timers = new Map()
  let statusHandler
  let timerId = 0
  let removed = false
  const channel = {
    on(type, filter, callback) { handlers.push({ type, filter, callback }); return channel },
    subscribe(callback) { statusHandler = callback; return channel },
  }
  return {
    client: { channel(name) { assert.equal(name, 'h5-convergence-signals'); return channel }, async removeChannel(received) { assert.equal(received, channel); removed = true } },
    options: { channelName: 'h5-convergence-signals', debounceMs: 10, setTimeoutFn(callback) { const id = ++timerId; timers.set(id, callback); return id }, clearTimeoutFn(id) { timers.delete(id) } },
    emit(table, event = 'UPDATE') { handlers.filter((handler) => handler.filter.table === table && handler.filter.event === event).forEach((handler) => handler.callback({ new: { ignored: true } })) },
    status(value) { statusHandler(value) },
    async flush() { const callbacks = [...timers.values()]; timers.clear(); callbacks.forEach((callback) => callback()); await new Promise((resolve) => setImmediate(resolve)) },
    get removed() { return removed },
  }
}

test('H5-T06 caja reutiliza infraestructura H4 y descarta respuestas tardías', () => {
  assert.match(cashierPage, /subscribeToOperationsChanges/)
  assert.match(cashierPage, /channelName: 'cashier-orders-signals'/)
  assert.match(cashierPage, /initialRefresh: false/)
  assert.match(cashierPage, /load\(false, \(\) => !disposed\)/)
  assert.match(cashierPage, /if \(!isCurrent\(\)\) return null/)
  assert.match(cashierPage, /if \(disposed\) void started\.stop\(\)/)
  assert.match(cashierPage, /if \(handle\) void handle\.stop\(\)/)
  assert.doesNotMatch(cashierPage, /setInterval|poll/i)
})

test('H5-T06 señales duplicadas convergen caja de vacío a ENTREGADO y luego a vacío', async () => {
  const f = fixture()
  const snapshots = [[], [{ orderId: 50, orderStatus: 'ENTREGADO', tableStatus: 'PENDIENTE_PAGO' }], []]
  const observed = []
  let reads = 0
  const handle = await subscribeToOperationsChanges(f.client, async () => { observed.push(snapshots[Math.min(reads++, snapshots.length - 1)]) }, () => {}, f.options)
  f.emit('pedido'); f.emit('pedido'); f.emit('mesa')
  await f.flush()
  assert.deepEqual(observed.at(-1), [{ orderId: 50, orderStatus: 'ENTREGADO', tableStatus: 'PENDIENTE_PAGO' }])
  f.emit('pedido'); f.emit('pedido')
  await f.flush()
  assert.deepEqual(observed.at(-1), [])
  assert.equal(observed.length, 3)
  await handle.stop()
})

test('H5-T06 mozo converge PEDIDO_LISTO a PENDIENTE_PAGO y luego LIBRE por snapshots', async () => {
  assert.match(waiterPage, /subscribeToOperationsChanges/)
  const f = fixture()
  const snapshots = ['PEDIDO_LISTO', 'PENDIENTE_PAGO', 'LIBRE']
  const observed = []
  let reads = 0
  const handle = await subscribeToOperationsChanges(f.client, async () => { observed.push(snapshots[Math.min(reads++, 2)]) }, () => {}, f.options)
  f.emit('mesa'); await f.flush()
  f.emit('mesa'); await f.flush()
  assert.deepEqual(observed, ['PEDIDO_LISTO', 'PENDIENTE_PAGO', 'LIBRE'])
  await handle.stop()
})

test('H5-T06 reconecta, resincroniza, limpia y nunca consume payload como verdad', async () => {
  const f = fixture()
  let reads = 0
  let errors = 0
  const handle = await subscribeToOperationsChanges(f.client, async () => { reads += 1 }, () => { errors += 1 }, f.options)
  f.status('CHANNEL_ERROR')
  await new Promise((resolve) => setImmediate(resolve))
  f.status('SUBSCRIBED')
  await new Promise((resolve) => setImmediate(resolve))
  assert.equal(errors, 1)
  assert.equal(reads, 3)
  await handle.stop()
  assert.equal(f.removed, true)
  f.emit('pedido'); await f.flush()
  assert.equal(reads, 3)
  assert.doesNotMatch(realtimeSource, /payload\.(new|old)|\.push\(payload|setInterval|poll/i)
})
