// E7-T10 — Validación en un proyecto Supabase AISLADO (PostgreSQL 17 + PostgREST + Realtime reales).
// Uso (PowerShell o bash), con variables efímeras que NO se guardan en .env.local:
//   E7_VALIDATION_SUPABASE_URL=https://<ref-validacion>.supabase.co
//   E7_VALIDATION_PUBLISHABLE_KEY=<clave publicable del proyecto de validación>
//   E7_VALIDATION_SERVICE_ROLE_KEY=<service_role del proyecto de validación>  (sólo para crear usuarios/fixture)
//   node --experimental-strip-types scripts/e7_t10_validation.mjs
// Guardia: se niega a ejecutar contra el proyecto de .env.local, supabase/.temp/project-ref o los refs
// DEV/SHARED/PROD declarados (el proyecto compartido con Production nunca es destino de E7-T10).
// Modo local (desviación de ambiente aprobada para T10): E7_VALIDATION_LOCAL=1 apunta al stack
// Supabase local del repositorio (`supabase start`, http://127.0.0.1:54321); sólo acepta loopback.
import assert from 'node:assert/strict'
import { randomBytes, randomUUID } from 'node:crypto'
import { execFileSync } from 'node:child_process'
import { readFile } from 'node:fs/promises'
import { createClient } from '@supabase/supabase-js'
import { createKitchenRealtimeService } from '../src/services/kitchenRealtimeService.ts'
import { buildCommandDocument, createKitchenCommandService } from '../src/services/kitchenCommandService.ts'
import { subscribeToOperationsChanges } from '../src/services/operationsRealtimeService.ts'
import { createWaiterOrderService } from '../src/services/waiterOrderService.ts'

const url = process.env.E7_VALIDATION_SUPABASE_URL?.trim()
const publishableKey = process.env.E7_VALIDATION_PUBLISHABLE_KEY?.trim()
const serviceRoleKey = process.env.E7_VALIDATION_SERVICE_ROLE_KEY?.trim()
const results = []
const step = (name, ok, detail = '') => { results.push({ name, ok, detail }); console.log(`${ok ? 'OK  ' : 'FAIL'} ${name}${detail ? ` — ${detail}` : ''}`) }

function refFromUrl(value) {
  const host = new URL(value).hostname
  const match = host.match(/^([a-z0-9]+)\.supabase\.co$/)
  if (!match) throw new Error('E7_VALIDATION_SUPABASE_URL debe ser https://<ref>.supabase.co')
  return match[1]
}

async function readOptional(path) { try { return (await readFile(path, 'utf8')).trim() } catch { return '' } }

async function guard() {
  if (!url || !publishableKey || !serviceRoleKey) throw new Error('Faltan variables E7_VALIDATION_*.')
  if (process.env.E7_VALIDATION_LOCAL === '1') {
    const host = new URL(url).hostname
    if (!['127.0.0.1', 'localhost', '::1'].includes(host)) throw new Error('Guardia E7-T10: el modo local sólo acepta el stack Supabase en loopback.')
    console.log(`Destino de validación: stack Supabase local (${new URL(url).host})`)
    return
  }
  const ref = refFromUrl(url)
  const envLocal = await readOptional(new URL('../.env.local', import.meta.url))
  const forbidden = new Set([await readOptional(new URL('../supabase/.temp/project-ref', import.meta.url))])
  for (const line of envLocal.split(/\r?\n/)) {
    const [key, ...rest] = line.split('=')
    const value = rest.join('=').trim()
    if (!value) continue
    if (key === 'VITE_SUPABASE_URL') { try { forbidden.add(refFromUrl(value)) } catch { /* ignorar */ } }
    if (/^MIKUY_(EXPECTED|DEV|SHARED|PROD)_SUPABASE_PROJECT_REF$/.test(key)) forbidden.add(value.toLowerCase())
  }
  if (forbidden.has(ref)) throw new Error('Guardia E7-T10: el destino coincide con un proyecto DEV/SHARED/PROD. Abortado.')
  console.log(`Destino de validación aislado: ${ref.slice(0, 4)}…${ref.slice(-4)} (no coincide con DEV/SHARED/PROD)`)
}

const client = (key) => createClient(url, key, { auth: { persistSession: false, autoRefreshToken: false } })
const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms))
async function waitFor(label, predicate, timeoutMs = 15000) {
  const started = Date.now()
  while (Date.now() - started < timeoutMs) {
    if (predicate()) { step(label, true, `${Date.now() - started} ms`); return true }
    await sleep(100)
  }
  step(label, false, `sin señal en ${timeoutMs} ms`); return false
}
const must = (result, label) => { if (result.error) throw new Error(`${label}: ${result.error.code ?? ''} ${result.error.message}`); return result.data }

// Modo local: las tablas base de la baseline no conceden privilegios a service_role en la imagen
// Supabase local actual (sólo Auth admin los necesita). La fixture de tablas se crea con psql como
// postgres dentro del contenedor de base local; nunca se usa en modo cloud.
function localSql(sql) {
  const container = process.env.E7_VALIDATION_DB_CONTAINER?.trim() || 'supabase_db_mikuyapp-restaurant-ops'
  return execFileSync('docker', ['exec', '-i', '-e', 'PGPASSWORD=postgres', container, 'psql', '-h', '127.0.0.1', '-U', 'postgres',
    '-d', 'postgres', '-X', '-At', '-v', 'ON_ERROR_STOP=1'], { input: sql, encoding: 'utf8' }).trim()
}

async function localFixture(admin, runId, password) {
  const users = {}
  for (const [key, code] of [['mozoA', 'MOZO'], ['mozoB', 'MOZO'], ['cocina1', 'COCINA'], ['cocina2', 'COCINA']]) {
    const email = `e7-val-${runId}-${key.toLowerCase()}@example.invalid`
    const created = await admin.auth.admin.createUser({ email, password, email_confirm: true })
    if (created.error) throw new Error(`usuario ${key}: ${created.error.message}`)
    users[key] = { id: created.data.user.id, email, code }
  }
  const perfiles = Object.entries(users).map(([key, u]) => `('${u.id}'::uuid, '${u.code}', '${key} ${runId}')`).join(', ')
  const out = localSql(`with l as (insert into public.local (codigo, nombre) values ('E7-VAL-${runId}', 'Validación E7 ${runId}') returning id),
  p as (insert into public.perfil_usuario (id, local_id, rol_id, nombre)
        select u.id, l.id, r.id, u.nombre from l, (values ${perfiles}) as u(id, codigo, nombre) join public.rol r on r.codigo = u.codigo returning id),
  m as (insert into public.mesa (local_id, codigo, nombre) select id, '${`V${runId}`.slice(0, 12)}', 'Mesa validación E7' from l returning id),
  c as (insert into public.categoria (local_id, codigo, nombre) select id, '${`E7V${runId}`.slice(0, 12)}', 'Validación' from l returning id),
  pr as (insert into public.producto (local_id, categoria_id, codigo, nombre, precio, requiere_cocina)
         select l.id, c.id, v.codigo, v.nombre, v.precio, v.rc from l, c,
         (values ('E7V-CEV', 'Ceviche validación', 30, true), ('E7V-CHI', 'Chicha validación', 8, false)) as v(codigo, nombre, precio, rc) returning id, codigo)
select json_build_object('local', (select id from l), 'mesa', (select id from m), 'perfiles', (select count(*) from p),
  'ceviche', (select id from pr where codigo = 'E7V-CEV'), 'chicha', (select id from pr where codigo = 'E7V-CHI'));`)
  const row = JSON.parse(out.split(/\r?\n/).pop())
  if (row.perfiles !== 4) throw new Error(`fixture local: perfiles=${row.perfiles}`)
  return { password, local: row.local, mesa: row.mesa, users, ceviche: row.ceviche, chicha: row.chicha }
}

async function fixture(admin, runId) {
  const password = randomBytes(18).toString('base64url')
  if (process.env.E7_VALIDATION_LOCAL === '1') return localFixture(admin, runId, password)
  const roles = must(await admin.from('rol').select('id,codigo'), 'roles')
  const roleId = (code) => roles.find((row) => row.codigo === code).id
  const local = must(await admin.from('local').insert({ codigo: `E7-VAL-${runId}`, nombre: `Validación E7 ${runId}` }).select('id').single(), 'local')
  const users = {}
  for (const [key, code] of [['mozoA', 'MOZO'], ['mozoB', 'MOZO'], ['cocina1', 'COCINA'], ['cocina2', 'COCINA']]) {
    const email = `e7-val-${runId}-${key.toLowerCase()}@example.invalid`
    const created = await admin.auth.admin.createUser({ email, password, email_confirm: true })
    if (created.error) throw new Error(`usuario ${key}: ${created.error.message}`)
    must(await admin.from('perfil_usuario').insert({ id: created.data.user.id, local_id: local.id, rol_id: roleId(code), nombre: `${key} ${runId}` }), `perfil ${key}`)
    users[key] = { id: created.data.user.id, email, code }
  }
  const mesa = must(await admin.from('mesa').insert({ local_id: local.id, codigo: `V${runId}`.slice(0, 12), nombre: 'Mesa validación E7' }).select('id').single(), 'mesa')
  const categoria = must(await admin.from('categoria').insert({ local_id: local.id, codigo: `E7V${runId}`.slice(0, 12), nombre: 'Validación' }).select('id').single(), 'categoria')
  const productos = must(await admin.from('producto').insert([
    { local_id: local.id, categoria_id: categoria.id, codigo: 'E7V-CEV', nombre: 'Ceviche validación', precio: 30, requiere_cocina: true },
    { local_id: local.id, categoria_id: categoria.id, codigo: 'E7V-CHI', nombre: 'Chicha validación', precio: 8, requiere_cocina: false },
  ]).select('id,codigo'), 'productos')
  const product = (code) => productos.find((row) => row.codigo === code).id
  return { password, local: local.id, mesa: mesa.id, users, ceviche: product('E7V-CEV'), chicha: product('E7V-CHI') }
}

async function signIn(user, password) {
  const c = client(publishableKey)
  must(await c.auth.signInWithPassword({ email: user.email, password }), `login ${user.email}`)
  return c
}

const context = (fx, user) => ({
  profile: { id: user.id, local_id: fx.local, rol_id: 0, nombre: user.email, activo: true },
  role: { id: 0, codigo: user.code, activo: true },
  local: { id: fx.local, activo: true },
})

async function main() {
  await guard()
  const admin = client(serviceRoleKey)
  const runId = randomUUID().slice(0, 8)
  const fx = await fixture(admin, runId)
  step('fixture aislada (local, 4 usuarios, mesa, productos con/sin cocina)', true, `run ${runId}`)

  const [mozoA, mozoB, cocina1, cocina2] = await Promise.all(['mozoA', 'mozoB', 'cocina1', 'cocina2'].map((k) => signIn(fx.users[k], fx.password)))
  const waiterA = createWaiterOrderService(mozoA)
  const waiterB = createWaiterOrderService(mozoB)
  const kitchen1 = createKitchenRealtimeService(cocina1)
  const kitchen2 = createKitchenRealtimeService(cocina2)
  const commands1 = createKitchenCommandService(cocina1)
  const commands2 = createKitchenCommandService(cocina2)
  const ctxA = context(fx, fx.users.mozoA)
  const ctxB = context(fx, fx.users.mozoB)

  // Suscripciones reales (mismo código del frontend): cocina 1 y mozo B
  let kitchenBoard = null
  let kitchenRefreshes = 0
  const kitchenHandle = await kitchen1.start({
    onSnapshot: (_rows, board) => { kitchenBoard = board; kitchenRefreshes += 1 },
    onError: (message) => console.log(`aviso cocina: ${message}`),
  })
  let orderId = null
  let waiterBView = null
  let waiterBRefreshes = 0
  const waiterHandle = await subscribeToOperationsChanges(mozoB, async () => {
    if (!orderId) return
    const [details, cancellations] = await Promise.all([waiterB.getOrderDetails(ctxB, orderId), waiterB.getOrderCancellations(ctxB, orderId)])
    if (details.ok && cancellations.ok) { waiterBView = { details: details.data, cancellations: cancellations.data }; waiterBRefreshes += 1 }
  }, () => console.log('aviso mozo B: reconexión'), { channelName: `e7-val-waiter-${runId}`, initialRefresh: false })
  await sleep(2500) // SUBSCRIBED

  try {
    // 1. Pedido mixto, edición y retiro (RPC E7-D15)
    const opened = await mozoA.rpc('crear_o_recuperar_pedido_mesa', { p_mesa_id: fx.mesa })
    orderId = must(opened, 'abrir pedido')[0].pedido_id
    const add = async (product, qty, obs) => must(await mozoA.rpc('agregar_detalle_pedido', { p_pedido_id: orderId, p_producto_id: product, p_cantidad: qty, p_observacion: obs }), 'agregar')[0].detalle_id
    const c1 = await add(fx.ceviche, 1, null)
    const c2 = await add(fx.ceviche, 1, 'sin ají')
    const c3 = await add(fx.ceviche, 1, 'para retirar')
    const bebida = await add(fx.chicha, 2, null)
    step('edición vía rpc_modificar_detalle_pedido', (await waiterA.updateOpenDetail(ctxA, c1, { cantidad: 2 }, { cantidad: 1, observacion: null })).ok)
    const stale = await waiterB.updateOpenDetail(ctxB, c1, { cantidad: 5 }, { cantidad: 1, observacion: null })
    step('PostgREST devuelve PT409 → conflicto concurrente', !stale.ok && stale.error.kind === 'concurrent-conflict')
    step('retiro vía rpc_retirar_detalle_pedido', (await waiterA.removeOpenDetail(ctxA, c3)).ok)

    // 2. Envío mixto → Realtime a cocina: sólo ceviches, comanda 1
    const before = kitchenRefreshes
    const sent = await waiterA.sendOrderToKitchen(ctxA, orderId)
    step('envío mixto', sent.ok && sent.data.detallesEnviados === 3)
    await waitFor('Realtime: cocina recibe el envío sin la bebida y con comanda', () => kitchenRefreshes > before
      && kitchenBoard?.detalles.filter((d) => d.pedido_id === orderId).length === 2
      && !kitchenBoard.detalles.some((d) => d.detalle_id === bebida)
      && kitchenBoard.comandas.some((c) => c.pedido_id === orderId && c.numero === 1 && c.lineas.length === 2))
    const detalles = must(await mozoA.from('detalle_pedido').select('id,estado,requiere_cocina').eq('pedido_id', orderId), 'detalles')
    step('producto sin cocina → LISTO', detalles.find((d) => d.id === bebida)?.estado === 'LISTO' && detalles.find((d) => d.id === bebida)?.requiere_cocina === false)

    // 3. Comanda: primera solicitud concurrente (PT409), reimpresión y documento
    let comanda = kitchenBoard?.comandas.find((c) => c.pedido_id === orderId && c.numero === 1)
    if (!comanda) { // Diagnóstico: sin señal Realtime, se continúa con el snapshot autoritativo leído vía RPC (el paso Realtime ya quedó en FAIL)
      console.log(`diagnóstico: refrescos de cocina=${kitchenRefreshes}, snapshot recibido=${kitchenBoard ? 'sí' : 'no'}`)
      const board = must(await cocina1.rpc('rpc_obtener_tablero_cocina'), 'tablero (diagnóstico)')
      comanda = board.comandas.find((c) => c.pedido_id === orderId && c.numero === 1)
      kitchenBoard = board
    }
    const [p1, p2] = await Promise.all([commands1.registerPrint(comanda.comanda_id, false), commands2.registerPrint(comanda.comanda_id, false)])
    step('primera solicitud única con PT409 concurrente', [p1, p2].filter((r) => r.ok).length === 1 && [p1, p2].some((r) => !r.ok && r.error.kind === 'concurrent-conflict'))
    const reprint = await commands2.registerPrint(comanda.comanda_id, true)
    step('reimpresión registrada', reprint.ok && reprint.impresiones === 2)

    // 4. Recepción completa (cocina 2) → Realtime a cocina 1
    const r1 = await kitchen2.receiveOrder(orderId)
    step('recepción completa', r1.ok && r1.received === 2)
    await waitFor('Realtime: cocina 1 ve RECIBIDO_COCINA', () => kitchenBoard?.detalles.filter((d) => d.pedido_id === orderId).every((d) => d.estado === 'RECIBIDO_COCINA'))
    const r2 = await kitchen1.receiveOrder(orderId)
    step('reintento de recepción = 0 sin error', r2.ok && r2.received === 0)

    // 5. Cancelación (mozo B) → la señal es el UPDATE de pedido; cocina y mozo B resincronizan
    const beforeWaiter = waiterBRefreshes
    const cancel = await waiterB.cancelOrderDetail(ctxB, c2, 'Cliente cambió de opinión')
    step('cancelación de línea completa', cancel.ok)
    await waitFor('Realtime: cocina recibe la cancelación', () => kitchenBoard?.cancelaciones.some((c) => c.detalle_id === c2)
      && !kitchenBoard.detalles.some((d) => d.detalle_id === c2))
    await waitFor('Realtime: mozo B resincroniza y ve el cancelado', () => waiterBRefreshes > beforeWaiter
      && waiterBView?.cancellations.some((c) => c.detalle_id === c2))
    const late = await kitchen2.transitionDetail(c2, 'RECIBIDO_COCINA', 'EN_PREPARACION')
    step('transición sobre cancelado → PT409', !late.ok && late.error.kind === 'concurrent-conflict')

    // 6. Documento imprimible con la línea cancelada marcada
    await kitchenHandle.resync()
    const refreshed = kitchenBoard.comandas.find((c) => c.comanda_id === comanda.comanda_id)
    const doc = buildCommandDocument(refreshed, kitchenBoard.cancelaciones, refreshed.impresiones)
    step('resync del snapshot autoritativo + documento (COPIA 1, línea CANCELADO)', doc.copyLabel === 'COPIA 1' && doc.lines.some((l) => l.detalle_id === c2 && l.cancelado))

    // 7. Avance individual hasta LISTO
    assert.ok((await kitchen1.transitionDetail(c1, 'RECIBIDO_COCINA', 'EN_PREPARACION')).ok)
    const cannot = await waiterA.cancelOrderDetail(ctxA, c1, 'tarde')
    step('cancelación bloqueada en EN_PREPARACION (PT409)', !cannot.ok && cannot.error.kind === 'concurrent-conflict')
    assert.ok((await kitchen1.transitionDetail(c1, 'EN_PREPARACION', 'LISTO')).ok)
    const review = await waiterA.getOrderReview(ctxA, orderId)
    step('pedido LISTO / mesa PEDIDO_LISTO', review.ok && review.data.estado === 'LISTO' && review.data.mesa.estado === 'PEDIDO_LISTO')
  } finally {
    await kitchenHandle.stop()
    await waiterHandle.stop()
    await Promise.all([mozoA, mozoB, cocina1, cocina2].map((c) => c.auth.signOut()))
  }
  const failed = results.filter((r) => !r.ok).length
  console.log(`== E7-T10 validación aislada: ${results.length - failed}/${results.length} OK`)
  process.exitCode = failed ? 1 : 0
}

main().catch((error) => { console.error(`ERROR: ${error.message}`); process.exitCode = 1 })
