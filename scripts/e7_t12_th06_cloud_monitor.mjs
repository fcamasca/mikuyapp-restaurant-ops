// E7-T12/TH06 — Monitor Realtime de SÓLO LECTURA contra el Supabase cloud del Preview (DEV).
// Inicia sesión como el MOZO de pruebas (.env.local: H2_MOZO_EMAIL/H2_MOZO_PASSWORD, nunca se imprimen), se suscribe
// con el mismo servicio del frontend (subscribeToOperationsChanges) y registra: estado del canal, cada señal de
// detalle_pedido/pedido/mesa (tabla, evento, id, estado) y el tablero de mesas autoritativo tras cada refetch.
// No escribe nada en la base. Uso: scripts\e7_t12_th06_cloud.cmd, y mientras corre (15 min) ejecutar TH06 en el Preview.
import { appendFileSync, writeFileSync } from 'node:fs'
import { randomUUID } from 'node:crypto'
import { createClient } from '@supabase/supabase-js'
import { maskProjectRef, readLocalLinkedProjectRef, validateEnvironmentConfiguration } from './environmentGuard.mjs'
import { subscribeToOperationsChanges } from '../src/services/operationsRealtimeService.ts'
import { createWaiterOrderService } from '../src/services/waiterOrderService.ts'

const logFile = new URL('../e7-t12-th06-cloud.log', import.meta.url)
writeFileSync(logFile, '')
const log = (message) => {
  const now = new Date(); const line = `${now.toISOString().slice(11, 23)} ${message}`
  console.log(line); appendFileSync(logFile, `${line}\n`)
}
const guard = validateEnvironmentConfiguration(process.env, await readLocalLinkedProjectRef())
if (guard.logicalEnvironment !== 'DEV') throw new Error('Monitor sólo para el ambiente lógico DEV del Preview.')
log(`Destino: Supabase ${maskProjectRef(guard.effectiveRef)} (estado ${guard.state}, ${guard.logicalEnvironment}); modo sólo lectura`)

const client = createClient(process.env.VITE_SUPABASE_URL, process.env.VITE_SUPABASE_PUBLISHABLE_KEY, { auth: { persistSession: false, autoRefreshToken: true } })
const login = await client.auth.signInWithPassword({ email: process.env.H2_MOZO_EMAIL, password: process.env.H2_MOZO_PASSWORD })
if (login.error) throw new Error(`login MOZO: ${login.error.message}`)
const profile = await client.from('perfil_usuario').select('id,local_id,nombre,activo,rol:rol_id(id,codigo,activo)').eq('id', login.data.user.id).single()
if (profile.error || profile.data.rol?.codigo !== 'MOZO') throw new Error('perfil MOZO no válido')
const context = { profile: { ...profile.data, rol_id: profile.data.rol.id }, role: profile.data.rol, local: { id: profile.data.local_id, activo: true } }
const waiter = createWaiterOrderService(client)
client.auth.onAuthStateChange((event) => log(`auth ${event}`))

// Canal crudo: registra cada evento que Realtime entrega a esta sesión MOZO (con RLS aplicada).
const raw = client.channel(`th06-monitor-raw-${randomUUID().slice(0, 6)}`)
for (const table of ['detalle_pedido', 'pedido', 'mesa']) {
  for (const event of ['INSERT', 'UPDATE']) {
    raw.on('postgres_changes', { event, schema: 'public', table }, (signal) => {
      log(`SEÑAL ${table} ${event} id=${signal.new?.id ?? '?'} estado=${signal.new?.estado ?? '?'} (antes=${signal.old?.estado ?? 'n/d'}) commit=${signal.commit_timestamp}`)
    })
  }
}
raw.subscribe((status, error) => log(`canal crudo: ${status}${error ? ` ${error.message}` : ''}`))

// Mismo servicio y patrón que WaiterTablesPage: señal -> refetch autoritativo.
const handle = await subscribeToOperationsChanges(client, async () => {
  const board = await waiter.getTableBoard(context)
  log(board.ok ? `refetch tablero: ${board.data.map((t) => `${t.codigo}:${t.estado}${t.pedido ? `#${t.pedido.id}(${t.pedido.estado})` : ''}`).join(' ')}` : `refetch error: ${board.error.message}`)
}, () => log('servicio: error de conexión Realtime'), { channelName: `th06-monitor-${randomUUID().slice(0, 6)}`, initialRefresh: true })

log('Monitor activo 15 minutos. Ejecuta ahora TH06 en el Preview (entrega y cobro total).')
await new Promise((resolve) => setTimeout(resolve, 15 * 60 * 1000))
await handle.stop(); await client.removeChannel(raw); await client.auth.signOut()
log('== FIN monitor')
process.exit(0)
