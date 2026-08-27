import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import test from 'node:test'
import { createKitchenRealtimeService } from '../src/services/kitchenRealtimeService.ts'

const serviceSource = readFileSync(
  new URL('../src/services/kitchenRealtimeService.ts', import.meta.url),
  'utf8',
)
const migrationSource = readFileSync(
  new URL('../supabase/migrations/20260827000900_kitchen_realtime_signals.sql', import.meta.url),
  'utf8',
)

function row(id, estado = 'ENVIADO') {
  return {
    pedido_id: 1,
    pedido_estado: estado,
    mesa_id: 'mesa-1',
    mesa_codigo: 'M01',
    mesa_nombre: 'Mesa 1',
    mesa_estado: 'OCUPADA',
    detalle_id: id,
    producto_id: 'producto-1',
    producto_codigo: 'P01',
    producto_nombre: 'Ceviche',
    cantidad: 1,
    observacion: null,
    estado,
    enviado_en: '2026-08-27T12:00:00Z',
    modificado_en: '2026-08-27T12:00:00Z',
  }
}

function createFixture(responses = [[row(1)], [row(1)], [row(2)]]) {
  const handlers = []
  const timers = new Map()
  let timerId = 0
  let statusHandler
  let rpcCalls = 0
  let removed = false

  const channel = {
    on(type, filter, callback) {
      handlers.push({ type, filter, callback })
      return channel
    },
    subscribe(callback) {
      statusHandler = callback
      return channel
    },
  }

  const client = {
    async rpc(name) {
      assert.equal(name, 'obtener_tablero_cocina')
      const data = responses[Math.min(rpcCalls, responses.length - 1)]
      rpcCalls += 1
      return data instanceof Error
        ? { data: null, error: { message: data.message } }
        : { data, error: null }
    },
    channel(name) {
      assert.equal(name, 'kitchen-board-signals')
      return channel
    },
    async removeChannel(received) {
      assert.equal(received, channel)
      removed = true
    },
  }

  return {
    client,
    options: {
      debounceMs: 50,
      setTimeoutFn(callback) {
        const id = ++timerId
        timers.set(id, callback)
        return id
      },
      clearTimeoutFn(id) { timers.delete(id) },
    },
    handlers,
    emitStatus(status) { statusHandler(status) },
    emit(table, event) {
      for (const handler of handlers) {
        if (handler.filter.table === table && handler.filter.event === event) handler.callback({})
      }
    },
    async flushTimer() {
      const callbacks = [...timers.values()]
      timers.clear()
      callbacks.forEach((callback) => callback())
      await new Promise((resolve) => setImmediate(resolve))
    },
    get rpcCalls() { return rpcCalls },
    get removed() { return removed },
  }
}

test('T05 publica exclusivamente las tres tablas y agrega políticas SELECT de cocina', () => {
  for (const table of ['detalle_pedido', 'pedido', 'mesa']) {
    assert.match(migrationSource, new RegExp(`add table public\\.${table}`))
  }
  assert.match(migrationSource, /drop table %I\.%I/)
  assert.match(migrationSource, /rol_codigo = 'COCINA'/g)
  assert.match(migrationSource, /for select/g)
  assert.doesNotMatch(migrationSource, /for update|for insert|for delete/i)
})

test('T05 carga snapshot, suscribe seis señales y hace segunda carga al SUBSCRIBED', async () => {
  const fixture = createFixture()
  const snapshots = []
  const handle = await createKitchenRealtimeService(fixture.client, fixture.options).start({
    onSnapshot: (rows) => snapshots.push(rows),
    onError: () => assert.fail('No se esperaba error'),
  })

  assert.equal(fixture.rpcCalls, 1)
  assert.equal(fixture.handlers.length, 6)
  assert.deepEqual(
    fixture.handlers.map(({ filter }) => `${filter.table}:${filter.event}`).sort(),
    [
      'detalle_pedido:INSERT', 'detalle_pedido:UPDATE',
      'mesa:INSERT', 'mesa:UPDATE', 'pedido:INSERT', 'pedido:UPDATE',
    ],
  )

  fixture.emitStatus('SUBSCRIBED')
  await new Promise((resolve) => setImmediate(resolve))
  assert.equal(fixture.rpcCalls, 2)
  assert.equal(snapshots.length, 2)
  await handle.stop()
  assert.equal(fixture.removed, true)
})

test('T05 agrupa eventos repetidos/fuera de orden y reemplaza con snapshot autoritativo', async () => {
  const fixture = createFixture([[row(1)], [row(2, 'RECIBIDO_COCINA')]])
  const snapshots = []
  const handle = await createKitchenRealtimeService(fixture.client, fixture.options).start({
    onSnapshot: (rows) => snapshots.push(rows),
    onError: () => assert.fail('No se esperaba error'),
  })

  fixture.emit('pedido', 'UPDATE')
  fixture.emit('detalle_pedido', 'UPDATE')
  fixture.emit('detalle_pedido', 'UPDATE')
  fixture.emit('mesa', 'INSERT')
  assert.equal(fixture.rpcCalls, 1)
  await fixture.flushTimer()

  assert.equal(fixture.rpcCalls, 2)
  assert.deepEqual(snapshots.at(-1), [row(2, 'RECIBIDO_COCINA')])
  assert.equal(snapshots.at(-1).some((item) => item.detalle_id === 1), false)
  await handle.stop()
})

test('T05 resincroniza en error y otra vez al reconectar', async () => {
  const fixture = createFixture([[row(1)], [row(2)], [row(3)]])
  const snapshots = []
  const errors = []
  const handle = await createKitchenRealtimeService(fixture.client, fixture.options).start({
    onSnapshot: (rows) => snapshots.push(rows),
    onError: (message) => errors.push(message),
  })

  fixture.emitStatus('CHANNEL_ERROR')
  await new Promise((resolve) => setImmediate(resolve))
  assert.equal(fixture.rpcCalls, 2)
  assert.equal(errors.length, 1)

  fixture.emitStatus('SUBSCRIBED')
  await new Promise((resolve) => setImmediate(resolve))
  assert.equal(fixture.rpcCalls, 3)
  assert.deepEqual(snapshots.at(-1), [row(3)])
  await handle.stop()
})

test('T05 no usa polling ni construye el tablero mediante append de eventos', () => {
  assert.doesNotMatch(serviceSource, /setInterval|poll/i)
  assert.match(serviceSource, /obtener_tablero_cocina/)
  assert.match(serviceSource, /callbacks\.onSnapshot/)
  assert.doesNotMatch(serviceSource, /payload\.(new|old)|\.push\(payload/)
})

test('T07 incorpora un detalle nuevo reemplazando el snapshot sin duplicar filas', async () => {
  const fixture = createFixture([
    [row(1)],
    [row(1), row(2)],
  ])
  const snapshots = []
  const handle = await createKitchenRealtimeService(fixture.client, fixture.options).start({
    onSnapshot: (rows) => snapshots.push(rows),
    onError: () => assert.fail('No se esperaba error'),
  })

  fixture.emit('detalle_pedido', 'INSERT')
  fixture.emit('detalle_pedido', 'INSERT')
  await fixture.flushTimer()

  assert.equal(fixture.rpcCalls, 2)
  assert.deepEqual(snapshots.at(-1).map((item) => item.detalle_id), [1, 2])
  assert.equal(new Set(snapshots.at(-1).map((item) => item.detalle_id)).size, 2)
  await handle.stop()
})

test('T07 refleja UPDATE repetido o fuera de orden desde el snapshot ganador', async () => {
  const fixture = createFixture([
    [row(1, 'ENVIADO')],
    [row(1, 'RECIBIDO_COCINA')],
  ])
  const snapshots = []
  const handle = await createKitchenRealtimeService(fixture.client, fixture.options).start({
    onSnapshot: (rows) => snapshots.push(rows),
    onError: () => assert.fail('No se esperaba error'),
  })

  fixture.emit('mesa', 'UPDATE')
  fixture.emit('pedido', 'UPDATE')
  fixture.emit('detalle_pedido', 'UPDATE')
  await fixture.flushTimer()

  assert.equal(fixture.rpcCalls, 2)
  assert.equal(snapshots.at(-1)[0].estado, 'RECIBIDO_COCINA')
  await handle.stop()
})

test('T07 cleanup cancela canal y descarta snapshot o status tardíos', async () => {
  let resolveDeferred
  let rpcCalls = 0
  let statusHandler
  let removed = false
  const deferred = new Promise((resolve) => { resolveDeferred = resolve })
  const channel = {
    on() { return channel },
    subscribe(callback) { statusHandler = callback; return channel },
  }
  const client = {
    async rpc() {
      rpcCalls += 1
      if (rpcCalls === 1) return { data: [row(1)], error: null }
      return deferred
    },
    channel() { return channel },
    async removeChannel() { removed = true },
  }
  const snapshots = []
  const errors = []
  const handle = await createKitchenRealtimeService(client).start({
    onSnapshot: (rows) => snapshots.push(rows),
    onError: (message) => errors.push(message),
  })

  const lateRefresh = handle.resync()
  await handle.stop()
  resolveDeferred({ data: [row(2)], error: null })
  await lateRefresh
  statusHandler('CHANNEL_ERROR')
  await new Promise((resolve) => setImmediate(resolve))

  assert.equal(removed, true)
  assert.equal(snapshots.length, 1)
  assert.equal(errors.length, 0)
  assert.equal(rpcCalls, 2)
})
