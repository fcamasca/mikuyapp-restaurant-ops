// E9 — TP22/TP21 con clientes Realtime programáticos contra un servidor Supabase REAL: el stack Supabase local
// del repositorio (Docker + `supabase start`, http://127.0.0.1:54321), mismo patrón aprobado en E7-T10.
// Verifica que ADMIN, MOZO, COCINA y CAJA reciben la apertura y el cierre de la jornada sin refrescar (con un
// segundo ADMIN), la apertura idempotente, el remontaje con topic único, la ausencia de polling y la
// reconexión, usando los servicios reales del frontend (operationalDayService).
//
// Uso: lo invoca scripts/e9_t06_local.ps1 con variables efímeras tomadas de `supabase status`:
//   E9_VALIDATION_SUPABASE_URL=http://127.0.0.1:54321  E9_VALIDATION_PUBLISHABLE_KEY=...  E9_VALIDATION_SERVICE_ROLE_KEY=...
//   node --experimental-strip-types scripts/e9_realtime_verificacion.mjs
// Guardia: sólo loopback. Nunca DEV, el proyecto compartido ni PROD (DC-12). La clave de servicio local se usa
// únicamente para crear los usuarios de prueba (Auth admin); la fixture de tablas se crea con psql dentro del
// contenedor de base local. El local de prueba es propio de cada ejecución y queda cerrado al terminar.
import { appendFileSync, writeFileSync } from 'node:fs'
import { randomBytes, randomUUID } from 'node:crypto'
import { execFileSync } from 'node:child_process'
import { createClient } from '@supabase/supabase-js'
import { createOperationalDayService, subscribeToOperationalDay } from '../src/services/operationalDayService.ts'

const LOG = 'e9-realtime-verificacion.log'
writeFileSync(LOG, '')
const log = (line) => { const text = `[${new Date().toISOString()}] ${line}`; console.log(text); appendFileSync(LOG, text + '\n') }
const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms))
const results = []
const check = (id, ok, detail) => { results.push({ id, ok, detail }); log(`${ok ? 'PASS' : 'FAIL'} ${id}: ${detail}`) }
const unwrap = (r, label) => { if (!r.ok) throw new Error(`${label}: ${r.error.message}`); return r.data }
const must = (r, label) => { if (r.error) throw new Error(`${label}: ${r.error.code ?? ''} ${r.error.message}`); return r.data }

const url = process.env.E9_VALIDATION_SUPABASE_URL?.trim()
const publishableKey = process.env.E9_VALIDATION_PUBLISHABLE_KEY?.trim()
const serviceRoleKey = process.env.E9_VALIDATION_SERVICE_ROLE_KEY?.trim()
if (!url || !publishableKey || !serviceRoleKey) throw new Error('Faltan variables E9_VALIDATION_*.')
if (!['127.0.0.1', 'localhost', '::1', '[::1]'].includes(new URL(url).hostname)) {
  throw new Error('Guardia E9: sólo se ejecuta contra el stack Supabase local (loopback).')
}
log(`Stack Supabase local: ${url}`)

function localSql(sql) {
  const container = process.env.E9_VALIDATION_DB_CONTAINER?.trim() || 'supabase_db_mikuyapp-restaurant-ops'
  return execFileSync('docker', ['exec', '-i', '-e', 'PGPASSWORD=postgres', container, 'psql', '-h', '127.0.0.1', '-U', 'postgres',
    '-d', 'postgres', '-X', '-At', '-v', 'ON_ERROR_STOP=1'], { input: sql, encoding: 'utf8' }).trim()
}

// ===== Fixture propia: local nuevo (sin jornadas, por tanto cerrado) con un usuario por rol
const runId = randomUUID().slice(0, 8)
const password = randomBytes(18).toString('base64url')
const admin = createClient(url, serviceRoleKey, { auth: { persistSession: false, autoRefreshToken: false } })
const users = {}
for (const [key, code] of [['admin', 'ADMINISTRADOR'], ['mozo', 'MOZO'], ['cocina', 'COCINA'], ['caja', 'CAJA']]) {
  const email = `e9-val-${runId}-${key}@example.invalid`
  const created = await admin.auth.admin.createUser({ email, password, email_confirm: true })
  if (created.error) throw new Error(`usuario ${key}: ${created.error.message}`)
  users[key] = { id: created.data.user.id, email, code }
}
const perfiles = Object.entries(users).map(([key, u]) => `('${u.id}'::uuid, '${u.code}', '${key} ${runId}')`).join(', ')
const fx = JSON.parse(localSql(`with l as (insert into public.local (codigo, nombre) values ('E9-VAL-${runId}', 'Validación E9 ${runId}') returning id),
  p as (insert into public.perfil_usuario (id, local_id, rol_id, nombre)
        select u.id, l.id, r.id, u.nombre from l, (values ${perfiles}) as u(id, codigo, nombre) join public.rol r on r.codigo = u.codigo returning id)
select json_build_object('local', (select id from l), 'perfiles', (select count(*) from p));`).split(/\r?\n/).pop())
if (fx.perfiles !== 4) throw new Error(`fixture local: perfiles=${fx.perfiles}`)
const migrations = localSql("select count(*) || ' migraciones, última ' || max(version) from supabase_migrations.schema_migrations")
const publication = localSql("select string_agg(tablename, ',' order by tablename) from pg_publication_tables where pubname = 'supabase_realtime'")
log(`Base local: ${migrations}; publicación = ${publication}; local de prueba E9-VAL-${runId}`)
check('Publicación incluye jornada_operativa', publication.split(',').includes('jornada_operativa'), publication)

let restRequests = 0
const countingFetch = (...args) => { if (String(args[0]).includes('/rest/v1/')) restRequests += 1; return fetch(...args) }
async function device(user, label) {
  const client = createClient(url, publishableKey, { auth: { persistSession: false, autoRefreshToken: false }, global: { fetch: countingFetch } })
  must(await client.auth.signInWithPassword({ email: user.email, password }), `login ${label}`)
  const context = { profile: { id: user.id, local_id: fx.local, rol_id: 0, nombre: label, activo: true },
    role: { id: 0, codigo: user.code, activo: true }, local: { id: fx.local, nombre: 'Validación E9', activo: true } }
  return { client, label, context, service: createOperationalDayService(client), state: 'desconocido', dayId: null, refetches: 0, pending: 0, status: 'CREATED', events: { INSERT: 0, UPDATE: 0 } }
}
const devices = [
  await device(users.admin, 'admin-1'), await device(users.admin, 'admin-2'),
  await device(users.mozo, 'mozo'), await device(users.cocina, 'cocina'), await device(users.caja, 'caja'),
]
const [adminDevice] = devices

async function refresh(d) {
  d.refetches += 1
  d.pending += 1
  const r = await d.service.getCurrent()
  d.pending -= 1
  if (!r.ok) throw new Error(`${d.label}: ${r.error.message}`)
  if (r.ok) { d.state = r.data ? 'ABIERTA' : 'CERRADA'; d.dayId = r.data?.id ?? null }
}
async function waitAll(predicate, timeoutMs = 10000) {
  const start = Date.now()
  while (Date.now() - start < timeoutMs) { if (devices.every(predicate)) return Date.now() - start; await sleep(50) }
  return -1
}

// Observe real channel acknowledgements and payloads without changing the frontend service.
async function subscribeDevice(d) {
  d.status = 'CREATED'
  d.cdcReady = false
  const observedClient = {
    channel(topic) {
      const channel = d.client.channel(topic)
      channel.on('system', {}, (payload) => {
        log(`${d.label}: system ${JSON.stringify(payload)}`)
        if (payload.extension === 'postgres_changes') d.cdcReady = payload.status === 'ok'
      })
      const originalOn = channel.on.bind(channel)
      channel.on = (type, filter, callback) => originalOn(type, filter, (payload) => {
        if (payload.new?.local_id === fx.local) {
          d.events[filter.event] += 1
          log(`${d.label}: ${filter.event} jornada=${payload.new.id} topic=${topic}`)
        }
        callback(payload)
      })
      const originalSubscribe = channel.subscribe.bind(channel)
      channel.subscribe = (callback) => originalSubscribe((status, error) => {
        d.status = status
        if (status !== 'SUBSCRIBED') d.cdcReady = false
        log(`${d.label}: ${status} topic=${topic}${error ? ' error=' + error.message : ''}`)
        callback(status)
      })
      return channel
    },
    removeChannel: (channel) => d.client.removeChannel(channel),
  }
  return subscribeToOperationalDay(observedClient, () => refresh(d),
    () => log(`${d.label}: error de conexión`), { channelName: 'e9-local-operational-day' })
}
const ready = (d) => d.status === 'SUBSCRIBED' && d.cdcReady && d.pending === 0 && d.state !== 'desconocido'
const diagnostic = () => devices.map((d) => `${d.label}=${d.status}/CDC=${d.cdcReady}/${d.state} INSERT=${d.events.INSERT} UPDATE=${d.events.UPDATE}`).join(' ')

const handles = []
let openedId = null
try {
  for (const d of devices) {
    handles.push(await subscribeDevice(d))
  }
  const initialReady = await waitAll((d) => ready(d) && d.state === 'CERRADA', 60000)
  check('Suscripción inicial: cinco SUBSCRIBED + CDC confirmado y snapshot cerrado', initialReady >= 0, diagnostic())
  if (initialReady < 0) throw new Error('No se abre la jornada sin cinco canales SUBSCRIBED con CDC confirmado.')

  const opened = unwrap(await adminDevice.service.open(adminDevice.context, randomUUID()), 'abrir')
  openedId = opened.id
  const tOpen = await waitAll((d) => d.events.INSERT > 0 && d.state === 'ABIERTA' && d.dayId === opened.id)
  check('TP22 apertura recibida sin refrescar por MOZO, COCINA, CAJA y el segundo ADMIN', tOpen >= 0, `${tOpen} ms (${opened.identificacion}); ${diagnostic()}`)
  const again = unwrap(await devices[1].service.open(devices[1].context, randomUUID()), 'abrir de nuevo')
  check('TP22 apertura idempotente desde el segundo ADMIN', again.yaExistia && again.id === opened.id, `ya_existia=${again.yaExistia}`)

  const mozo = devices[2]
  await handles[2].stop()
  handles[2] = await subscribeDevice(mozo)
  if (await waitAll(ready, 60000) < 0) throw new Error('Remontaje sin SUBSCRIBED.')
  const beforeIdle = restRequests
  await sleep(10000)
  check('TP21 sin polling: 10 s sin señales no generan peticiones REST', restRequests === beforeIdle, `${restRequests - beforeIdle} peticiones`)
  const cocina = devices[3]
  cocina.client.realtime.disconnect()
  if (await waitAll((d) => d !== cocina || d.status !== 'SUBSCRIBED') < 0) throw new Error('No se observó desconexión.')
  const beforeReconnect = cocina.refetches
  cocina.client.realtime.connect()
  const start = Date.now(); let tReconnect = -1
  while (Date.now() - start < 15000) { if (ready(cocina) && cocina.refetches > beforeReconnect) { tReconnect = Date.now() - start; break } await sleep(50) }
  check('TP21 la reconexión resincroniza el estado autoritativo', tReconnect >= 0, `${tReconnect} ms`)

  const closed = unwrap(await adminDevice.service.close(adminDevice.context, opened.id), 'cerrar')
  openedId = null
  const tClose = await waitAll((d) => d.events.UPDATE > 0 && d.state === 'CERRADA')
  check('TP22 cierre recibido sin refrescar por los cinco clientes (incluido el mozo remontado, topic único)', tClose >= 0 && !closed.yaEstabaCerrada, `${tClose} ms; ${diagnostic()}`)
} catch (error) {
  check('Ejecución sin excepciones', false, error instanceof Error ? error.message : String(error))
} finally {
  for (const h of handles) await h.stop()
  if (openedId !== null) await adminDevice.service.close(adminDevice.context, openedId)
  const failed = results.filter((r) => !r.ok)
  log(`RESUMEN ${results.length - failed.length}/${results.length} PASS${failed.length ? ' — FALLAS: ' + failed.map((r) => r.id).join('; ') : ''}`)
  process.exit(failed.length ? 1 : 0)
}
