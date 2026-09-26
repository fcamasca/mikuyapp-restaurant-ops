// E7-T12/TH06 — Experimento LOCAL (loopback): ¿qué pasa si una vista se desmonta y se vuelve a montar con el mismo
// nombre de canal antes de que Realtime confirme la salida del canal anterior? (p. ej. recarga del contexto de perfil
// tras TOKEN_REFRESHED, que desmonta WaiterOrderPage/WaiterTablesPage). Usa supabase-js y subscribeToOperationsChanges reales.
import { execFileSync } from 'node:child_process'
import { randomBytes, randomUUID } from 'node:crypto'
import { createClient } from '@supabase/supabase-js'
import { subscribeToOperationsChanges } from '../src/services/operationsRealtimeService.ts'

const url = process.env.E7_VALIDATION_SUPABASE_URL?.trim()
const anonKey = process.env.E7_VALIDATION_PUBLISHABLE_KEY?.trim()
const serviceKey = process.env.E7_VALIDATION_SERVICE_ROLE_KEY?.trim()
if (!url || !anonKey || !serviceKey) throw new Error('Faltan variables E7_VALIDATION_*')
if (!['127.0.0.1', 'localhost', '::1'].includes(new URL(url).hostname)) throw new Error('Sólo stack local (loopback).')
const sql = (text) => execFileSync('docker', ['exec', '-i', '-e', 'PGPASSWORD=postgres', 'supabase_db_mikuyapp-restaurant-ops', 'psql', '-h', '127.0.0.1',
  '-U', 'postgres', '-d', 'postgres', '-X', '-At', '-v', 'ON_ERROR_STOP=1'], { input: text, encoding: 'utf8' }).trim()
const sleep = (ms) => new Promise((r) => setTimeout(r, ms))
const run = randomUUID().slice(0, 8)
const password = randomBytes(18).toString('base64url')
const admin = createClient(url, serviceKey, { auth: { persistSession: false, autoRefreshToken: false } })
const email = `e7-th06-race-${run}@example.invalid`
const created = await admin.auth.admin.createUser({ email, password, email_confirm: true })
if (created.error) throw new Error(created.error.message)
const mesa = sql(`with l as (insert into public.local (codigo, nombre) values ('E7-RACE-${run}', 'Race ${run}') returning id),
 p as (insert into public.perfil_usuario (id, local_id, rol_id, nombre) select '${created.data.user.id}', l.id, r.id, 'Mozo' from l, public.rol r where r.codigo = 'MOZO' returning id)
insert into public.mesa (local_id, codigo, nombre) select l.id, 'R1', 'Mesa race' from l, p returning id;`).split(/\r?\n/)[0]
const mozo = createClient(url, anonKey, { auth: { persistSession: false, autoRefreshToken: false } })
if ((await mozo.auth.signInWithPassword({ email, password })).error) throw new Error('login')
const topics = () => mozo.getChannels().map((c) => `${c.topic.replace('realtime:', '')}=${c.state}`).join(' ') || 'ninguno'
const touch = async (label) => { sql(`update public.mesa set nombre = 'Mesa race ${label}' where id = '${mesa}'`); await sleep(2500) }

async function scenario(label, sameName) {
  const name = `waiter-order-race-${run}`
  let first = 0, second = 0, secondStatus = []
  const h1 = await subscribeToOperationsChanges(mozo, async () => { first += 1 }, () => {}, { channelName: name, initialRefresh: false })
  await sleep(2500)
  first = 0
  // Desmontaje (cleanup sin await, como en React) y remontaje inmediato.
  void h1.stop()
  const h2name = sameName ? name : `${name}-${randomUUID().slice(0, 6)}`
  console.log(`[${label}] al remontar: ${topics()}`)
  const h2 = await subscribeToOperationsChanges(mozo, async () => { second += 1 }, () => { secondStatus.push('error') }, { channelName: h2name, initialRefresh: false })
  await sleep(2500)
  console.log(`[${label}] tras 2,5 s: ${topics()}`)
  second = 0
  await touch(label)
  console.log(`[${label}] UPDATE mesa -> refetch vista remontada=${second} (vista desmontada=${first}) errores=${secondStatus.length}`)
  await h2.stop(); await sleep(1000)
  return second
}
const same = await scenario('mismo nombre de canal', true)
const unique = await scenario('nombre único por montaje', false)
await mozo.auth.signOut()
console.log(same === 0 && unique > 0
  ? '== RACE CONFIRMADA: al remontar con el mismo nombre la vista queda sin señales; con nombre único sí las recibe'
  : `== RACE NO REPRODUCIDA (mismo=${same}, único=${unique})`)
