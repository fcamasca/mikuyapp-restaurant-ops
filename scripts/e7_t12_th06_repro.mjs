// E7-T12 / TH06 — Reproducción del defecto posterior al cobro total en el stack Supabase LOCAL (loopback).
// Recorrido real: mozo (pedido mixto) -> cocina (recepción y LISTO) -> mozo (entrega) -> caja (cobro TOTAL),
// con la vista del mozo suscrita a Realtime como WaiterOrderPage. Informa qué obtiene el mozo al resincronizar.
// Variables (las pone scripts/e7_t12_th06.ps1): E7_VALIDATION_SUPABASE_URL, E7_VALIDATION_PUBLISHABLE_KEY,
// E7_VALIDATION_SERVICE_ROLE_KEY (sólo Auth admin). Nunca contra cloud.
import { execFileSync } from 'node:child_process'
import { randomBytes, randomUUID } from 'node:crypto'
import { createClient } from '@supabase/supabase-js'
import { createWaiterOrderService } from '../src/services/waiterOrderService.ts'
import { createKitchenRealtimeService } from '../src/services/kitchenRealtimeService.ts'
import { createCashierService } from '../src/services/cashierService.ts'
import { subscribeToOperationsChanges } from '../src/services/operationsRealtimeService.ts'

const url = process.env.E7_VALIDATION_SUPABASE_URL?.trim()
const anonKey = process.env.E7_VALIDATION_PUBLISHABLE_KEY?.trim()
const serviceKey = process.env.E7_VALIDATION_SERVICE_ROLE_KEY?.trim()
if (!url || !anonKey || !serviceKey) throw new Error('Faltan variables E7_VALIDATION_*')
if (!['127.0.0.1', 'localhost', '::1'].includes(new URL(url).hostname)) throw new Error('Sólo stack local (loopback).')

const sql = (text) => execFileSync('docker', ['exec', '-i', '-e', 'PGPASSWORD=postgres', 'supabase_db_mikuyapp-restaurant-ops', 'psql', '-h', '127.0.0.1',
  '-U', 'postgres', '-d', 'postgres', '-X', '-At', '-v', 'ON_ERROR_STOP=1'], { input: text, encoding: 'utf8' }).trim()
const client = (key) => createClient(url, key, { auth: { persistSession: false, autoRefreshToken: false } })
const sleep = (ms) => new Promise((r) => setTimeout(r, ms))
const must = (r, label) => { if (r.error) throw new Error(`${label}: ${r.error.code ?? ''} ${r.error.message}`); return r.data }
const ok = (r, label) => { if (!r.ok) throw new Error(`${label}: ${r.error.message}`); return r.data }

const run = randomUUID().slice(0, 8)
const password = randomBytes(18).toString('base64url')
const admin = client(serviceKey)
const users = {}
for (const [key, code] of [['mozo', 'MOZO'], ['cocina', 'COCINA'], ['caja', 'CAJA']]) {
  const email = `e7-th06-${run}-${key}@example.invalid`
  const created = await admin.auth.admin.createUser({ email, password, email_confirm: true })
  if (created.error) throw new Error(created.error.message)
  users[key] = { id: created.data.user.id, email, code }
}
const fx = JSON.parse(sql(`with l as (insert into public.local (codigo, nombre) values ('E7-TH06-${run}', 'TH06 ${run}') returning id),
 p as (insert into public.perfil_usuario (id, local_id, rol_id, nombre) select u.id, l.id, r.id, u.n from l,
   (values ('${users.mozo.id}'::uuid, 'MOZO', 'Mozo'), ('${users.cocina.id}'::uuid, 'COCINA', 'Cocina'), ('${users.caja.id}'::uuid, 'CAJA', 'Caja')) u(id, c, n)
   join public.rol r on r.codigo = u.c returning id),
 m as (insert into public.mesa (local_id, codigo, nombre) select id, 'TH06', 'Mesa TH06' from l returning id),
 c as (insert into public.categoria (local_id, codigo, nombre) select id, 'TH06', 'Carta' from l returning id),
 pr as (insert into public.producto (local_id, categoria_id, codigo, nombre, precio, requiere_cocina) select l.id, c.id, v.a, v.b, v.p, v.r from l, c,
   (values ('CEV', 'Ceviche', 30, true), ('CHI', 'Chicha', 8, false)) v(a, b, p, r) returning id, codigo),
 cj as (insert into public.caja (local_id, codigo, nombre) select id, 'TH06', 'Caja TH06' from l returning id, local_id),
 s as (insert into public.sesion_caja (caja_id, local_id, abierta_por, monto_inicial, idempotency_key) select id, local_id, '${users.caja.id}', 0, gen_random_uuid() from cj returning id)
select json_build_object('local', (select id from l), 'mesa', (select id from m), 'sesion', (select id from s), 'perfiles', (select count(*) from p),
 'cev', (select id from pr where codigo = 'CEV'), 'chi', (select id from pr where codigo = 'CHI'));`).split(/\r?\n/).pop())

async function signIn(u) { const c = client(anonKey); must(await c.auth.signInWithPassword({ email: u.email, password }), 'login'); return c }
const ctx = (u) => ({ profile: { id: u.id, local_id: fx.local, rol_id: 0, nombre: u.code, activo: true }, role: { id: 0, codigo: u.code, activo: true }, local: { id: fx.local, activo: true } })
const [mozoC, cocinaC, cajaC] = await Promise.all([signIn(users.mozo), signIn(users.cocina), signIn(users.caja)])
const waiter = createWaiterOrderService(mozoC)
const kitchen = createKitchenRealtimeService(cocinaC)
const cashier = createCashierService(cajaC)
const cm = ctx(users.mozo)

const orderId = ok(await waiter.createOrRecoverOrder(cm, fx.mesa), 'abrir').pedidoId
must(await mozoC.rpc('agregar_detalle_pedido', { p_pedido_id: orderId, p_producto_id: fx.cev, p_cantidad: 1, p_observacion: null }), 'ceviche')
must(await mozoC.rpc('agregar_detalle_pedido', { p_pedido_id: orderId, p_producto_id: fx.chi, p_cantidad: 1, p_observacion: null }), 'chicha')
ok(await waiter.sendOrderToKitchen(cm, orderId), 'envío')
must(await cocinaC.rpc('rpc_recibir_pedido_cocina', { p_pedido_id: orderId }), 'recepción')
const cev = sql(`select id from public.detalle_pedido where pedido_id = ${orderId} and requiere_cocina`)
ok(await kitchen.transitionDetail(Number(cev), 'RECIBIDO_COCINA', 'EN_PREPARACION'), 'preparación')
ok(await kitchen.transitionDetail(Number(cev), 'EN_PREPARACION', 'LISTO'), 'listo')
ok(await waiter.deliverOrder(cm, orderId), 'entrega')
// Regresión H5: reapertura antes del primer pago (bebida nueva -> LISTO/PEDIDO_LISTO) y segunda entrega.
must(await mozoC.rpc('agregar_detalle_pedido', { p_pedido_id: orderId, p_producto_id: fx.chi, p_cantidad: 1, p_observacion: 'reapertura' }), 'reapertura')
ok(await waiter.sendOrderToKitchen(cm, orderId), 'envío reapertura')
console.log(`Reapertura antes del pago: ${sql(`select p.estado||' / mesa '||m.estado from public.pedido p join public.mesa m on m.id = p.mesa_id where p.id = ${orderId}`)}`)
ok(await waiter.deliverOrder(cm, orderId), 'segunda entrega')
console.log(`Antes del cobro: ${sql(`select 'pedido #'||p.id||' '||p.estado||' / mesa '||m.estado from public.pedido p join public.mesa m on m.id = p.mesa_id where p.id = ${orderId}`)}`)

// Vista del mozo abierta en el pedido: misma resincronización que WaiterOrderPage (reloadOrderSnapshot) en cada señal.
const seen = []
const handle = await subscribeToOperationsChanges(mozoC, async () => {
  const [d, r, c] = await Promise.all([waiter.getOrderDetails(cm, orderId), waiter.getOrderReview(cm, orderId), waiter.getOrderCancellations(cm, orderId)])
  seen.push({ detalles: d.ok ? d.data.length : d.error.message, revision: r.ok ? `${r.data.estado}/${r.data.mesa.estado}` : `${r.error.kind}: ${r.error.message}`, cancelaciones: c.ok ? c.data.length : c.error.message })
}, () => {}, { channelName: `th06-${run}`, initialRefresh: false })
await sleep(2500)
seen.length = 0 // sólo cuentan las resincronizaciones posteriores al cobro

const payment = await cashier.registerPayment(ctx(users.caja), orderId, fx.sesion, 'TOTAL', [{ method: 'EFECTIVO', amount: 46, tip: 0 }], randomUUID())
console.log(`Cobro TOTAL: ${payment.ok ? 'confirmado' : payment.error.message}`)
console.log(`Después del cobro (BD): ${sql(`select 'pedido #'||p.id||' '||p.estado||' / mesa '||m.estado from public.pedido p join public.mesa m on m.id = p.mesa_id where p.id = ${orderId}`)}`)
const started = Date.now(); while (seen.length === 0 && Date.now() - started < 15000) await sleep(100)
console.log(`Señal Realtime al mozo: ${seen.length ? `${Date.now() - started} ms` : 'no llegó en 15 s'}`)
console.log(`Resincronización del mozo (señal): ${JSON.stringify(seen[0] ?? null)}`)
const retry = await waiter.getOrderReview(cm, orderId)
console.log(`Reintentar (getOrderReview): ${retry.ok ? `${retry.data.estado}/${retry.data.mesa.estado}` : `${retry.error.kind}: ${retry.error.message}`}`)
const board = await waiter.getTableBoard(cm)
console.log(`Mesas del mozo: ${board.ok ? board.data.map((t) => `${t.codigo} ${t.estado} pedido=${t.pedido?.id ?? 'ninguno'}`).join('; ') : board.error.message}`)
await handle.stop()
await Promise.all([mozoC, cocinaC, cajaC].map((c) => c.auth.signOut()))
const reproduced = !retry.ok && retry.error.message === 'No pudimos cargar el pedido vigente. Intenta nuevamente.'
const dbOk = sql(`select p.estado||'/'||m.estado from public.pedido p join public.mesa m on m.id = p.mesa_id where p.id = ${orderId}`) === 'PAGADO/LIBRE'
const signalOk = seen.length > 0 && String(seen[0].revision).startsWith('order-not-current')
const fixed = dbOk && signalOk && !retry.ok && retry.error.kind === 'order-not-current' && board.ok && board.data.every((t) => t.pedido === null)
console.log(reproduced ? '== TH06 DEFECTO REPRODUCIDO' : fixed ? '== TH06 CORREGIDO: PAGADO/LIBRE; la señal y Reintentar devuelven order-not-current (la vista vuelve a mesas)' : `== TH06 resultado inesperado: ${retry.ok ? 'revisión OK' : retry.error.kind}`)
process.exitCode = fixed ? 0 : 1
