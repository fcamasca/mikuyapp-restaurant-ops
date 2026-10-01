// E9 — TP22 con clientes Realtime programáticos contra un servidor Supabase real (lo que el entorno local
// no puede cubrir: no hay servidor Realtime local). Verifica que ADMIN, MOZO, COCINA y CAJA reciben la
// apertura y el cierre de la jornada sin refrescar, con un segundo ADMIN, remontaje con topic único,
// reconexión y ausencia de polling. Usa los servicios reales del frontend (operationalDayService).
//
// Uso (raíz del repo, en un ambiente DEV preparado y autorizado según DC-12, con las migraciones E9 aplicadas):
//   node --env-file=.env.local --experimental-strip-types scripts/e9_realtime_verificacion.mjs
// Requiere en .env.local los usuarios de prueba H2_ADMIN/H2_MOZO/H2_COCINA/H2_CAJA (EMAIL y PASSWORD).
// Precondición: el local de prueba debe estar CERRADO al iniciar; el script abre una jornada y la cierra,
// dejando el local cerrado como lo encontró. Si el local está abierto, aborta sin cambiar nada.
// Nunca se ejecuta contra PROD: exige ambiente lógico DEV y el ref DEV esperado. Escribe e9-realtime-verificacion.log.
import { appendFileSync, writeFileSync } from 'node:fs'
import { randomUUID } from 'node:crypto'
import { createClient } from '@supabase/supabase-js'
import { readLocalLinkedProjectRef, validateEnvironmentConfiguration, maskProjectRef } from './environmentGuard.mjs'
import { createOperationalDayService, subscribeToOperationalDay } from '../src/services/operationalDayService.ts'

const LOG = 'e9-realtime-verificacion.log'
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

let restRequests = 0
const countingFetch = (...args) => { if (String(args[0]).includes('/rest/v1/')) restRequests += 1; return fetch(...args) }
async function device(email, password, label, codigo) {
  const client = createClient(url, key, { auth: { persistSession: false, autoRefreshToken: false }, global: { fetch: countingFetch } })
  const session = must(await client.auth.signInWithPassword({ email, password }), `login ${label}`)
  const profile = must(await client.from('perfil_usuario').select('id,local_id,nombre').eq('id', session.user.id).single(), `perfil ${label}`)
  const context = { profile: { id: session.user.id, local_id: profile.local_id, rol_id: 0, nombre: profile.nombre, activo: true },
    role: { id: 0, codigo, activo: true }, local: { id: profile.local_id, nombre: 'DEV', activo: true } }
  return { client, label, context, service: createOperationalDayService(client), state: 'desconocido', dayId: null, refetches: 0 }
}

const e = process.env
const devices = [
  await device(e.H2_ADMIN_EMAIL, e.H2_ADMIN_PASSWORD, 'admin-1', 'ADMINISTRADOR'),
  await device(e.H2_ADMIN_EMAIL, e.H2_ADMIN_PASSWORD, 'admin-2', 'ADMINISTRADOR'),
  await device(e.H2_MOZO_EMAIL, e.H2_MOZO_PASSWORD, 'mozo', 'MOZO'),
  await device(e.H2_COCINA_EMAIL, e.H2_COCINA_PASSWORD, 'cocina', 'COCINA'),
  await device(e.H2_CAJA_EMAIL, e.H2_CAJA_PASSWORD, 'caja', 'CAJA'),
]
const [admin] = devices

// ===== Precondiciones: migraciones E9 aplicadas y local CERRADO
const probe = await admin.client.rpc('rpc_cerrar_jornada_operativa', { p_jornada_operativa_id: null })
if (probe.error?.code !== '22023') throw new Error(`Migraciones E9 no aplicadas (respuesta ${probe.error?.code ?? 'sin error'}).`)
const initial = unwrap(await admin.service.getCurrent(), 'estado inicial')
if (initial) throw new Error(`El local está abierto (${initial.identificacion}). El script no cierra jornadas ajenas: ciérrela desde la UI o use otro ambiente.`)
log('Precondiciones OK: migraciones E9 aplicadas; local cerrado.')

async function refresh(d) {
  d.refetches += 1
  const r = await d.service.getCurrent()
  if (r.ok) { d.state = r.data ? 'ABIERTA' : 'CERRADA'; d.dayId = r.data?.id ?? null }
}
async function waitAll(predicate, timeoutMs = 10000) {
  const start = Date.now()
  while (Date.now() - start < timeoutMs) { if (devices.every(predicate)) return Date.now() - start; await sleep(50) }
  return -1
}

const handles = []
try {
  for (const d of devices) {
    handles.push(await subscribeToOperationalDay(d.client, () => refresh(d), () => log(`${d.label}: error de conexión`), { channelName: 'e9-dev-operational-day' }))
  }
  await waitAll((d) => d.state === 'CERRADA')
  check('Suscripción inicial: los cinco clientes ven el local cerrado', devices.every((d) => d.state === 'CERRADA'), devices.map((d) => `${d.label}=${d.state}`).join(' '))

  // Apertura
  const opened = unwrap(await admin.service.open(admin.context, randomUUID()), 'abrir')
  const tOpen = await waitAll((d) => d.state === 'ABIERTA' && d.dayId === opened.id)
  check('TP22 apertura: MOZO, COCINA, CAJA y el segundo ADMIN la reciben sin refrescar', tOpen >= 0, `${tOpen} ms (${opened.identificacion})`)
  const again = unwrap(await devices[1].service.open(devices[1].context, randomUUID()), 'abrir de nuevo')
  check('TP22 apertura idempotente desde el segundo ADMIN', again.yaExistia && again.id === opened.id, `ya_existia=${again.yaExistia}`)

  // Remontaje con el mismo nombre de canal (topic único) y ausencia de polling
  const mozo = devices[2]
  await handles[2].stop()
  handles[2] = await subscribeToOperationalDay(mozo.client, () => refresh(mozo), () => log('mozo remontado: error'), { channelName: 'e9-dev-operational-day' })
  const beforeIdle = restRequests
  await sleep(10000)
  check('TP21/TP22 sin polling: 10 s sin señales no generan peticiones REST', restRequests === beforeIdle, `${restRequests - beforeIdle} peticiones`)
  const cocina = devices[3]
  cocina.client.realtime.disconnect()
  await sleep(1500)
  const beforeReconnect = cocina.refetches
  cocina.client.realtime.connect()
  const tReconnect = await (async () => { const start = Date.now(); while (Date.now() - start < 15000) { if (cocina.refetches > beforeReconnect) return Date.now() - start; await sleep(50) } return -1 })()
  check('TP21 reconexión resincroniza el estado autoritativo', tReconnect >= 0, `${tReconnect} ms`)

  // Cierre (sin pendientes: el script no crea pedidos ni sesiones)
  const closed = unwrap(await admin.service.close(admin.context, opened.id), 'cerrar')
  const tClose = await waitAll((d) => d.state === 'CERRADA')
  check('TP22 cierre: los cinco clientes (incluido el mozo remontado) pasan a local cerrado sin refrescar', tClose >= 0 && !closed.yaEstabaCerrada, `${tClose} ms`)
} finally {
  for (const h of handles) await h.stop()
  const failed = results.filter((r) => !r.ok)
  log(`RESUMEN ${results.length - failed.length}/${results.length} PASS${failed.length ? ' — FALLAS: ' + failed.map((r) => r.id).join('; ') : ''}`)
  process.exit(failed.length ? 1 : 0)
}
