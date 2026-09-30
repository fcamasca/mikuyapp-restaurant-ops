// E10 — Verificación con Supabase real (DEV compartido) de lo que el entorno local no puede cubrir:
//   TP13 lectura del mozo vía PostgREST real; TP15 entrega Realtime mozo <-> caja con segundo mozo/caja,
//   cierre y reapertura; TP16 remontaje, reconexión y ausencia de polling; observación real de HZ-02.
// Uso (Windows, raíz del repo, con las migraciones E10 ya aplicadas en DEV y una caja ABIERTA en DEV):
//   node --env-file=.env.local --experimental-strip-types scripts/e10_dev_verificacion.mjs
// Usa los usuarios de prueba H2_MOZO/H2_COCINA/H2_CAJA de .env.local y los servicios reales del frontend.
// ATENCIÓN: en TRANSITIONING este proyecto también atiende Production. El script crea dos pedidos de prueba en
// dos mesas LIBRES y los cobra (importe de un producto cada uno, marcado "E10-DEV") para dejar las mesas LIBRES.
// Nunca se ejecuta contra PROD: exige ambiente lógico DEV y el ref DEV esperado. Escribe e10-dev-verificacion.log.
import { appendFileSync, writeFileSync } from 'node:fs'
import { randomUUID } from 'node:crypto'
import { createClient } from '@supabase/supabase-js'
import { readLocalLinkedProjectRef, validateEnvironmentConfiguration, maskProjectRef } from './environmentGuard.mjs'
import { createWaiterOrderService } from '../src/services/waiterOrderService.ts'
import { createKitchenRealtimeService } from '../src/services/kitchenRealtimeService.ts'
import { createCashierService } from '../src/services/cashierService.ts'
import { subscribeToOperationsChanges } from '../src/services/operationsRealtimeService.ts'

const LOG = 'e10-dev-verificacion.log'
writeFileSync(LOG, '')
const log = (line) => { const text = `[${new Date().toISOString()}] ${line}`; console.log(text); appendFileSync(LOG, text + '\n') }
const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms))
const results = []
const check = (id, ok, detail) => { results.push({ id, ok, detail }); log(`${ok ? 'PASS' : 'FAIL'} ${id}: ${detail}`) }
const unwrap = (r, label) => { if (!r.ok) throw new Error(`${label}: ${r.error.message}`); return r.data }
const must = (r, label) => { if (r.error) throw new Error(`${label}: ${r.error.code ?? ''} ${r.error.message}`); return r.data }

// ===== Guardia de ambiente: sólo DEV
const env = validateEnvironmentConfiguration(process.env, await readLocalLinkedProjectRef())
if (env.logicalEnvironment !== 'DEV' || !process.env.MIKUY_DEV_SUPABASE_PROJECT_REF || env.effectiveRef !== process.env.MIKUY_DEV_SUPABASE_PROJECT_REF.trim()) {
  throw new Error('Sólo se ejecuta contra DEV (ambiente lógico DEV y ref DEV esperado).')
}
log(`Ambiente: state=${env.state} logical=${env.logicalEnvironment} ref=${maskProjectRef(env.effectiveRef)}`)
const url = process.env.VITE_SUPABASE_URL.trim()
const key = process.env.VITE_SUPABASE_PUBLISHABLE_KEY.trim()

// Cliente con contador de peticiones REST (para verificar ausencia de polling).
let restRequests = 0
const countingFetch = (...args) => { if (String(args[0]).includes('/rest/v1/')) restRequests += 1; return fetch(...args) }
async function device(email, password, label) {
  const client = createClient(url, key, { auth: { persistSession: false, autoRefreshToken: false }, global: { fetch: countingFetch } })
  const session = must(await client.auth.signInWithPassword({ email, password }), `login ${label}`)
  const profile = must(await client.from('perfil_usuario').select('id,local_id,nombre').eq('id', session.user.id).single(), `perfil ${label}`)
  return { client, label, id: session.user.id, profile }
}
const ctx = (d, codigo) => ({ profile: { id: d.id, local_id: d.profile.local_id, rol_id: 0, nombre: d.profile.nombre, activo: true },
  role: { id: 0, codigo, activo: true }, local: { id: d.profile.local_id, nombre: 'DEV', activo: true } })

const e = process.env
const mozoA = await device(e.H2_MOZO_EMAIL, e.H2_MOZO_PASSWORD, 'mozo-dispositivo-1')
const mozoB = await device(e.H2_MOZO_EMAIL, e.H2_MOZO_PASSWORD, 'mozo-dispositivo-2')
const cajaA = await device(e.H2_CAJA_EMAIL, e.H2_CAJA_PASSWORD, 'caja-1')
const cajaB = await device(e.H2_CAJA_EMAIL, e.H2_CAJA_PASSWORD, 'caja-2')
const cocina = await device(e.H2_COCINA_EMAIL, e.H2_COCINA_PASSWORD, 'cocina')
const cm = ctx(mozoA, 'MOZO'); const cc = ctx(cajaA, 'CAJA')
const waiterA = createWaiterOrderService(mozoA.client); const waiterB = createWaiterOrderService(mozoB.client)
const cashierA = createCashierService(cajaA.client); const cashierB = createCashierService(cajaB.client)
const kitchen = createKitchenRealtimeService(cocina.client)

// ===== Precondiciones: migraciones E10 aplicadas, caja abierta, dos mesas libres, un producto activo
const probe = await mozoA.client.rpc('rpc_solicitar_cuenta_pedido', { p_pedido_id: null })
if (probe.error?.code !== '22023') throw new Error(`Migraciones E10 no aplicadas en DEV (respuesta ${probe.error?.code ?? 'sin error'}).`)
const boxes = unwrap(await cashierA.getCashboxes(cc), 'cajas')
if (boxes.length !== 1) throw new Error('DEV debe tener exactamente una caja activa.')
const session = unwrap(await cashierA.getActiveSession(cc, boxes[0].id), 'sesión')
if (!session) throw new Error('Abra la caja en DEV desde la UI antes de ejecutar el script.')
const board = unwrap(await waiterA.getTableBoard(cm), 'tablero')
const free = board.filter((t) => t.estado === 'LIBRE' && !t.pedido)
if (free.length < 2) throw new Error('Se necesitan dos mesas LIBRES en DEV.')
const products = must(await mozoA.client.from('producto').select('id,nombre,precio,requiere_cocina').eq('local_id', cm.local.id).eq('activo', true).order('precio'), 'productos')
const product = products.find((p) => p.requiere_cocina === false) ?? products[0]
log(`Precondiciones OK: caja ${boxes[0].codigo} sesión abierta; mesas ${free[0].codigo}, ${free[1].codigo}; producto ${product.nombre} (cocina=${product.requiere_cocina})`)

// ===== Suscriptores Realtime reales: registran tabla/evento/estado (sin usar el payload como dato)
const events = []
function recorder(d, name) {
  const channel = d.client.channel(`e10-dev-${name}-${randomUUID().slice(0, 6)}`)
  for (const table of ['pedido', 'mesa', 'solicitud_cuenta']) {
    channel.on('postgres_changes', { event: '*', schema: 'public', table }, (payload) => {
      events.push({ at: Date.now(), who: name, table, event: payload.eventType, id: payload.new?.id ?? payload.old?.id, estado: payload.new?.estado, pedido: payload.new?.pedido_id })
    })
  }
  return new Promise((resolve) => channel.subscribe((status) => { if (status === 'SUBSCRIBED') resolve(channel) }))
}
const channels = await Promise.all([recorder(mozoA, 'mozo1'), recorder(mozoB, 'mozo2'), recorder(cajaA, 'caja1'), recorder(cajaB, 'caja2'), recorder(cocina, 'cocina')])
// Vistas reales: caja con additionalSignalTables y refetch autoritativo; segundo dispositivo del mozo.
let cajaSnapshot = []; let cajaRefetches = 0
const cajaView = await subscribeToOperationsChanges(cajaA.client, async () => { cajaRefetches += 1; const r = await cashierA.getPendingOrders(cc); if (r.ok) cajaSnapshot = r.data },
  () => log('caja1: error de conexión Realtime'), { channelName: 'e10-dev-cashier', additionalSignalTables: ['solicitud_cuenta'] })
const waitFor = async (predicate, ms = 8000) => { const start = Date.now(); while (Date.now() - start < ms) { if (predicate()) return Date.now() - start; await sleep(100) } return -1 }
const since = () => { const mark = Date.now(); return (who, table, filter = () => true) => events.find((x) => x.at >= mark && x.who === who && x.table === table && filter(x)) }

async function deliveredOrder(table) {
  const orderId = unwrap(await waiterA.createOrRecoverOrder(cm, table.id), 'abrir').pedidoId
  must(await mozoA.client.rpc('agregar_detalle_pedido', { p_pedido_id: orderId, p_producto_id: product.id, p_cantidad: 1, p_observacion: 'E10-DEV' }), 'agregar')
  unwrap(await waiterA.sendOrderToKitchen(cm, orderId), 'enviar')
  await prepareKitchen(orderId)
  unwrap(await waiterA.deliverOrder(cm, orderId), 'entregar')
  return orderId
}
async function prepareKitchen(orderId) {
  const pending = must(await cocina.client.from('detalle_pedido').select('id,estado').eq('pedido_id', orderId).eq('requiere_cocina', true).neq('estado', 'LISTO'), 'detalles cocina')
  if (pending.length === 0) return
  must(await cocina.client.rpc('rpc_recibir_pedido_cocina', { p_pedido_id: orderId }), 'recepción')
  for (const d of pending) {
    unwrap(await kitchen.transitionDetail(d.id, 'RECIBIDO_COCINA', 'EN_PREPARACION'), 'preparación')
    unwrap(await kitchen.transitionDetail(d.id, 'EN_PREPARACION', 'LISTO'), 'listo')
  }
}
async function payTotal(orderId) {
  const r = await cashierA.getPendingOrders(cc)
  const order = unwrap(r, 'pendientes').find((o) => o.orderId === orderId)
  return unwrap(await cashierA.registerPayment(cc, orderId, session.id, 'TOTAL', [{ method: 'EFECTIVO', amount: order.balance, tip: 0 }], randomUUID()), 'cobro')
}

try {
  // ===== Flujo A: solicitud, repetición desde el segundo dispositivo, lectura real y cobro total
  const p1 = await deliveredOrder(free[0])
  let seen = since()
  const req = unwrap(await waiterA.requestBill(cm, p1), 'solicitar')
  const tCaja1 = await waitFor(() => seen('caja1', 'solicitud_cuenta', (x) => x.event === 'INSERT'))
  const tCaja2 = await waitFor(() => seen('caja2', 'solicitud_cuenta', (x) => x.event === 'INSERT'))
  const tMozo2 = await waitFor(() => seen('mozo2', 'solicitud_cuenta', (x) => x.event === 'INSERT'))
  const tView = await waitFor(() => cajaSnapshot.some((o) => o.orderId === p1 && o.billRequestId === req.solicitudId))
  check('TP15 solicitud -> caja 1, caja 2 y segundo dispositivo del mozo', tCaja1 >= 0 && tCaja2 >= 0 && tMozo2 >= 0,
    `caja1 ${tCaja1} ms, caja2 ${tCaja2} ms, mozo2 ${tMozo2} ms`)
  check('TP15 vista de Caja refetch autoritativo con la solicitud', tView >= 0, `${tView} ms; refetches=${cajaRefetches}`)
  check('TP15 cocina no recibe solicitudes', !events.some((x) => x.who === 'cocina' && x.table === 'solicitud_cuenta'), 'sin eventos solicitud_cuenta en cocina')
  const review = unwrap(await waiterB.getOrderReview(cm, p1), 'revisión mozo 2')
  const tableRow = unwrap(await waiterB.getTableBoard(cm), 'tablero mozo 2').find((t) => t.id === free[0].id)
  check('TP13 lectura embebida PostgREST real (pedido y tablero)', review.cuentaSolicitadaEn === req.solicitadaEn && tableRow?.pedido?.cuentaSolicitadaEn === req.solicitadaEn,
    `revisión=${review.cuentaSolicitadaEn} tablero=${tableRow?.pedido?.cuentaSolicitadaEn}`)
  seen = since()
  const again = unwrap(await waiterB.requestBill(cm, p1), 'repetir')
  await sleep(2500)
  check('TP15 repetición idempotente sin evento nuevo', again.yaExistia && again.solicitudId === req.solicitudId && !seen('caja1', 'solicitud_cuenta'),
    `ya_existia=${again.yaExistia}`)
  const pendingRow = cajaSnapshot.find((o) => o.orderId === p1)
  check('TP12 real lectura de Caja', pendingRow?.billRequestedBy != null && pendingRow?.serverNow != null, `mozo=${pendingRow?.billRequestedBy} servidor=${pendingRow?.serverNow}`)
  seen = since()
  await payTotal(p1)
  const tClose = await waitFor(() => seen('caja2', 'solicitud_cuenta', (x) => x.estado === 'ATENDIDA'))
  const tMesa = await waitFor(() => seen('mozo2', 'mesa', (x) => x.estado === 'LIBRE'))
  const tGone = await waitFor(() => !cajaSnapshot.some((o) => o.orderId === p1))
  check('TP15 cierre ATENDIDA -> caja 2; mesa LIBRE -> mozo; retiro en vista de Caja', tClose >= 0 && tMesa >= 0 && tGone >= 0,
    `ATENDIDA ${tClose} ms, mesa ${tMesa} ms, vista ${tGone} ms`)

  // ===== Flujo B: HZ-02 real y reapertura con solicitud
  const p2 = await deliveredOrder(free[1])
  seen = since()
  must(await mozoA.client.rpc('agregar_detalle_pedido', { p_pedido_id: p2, p_producto_id: product.id, p_cantidad: 1, p_observacion: 'E10-DEV reapertura' }), 'reapertura sin solicitud')
  await sleep(4000)
  const cajaPedido = seen('caja1', 'pedido', (x) => x.id === p2); const cajaMesa = seen('caja1', 'mesa')
  const mozoPedido = seen('mozo2', 'pedido', (x) => x.id === p2)
  check('HZ-02 reapertura sin solicitud: Caja no recibe señal (mozo sí)', !cajaPedido && !cajaMesa && Boolean(mozoPedido),
    `caja pedido=${Boolean(cajaPedido)} caja mesa=${Boolean(cajaMesa)} mozo pedido=${Boolean(mozoPedido)}`)
  unwrap(await waiterA.sendOrderToKitchen(cm, p2), 'enviar reapertura'); await prepareKitchen(p2)
  unwrap(await waiterA.deliverOrder(cm, p2), 'entregar 2')
  const req2 = unwrap(await waiterA.requestBill(cm, p2), 'solicitar 2')
  await waitFor(() => cajaSnapshot.some((o) => o.orderId === p2 && o.billRequestId === req2.solicitudId))
  seen = since()
  must(await mozoA.client.rpc('agregar_detalle_pedido', { p_pedido_id: p2, p_producto_id: product.id, p_cantidad: 1, p_observacion: 'E10-DEV reapertura 2' }), 'reapertura con solicitud')
  const tSin = await waitFor(() => seen('caja1', 'solicitud_cuenta', (x) => x.estado === 'SIN_EFECTO'))
  const tViewGone = await waitFor(() => !cajaSnapshot.some((o) => o.orderId === p2))
  check('HZ-02 mitigación: reapertura con solicitud -> Caja recibe SIN_EFECTO y retira el pedido', tSin >= 0 && tViewGone >= 0, `SIN_EFECTO ${tSin} ms, vista ${tViewGone} ms`)

  // ===== TP16: remontaje rápido, reconexión y ausencia de polling
  // Remontaje antes de que Realtime confirme la salida del canal anterior (caso E7-T12).
  void cajaView.stop()
  let remountRefetch = 0
  const remounted = await subscribeToOperationsChanges(cajaA.client, async () => { remountRefetch += 1; const r = await cashierA.getPendingOrders(cc); if (r.ok) cajaSnapshot = r.data },
    () => log('caja1 remontada: error de conexión'), { channelName: 'e10-dev-cashier', additionalSignalTables: ['solicitud_cuenta'] })
  unwrap(await waiterA.sendOrderToKitchen(cm, p2), 'enviar 3'); await prepareKitchen(p2)
  unwrap(await waiterA.deliverOrder(cm, p2), 'entregar 3')
  const req3 = unwrap(await waiterA.requestBill(cm, p2), 'solicitar 3')
  const tRemount = await waitFor(() => cajaSnapshot.some((o) => o.orderId === p2 && o.billRequestId === req3.solicitudId))
  check('TP16 remontaje con el mismo nombre de canal sigue recibiendo (topic único)', tRemount >= 0, `${tRemount} ms, refetches=${remountRefetch}`)
  const beforeIdle = restRequests
  await sleep(10000)
  check('TP16 sin polling: 10 s sin señales no generan peticiones REST', restRequests === beforeIdle, `${restRequests - beforeIdle} peticiones`)
  cajaA.client.realtime.disconnect()
  await sleep(1500)
  const refetchBeforeReconnect = remountRefetch
  cajaA.client.realtime.connect()
  const tReconnect = await waitFor(() => remountRefetch > refetchBeforeReconnect, 15000)
  check('TP16 reconexión resincroniza el snapshot autoritativo', tReconnect >= 0, `${tReconnect} ms`)
  await payTotal(p2)
  await remounted.stop()
} finally {
  for (const ch of channels) await ch.unsubscribe()
  const failed = results.filter((r) => !r.ok)
  log(`RESUMEN ${results.length - failed.length}/${results.length} PASS${failed.length ? ' — FALLAS: ' + failed.map((r) => r.id).join('; ') : ''}`)
  log(`Eventos registrados: ${events.length}. Log completo en ${LOG}.`)
  process.exit(failed.length ? 1 : 0)
}
