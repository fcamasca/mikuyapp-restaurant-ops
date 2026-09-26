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
    channel(name) { assert.match(name, /^waiter-test-signals:\d+$/); return channel },
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

// E7-T12/TH06: cliente que reproduce la semántica de supabase-js — client.channel(topic) devuelve el canal existente
// con ese topic mientras no se complete su salida, y un subscribe() sobre un canal no cerrado no registra callback.
function reusingClient() {
  const channels = new Map()
  let pendingLeaves = []
  return {
    channels,
    completeLeaves() { pendingLeaves.forEach((leave) => leave()); pendingLeaves = [] },
    channel(topic) {
      if (channels.has(topic)) return channels.get(topic)
      const channel = {
        topic, state: 'closed', handlers: [], statusCallback: null,
        on(type, filter, callback) { channel.handlers.push({ filter, callback }); return channel },
        subscribe(callback) {
          if (channel.state !== 'closed') return channel
          channel.state = 'joining'; channel.statusCallback = callback
          queueMicrotask(() => { channel.state = 'joined'; callback('SUBSCRIBED') })
          return channel
        },
      }
      channels.set(topic, channel)
      return channel
    },
    async removeChannel(channel) {
      channel.state = 'leaving'
      await new Promise((resolve) => pendingLeaves.push(resolve))
      channel.state = 'closed'; channels.delete(channel.topic); channel.statusCallback?.('CLOSED')
    },
  }
}

test('E7-T12/TH06 un remontaje antes de que termine la salida del canal anterior sigue recibiendo señales', async () => {
  const client = reusingClient()
  const timers = []
  const options = { channelName: 'waiter-order-45-signals', initialRefresh: false, debounceMs: 1,
    setTimeoutFn(callback) { timers.push(callback); return timers.length }, clearTimeoutFn() {} }
  let secondRefreshes = 0
  // Montaje, desmontaje inmediato (StrictMode / recarga de perfil) y remontaje antes de la confirmación de salida.
  const first = await subscribeToOperationsChanges(client, async () => {}, () => {}, options)
  const stopping = first.stop()
  const second = await subscribeToOperationsChanges(client, async () => { secondRefreshes += 1 }, () => {}, options)
  client.completeLeaves(); await stopping
  await new Promise((resolve) => setImmediate(resolve))
  const alive = [...client.channels.values()]
  assert.equal(alive.length, 1, 'sólo queda el canal del montaje vigente')
  assert.equal(alive[0].state, 'joined')
  assert.match(alive[0].topic, /^waiter-order-45-signals:\d+$/)
  const before = secondRefreshes
  alive[0].handlers.filter((handler) => handler.filter.table === 'mesa' && handler.filter.event === 'UPDATE')
    .forEach((handler) => handler.callback({ new: { id: 'mesa-1', estado: 'LIBRE' } }))
  timers.splice(0).forEach((callback) => callback())
  await new Promise((resolve) => setImmediate(resolve))
  assert.equal(secondRefreshes, before + 1, 'la señal de mesa LIBRE dispara el refetch de la vista vigente')
  const stopSecond = second.stop(); client.completeLeaves(); await stopSecond
  assert.equal(client.channels.size, 0)
})

test('E7-T12/TH06 cada suscripción usa un topic propio con el prefijo del canal', async () => {
  const client = reusingClient()
  const options = { channelName: 'waiter-tables-signals', initialRefresh: false }
  const a = await subscribeToOperationsChanges(client, async () => {}, () => {}, options)
  const b = await subscribeToOperationsChanges(client, async () => {}, () => {}, options)
  const topics = [...client.channels.keys()]
  assert.equal(topics.length, 2)
  assert.notEqual(topics[0], topics[1])
  topics.forEach((topic) => assert.match(topic, /^waiter-tables-signals:\d+$/))
  const stops = [a.stop(), b.stop()]; client.completeLeaves(); await Promise.all(stops)
})
