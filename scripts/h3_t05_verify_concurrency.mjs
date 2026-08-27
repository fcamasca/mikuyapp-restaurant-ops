import { createClient } from '@supabase/supabase-js'

const url = process.env.VITE_SUPABASE_URL?.trim()
const key = process.env.VITE_SUPABASE_PUBLISHABLE_KEY?.trim()
const email = process.env.H2_MOZO_EMAIL?.trim()
const password = process.env.H2_MOZO_PASSWORD?.trim()

if (!url || !key || !email || !password) {
  throw new Error('Faltan variables para verificar concurrencia H3-T05')
}

function createWaiterClient() {
  return createClient(url, key, {
    auth: {
      autoRefreshToken: false,
      detectSessionInUrl: false,
      persistSession: false,
    },
  })
}

const clients = [createWaiterClient(), createWaiterClient()]

for (const client of clients) {
  const { data, error } = await client.auth.signInWithPassword({ email, password })
  if (error || !data.session) {
    throw new Error('No se pudo autenticar una sesión MOZO para H3-T05')
  }
}

const results = await Promise.all(
  clients.map((client) => client.rpc('enviar_pedido_cocina', {
    p_pedido_id: -95501,
  })),
)

for (const result of results) {
  if (result.error || !Array.isArray(result.data) || result.data.length !== 1) {
    throw new Error(`Envío concurrente inválido: ${result.error?.message ?? 'respuesta inesperada'}`)
  }
}

const rows = results.map((result) => result.data[0])
const sentCounts = rows.map((row) => row.detalles_enviados).sort((a, b) => a - b)
const headerChanges = rows.filter((row) => row.cabecera_actualizada === true).length

if (sentCounts[0] !== 0 || sentCounts[1] !== 1 || headerChanges !== 1) {
  throw new Error(
    `Concurrencia incorrecta: enviados=${sentCounts.join(',')}, cabeceras=${headerChanges}`,
  )
}

const { data: orders, error: orderError } = await clients[0]
  .from('pedido')
  .select('estado,enviado_en')
  .eq('id', -95501)
  .limit(1)

const { data: details, error: detailError } = await clients[0]
  .from('detalle_pedido')
  .select('estado')
  .eq('id', -95511)
  .limit(1)

if (orderError || detailError || orders?.length !== 1 || details?.length !== 1
  || orders[0].estado !== 'ENVIADO' || !orders[0].enviado_en
  || details[0].estado !== 'ENVIADO') {
  throw new Error('Estado final concurrente inconsistente')
}

await Promise.all(clients.map((client) => client.auth.signOut()))

console.log('H3-T05 concurrencia aprobada: enviados=1/0, una transición de cabecera')
