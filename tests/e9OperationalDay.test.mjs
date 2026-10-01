import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import test from 'node:test'
import {
  LOCAL_CLOSED_MESSAGE,
  createOperationalDayService,
  isLocalClosedError,
  mapCurrentOperationalDay,
  subscribeToOperationalDay,
} from '../src/services/operationalDayService.ts'
import { createWaiterOrderService } from '../src/services/waiterOrderService.ts'
import { createCashierService } from '../src/services/cashierService.ts'

const read = (path) => readFileSync(new URL(path, import.meta.url), 'utf8')
const app = read('../src/App.tsx')
const gate = read('../src/components/OperationalDayGate.tsx')
const service = read('../src/services/operationalDayService.ts')
const realtimeBase = read('../src/services/operationsRealtimeService.ts')
const cashier = read('../src/pages/CashierPage.tsx')
const waiterTables = read('../src/pages/WaiterTablesPage.tsx')
const kitchenPage = read('../src/pages/KitchenBoardPage.tsx')

function context(role = 'MOZO') {
  return {
    profile: { id: 'user-own', local_id: 'local-own', rol_id: 1, nombre: 'Usuario', activo: true },
    role: { id: 1, codigo: role, activo: true },
    local: { id: 'local-own', nombre: 'Cebichería', activo: true },
  }
}

function rpcClient(responses) {
  const calls = []
  return {
    calls,
    client: {
      async rpc(name, args) {
        calls.push({ name, args })
        const response = responses[name]
        if (response instanceof Error) throw response
        return response ?? { data: null, error: null }
      },
    },
  }
}

const currentRow = {
  jornada_operativa_id: 7, identificacion: 'Jornada 2026-10-01 (2)', fecha_operativa: '2026-10-01', numero: 2,
  abierta_en: '2026-10-01T14:00:00Z', abierta_por_nombre: 'Ana Admin', servidor_ahora: '2026-10-01T15:00:00Z',
}

// ===== E9-T04: servicio (TP19, parte de servicio)

test('E9-T04 lee el estado del local sólo por RPC, sin enviar local ni rol; cero filas = local cerrado', async () => {
  const open = rpcClient({ rpc_obtener_jornada_operativa_actual: { data: [currentRow], error: null } })
  assert.deepEqual(await createOperationalDayService(open.client).getCurrent(), {
    ok: true,
    data: { id: 7, identificacion: 'Jornada 2026-10-01 (2)', fechaOperativa: '2026-10-01', numero: 2, abiertaEn: '2026-10-01T14:00:00Z', abiertaPorNombre: 'Ana Admin', servidorAhora: '2026-10-01T15:00:00Z' },
  })
  assert.deepEqual(open.calls, [{ name: 'rpc_obtener_jornada_operativa_actual', args: undefined }])
  const closed = rpcClient({ rpc_obtener_jornada_operativa_actual: { data: [], error: null } })
  assert.deepEqual(await createOperationalDayService(closed.client).getCurrent(), { ok: true, data: null })
  assert.equal(mapCurrentOperationalDay(null), null)
})

test('E9-T04 un error de lectura no se presenta como local abierto ni cerrado (fail-closed)', async () => {
  const failing = rpcClient({ rpc_obtener_jornada_operativa_actual: { data: null, error: { code: '08006', message: 'red' } } })
  const result = await createOperationalDayService(failing.client).getCurrent()
  assert.equal(result.ok, false)
  assert.equal(result.error.kind, 'operation-error')
  const throwing = rpcClient({ rpc_obtener_jornada_operativa_actual: new Error('offline') })
  assert.equal((await createOperationalDayService(throwing.client).getCurrent()).ok, false)
})

test('E9-T04 reconoce el PT409 de local cerrado sólo con el mensaje exacto de PostgreSQL', () => {
  assert.equal(LOCAL_CLOSED_MESSAGE, 'Local cerrado — el sistema no se encuentra aperturado')
  assert.equal(isLocalClosedError({ code: 'PT409', message: LOCAL_CLOSED_MESSAGE }), true)
  assert.equal(isLocalClosedError({ code: 'PT409', message: 'La sesión ya no está abierta' }), false)
  assert.equal(isLocalClosedError({ code: '42501', message: LOCAL_CLOSED_MESSAGE }), false)
  assert.equal(isLocalClosedError(null), false)
})

// ===== E9-T04: Realtime (TP21, parte Node)

function fakeRealtime() {
  const channels = []
  return {
    channels,
    removed: [],
    channel(topic) {
      const channel = { topic, bindings: [], status: null, on(type, filter, handler) { this.bindings.push({ type, filter, handler }); return this }, subscribe(callback) { this.status = callback; return this } }
      channels.push(channel)
      return channel
    },
    async removeChannel(channel) { this.removed.push(channel.topic) },
  }
}

function manualTimers() {
  const pending = new Map(); let next = 1
  return {
    setTimeoutFn: (fn) => { const id = next++; pending.set(id, fn); return id },
    clearTimeoutFn: (id) => { pending.delete(id) },
    flush: () => { const fns = [...pending.values()]; pending.clear(); fns.forEach((fn) => fn()) },
  }
}

test('E9-T04 la suscripción escucha sólo INSERT/UPDATE de jornada_operativa con topic propio por suscripción', async () => {
  const client = fakeRealtime()
  const first = await subscribeToOperationalDay(client, async () => {}, () => {}, { channelName: 'operational-day-signals' })
  const second = await subscribeToOperationalDay(client, async () => {}, () => {}, { channelName: 'operational-day-signals' })
  assert.notEqual(client.channels[0].topic, client.channels[1].topic)
  assert.match(client.channels[0].topic, /^operational-day-signals:\d+$/)
  assert.deepEqual(client.channels[0].bindings.map((b) => [b.type, b.filter.event, b.filter.schema, b.filter.table]), [
    ['postgres_changes', 'INSERT', 'public', 'jornada_operativa'],
    ['postgres_changes', 'UPDATE', 'public', 'jornada_operativa'],
  ])
  await first.stop(); await second.stop()
  assert.deepEqual(client.removed, [client.channels[0].topic, client.channels[1].topic])
})

test('E9-T04 las señales duplicadas se coalescen en una relectura; SUBSCRIBED y errores relevan el estado', async () => {
  const client = fakeRealtime(); const timers = manualTimers()
  let refreshes = 0; let errors = 0
  await subscribeToOperationalDay(client, async () => { refreshes += 1 }, () => { errors += 1 }, { channelName: 'gate', ...timers })
  const channel = client.channels[0]
  channel.bindings[0].handler({ new: { estado: 'ABIERTA' } })
  channel.bindings[1].handler({ new: { estado: 'CERRADA' } })
  channel.bindings[1].handler({})
  timers.flush(); await Promise.resolve(); await Promise.resolve()
  assert.equal(refreshes, 1)
  channel.status('SUBSCRIBED'); await Promise.resolve()
  assert.equal(refreshes, 2)
  channel.status('CHANNEL_ERROR'); await Promise.resolve()
  assert.equal(errors, 1)
  assert.equal(refreshes, 3)
})

test('E9-T04 no modifica ni refactoriza operationsRealtimeService; reutiliza subscriptionTopic y no hace polling', () => {
  assert.match(service, /import \{ subscriptionTopic \} from '\.\/operationsRealtimeService\.ts'/)
  assert.doesNotMatch(service + gate, /setInterval/)
  assert.match(realtimeBase, /const signalTables = \['detalle_pedido', 'pedido', 'mesa'\] as const/)
  assert.match(realtimeBase, /export type AdditionalSignalTable = 'solicitud_cuenta'/)
  assert.doesNotMatch(realtimeBase, /jornada/)
  assert.doesNotMatch(kitchenPage, /jornada|OperationalDay/)
})

// ===== E9-T04: gate y pantalla de local cerrado (TP19)

test('E9-T04 la pantalla de local cerrado muestra el texto exacto, el local y Cerrar sesión, sin acciones operativas', () => {
  assert.match(gate, /\{LOCAL_CLOSED_MESSAGE\}/)
  assert.match(gate, /context\.local\.nombre/)
  assert.match(gate, /'Cerrar sesión'/)
  assert.match(gate, /'Actualizar'/)
  assert.match(gate, /AuthenticatedUserMenu context=\{context\}/)
  const closedScreen = gate.slice(gate.indexOf('export function LocalClosedScreen'), gate.indexOf('function OperationalDayStatusScreen'))
  assert.doesNotMatch(closedScreen, /Mesa|Pedido|Cobrar|Cocina|Ventas|Verificación técnica/)
  assert.match(closedScreen, /min-h-11/)
  assert.match(closedScreen, /overflow-x-hidden/)
})

test('E9-T04 fail-closed: cargando o con error no muestra la pantalla operativa; Reintentar y Cerrar sesión', () => {
  assert.match(gate, /if \(state\.status === 'open'\) \{\s*return <OperationalDayContext\.Provider value=\{value\}>\{children\}<\/OperationalDayContext\.Provider>/)
  assert.match(gate, /Verificando el estado del local…/)
  assert.match(gate, /No pudimos verificar el estado del local/)
  assert.match(gate, />Reintentar</)
  assert.equal((gate.match(/\{children\}/g) ?? []).length, 1)
  assert.match(gate, /if \(!result\.ok\) setState\(\{ status: 'error', message: result\.error\.message \}\)/)
})

test('E9-T04 / DC-11: todas las rutas de MOZO, COCINA y CAJA pasan por el gate; ADMIN, /login y /403 no', () => {
  assert.match(app, /const gated = \(node: ReactNode\): ReactNode => \(role === 'ADMINISTRADOR' \|\| !profileContext\.context/)
  for (const page of ['<SalesPage context={profileContext.context} isSigningOut={isSigningOut} onBack', '<WaiterTablesPage', '<KitchenBoardPage', '<CashierPage', '<WaiterOrderPage']) {
    const index = app.indexOf(page)
    assert.notEqual(index, -1, page)
    assert.match(app.slice(Math.max(0, index - 40), index), /gated\(\s*$/, `${page} sin gate`)
  }
  const technical = app.slice(app.indexOf("resolution.pathname === '/tecnica'"))
  assert.match(technical, /return gated\(\s*<>/)
  assert.match(app, /<AdminShell active=\{resolution\.pathname\}/)
  assert.doesNotMatch(app.slice(app.indexOf("if (resolution.pathname.startsWith('/admin/'))"), app.indexOf("if (resolution.pathname === '/ventas')")), /gated\(/)
  assert.doesNotMatch(app.slice(app.indexOf('const isForbidden')), /gated\(/)
  assert.match(app, /return <LoginPage \/>/)
})

// ===== E9-T04: Caja y mozo (resync ante PT409 e identificación)

test('E9-T04 Caja muestra la identificación de la jornada y resincroniza ante local cerrado', () => {
  assert.match(cashier, /const operationalDay = useOperationalDay\(\)/)
  assert.match(cashier, /\{operationalDay\.jornada\.identificacion\}/)
  assert.match(cashier, /if \(!r\.ok && r\.error\?\.message === LOCAL_CLOSED_MESSAGE\) void operationalDay\.resync\(\)/)
})

test('E9-T04 la apertura de caja rechazada por local cerrado conserva el mensaje del servidor', async () => {
  const fixture = rpcClient({ rpc_abrir_sesion_caja: { data: null, error: { code: 'PT409', message: LOCAL_CLOSED_MESSAGE } } })
  const result = await createCashierService(fixture.client).openSession(context('CAJA'), 'caja-1', 0, 'key-1')
  assert.deepEqual(result, { ok: false, error: { kind: 'conflict', message: LOCAL_CLOSED_MESSAGE } })
  const other = rpcClient({ rpc_abrir_sesion_caja: { data: null, error: { code: 'PT409', message: 'La sesión cambió; reintente la solicitud' } } })
  assert.equal((await createCashierService(other.client).openSession(context('CAJA'), 'caja-1', 0, 'key-2')).error.message,
    'La operación cambió o no pudo completarse. Recarga los datos.')
})

test('E9-T04 abrir pedido con local cerrado informa el mensaje del servidor y la vista resincroniza el gate', async () => {
  const fixture = rpcClient({ crear_o_recuperar_pedido_mesa: { data: null, error: { code: 'PT409', message: LOCAL_CLOSED_MESSAGE } } })
  const result = await createWaiterOrderService(fixture.client).createOrRecoverOrder(context('MOZO'), 'mesa-1')
  assert.deepEqual(result, { ok: false, error: { kind: 'operation-error', message: LOCAL_CLOSED_MESSAGE, recoverable: true } })
  assert.deepEqual(fixture.calls, [{ name: 'crear_o_recuperar_pedido_mesa', args: { p_mesa_id: 'mesa-1' } }])
  const generic = rpcClient({ crear_o_recuperar_pedido_mesa: { data: null, error: { code: '55000', message: 'x' } } })
  assert.equal((await createWaiterOrderService(generic.client).createOrRecoverOrder(context('MOZO'), 'mesa-1')).error.message,
    'No pudimos abrir el pedido de la mesa. Intenta nuevamente.')
  assert.match(waiterTables, /if \(result\.error\.message === LOCAL_CLOSED_MESSAGE\) void operationalDay\.resync\(\)/)
})
