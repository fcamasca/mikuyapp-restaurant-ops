import { createClient } from '@supabase/supabase-js'

const url = process.env.VITE_SUPABASE_URL?.trim()
const key = process.env.VITE_SUPABASE_PUBLISHABLE_KEY?.trim()
const email = process.env.H2_MOZO_EMAIL?.trim()
const password = process.env.H2_MOZO_PASSWORD?.trim()
const tableId = process.env.H3_T02_CONCURRENCY_TABLE_ID?.trim()

if (!url || !key || !email || !password || !tableId) {
  throw new Error('Faltan variables para verificar concurrencia H3-T02')
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
    throw new Error('No se pudo autenticar una sesión MOZO para H3-T02')
  }
}

const results = await Promise.all(
  clients.map((client) => client.rpc('crear_o_recuperar_pedido_mesa', {
    p_mesa_id: tableId,
  })),
)

for (const result of results) {
  if (result.error || !Array.isArray(result.data) || result.data.length !== 1) {
    throw new Error(`Solicitud concurrente inválida: ${result.error?.message ?? 'respuesta inesperada'}`)
  }
}

const rows = results.map((result) => result.data[0])
const orderIds = new Set(rows.map((row) => row.pedido_id))
const createdCount = rows.filter((row) => row.fue_creado === true).length

if (orderIds.size !== 1 || createdCount !== 1) {
  throw new Error(`Concurrencia incorrecta: pedidos=${orderIds.size}, creados=${createdCount}`)
}

console.log(`H3-T02 concurrencia aprobada: pedido=${rows[0].pedido_id}, creado=1, recuperado=1`)
