import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import test from 'node:test'
import { subscribeToOperationsChanges } from '../src/services/operationsRealtimeService.ts'

const tablesPage = readFileSync(new URL('../src/pages/WaiterTablesPage.tsx', import.meta.url), 'utf8')
const orderPage = readFileSync(new URL('../src/pages/WaiterOrderPage.tsx', import.meta.url), 'utf8')
const serviceSource = readFileSync(new URL('../src/services/operationsRealtimeService.ts', import.meta.url), 'utf8')

function fixture() {
  const handlers = []
  const timers = new Map()
  let nextTimer = 0
  let statusHandler
  let removed = false
  const channel = {
    on(type, filter, callback) { handlers.push({ type, filter, callback }); return channel },
    subscribe(callback) { statusHandler = callback; return channel },
  }
  const client = {
    channel(name) { assert.equal(name, 'waiter-test-signals'); return channel },
    async removeChannel(received) { assert.equal(received, channel); removed = true },
  }
  return {
    client,
    handlers,
    options: {
      channelName: 'waiter-test-signals',
      debounceMs: 20,
      setTimeoutFn(callback) { const id = ++nextTimer; timers.set(id, callback); return id },
      clearTimeoutFn(id) { timers.delete(id) },
    },
    emit(table, event) {
      handlers.filter((handler) => handler.filter.table === table && handler.filter.event === event)
        .forEach((handler) => handler.callback({ new: { ignored: true } }))
    },
    status(value) { statusHandler(value) },
    async flush() {
      const callbacks = [...timers.values()]
      timers.clear()
      callbacks.forEach((callback) => callback())
      await new Promise((resolve) => setImmediate(resolve))
    },
    get removed() { return removed },
  }
}

test('H4-T08 suscribe tablero y pedido del mozo a detalle, pedido y mesa', () => {
  assert.match(tablesPage, /subscribeToOperationsChanges/)
  assert.match(orderPage, /subscribeToOperationsChanges/)
  assert.match(tablesPage, /getTableBoard/)
  assert.match(orderPage, /getOrderDetails/)
  assert.match(orderPage, /getOrderReview/)
  assert.match(orderPage, /setDetails\(detailResult\.data\)/)
  assert.match(orderPage, /setReview\(reviewResult\.data\)/)
  assert.match(tablesPage, /initialRefresh: false/)
  assert.match(orderPage, /initialRefresh: false/)
})

test('H4-T08 usa eventos como señales, agrupa repetidos y no hace append de payloads', async () => {
  const f = fixture()
  let refreshes = 0
  const handle = await subscribeToOperationsChanges(f.client, async () => { refreshes += 1 }, () => {}, f.options)
  assert.equal(refreshes, 1)
  assert.equal(f.handlers.length, 6)
  f.emit('detalle_pedido', 'UPDATE')
  f.emit('pedido', 'UPDATE')
  f.emit('mesa', 'UPDATE')
  await f.flush()
  assert.equal(refreshes, 2)
  assert.doesNotMatch(serviceSource, /payload\.(new|old)|\.push\(payload|setInterval|poll/i)
  await handle.stop()
})

test('H4-T08 hace segunda carga, recupera reconexión y limpia el canal', async () => {
  const f = fixture()
  let refreshes = 0
  let errors = 0
  const handle = await subscribeToOperationsChanges(
    f.client,
    async () => { refreshes += 1 },
    () => { errors += 1 },
    f.options,
  )
  f.status('SUBSCRIBED')
  await new Promise((resolve) => setImmediate(resolve))
  assert.equal(refreshes, 2)
  f.status('CHANNEL_ERROR')
  await new Promise((resolve) => setImmediate(resolve))
  assert.equal(errors, 1)
  assert.equal(refreshes, 3)
  await handle.stop()
  assert.equal(f.removed, true)
  f.status('SUBSCRIBED')
  f.emit('mesa', 'UPDATE')
  await f.flush()
  assert.equal(refreshes, 3)
})

test('H4-T08 protege las vistas contra respuestas tardías después del cleanup', () => {
  assert.match(tablesPage, /loadBoard\(false, \(\) => !disposed\)/)
  assert.match(orderPage, /reloadOrderSnapshot\(\(\) => !disposed\)/)
  assert.match(tablesPage, /if \(disposed\) void started\.stop\(\)/)
  assert.match(orderPage, /if \(disposed\) void started\.stop\(\)/)
})
