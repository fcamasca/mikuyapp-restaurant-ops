import { createClient } from '@supabase/supabase-js'

const url = process.env.VITE_SUPABASE_URL?.trim()
const publishableKey = process.env.VITE_SUPABASE_PUBLISHABLE_KEY?.trim()

if (!url || !publishableKey) {
  console.error('TP-14/TP-17: faltan las variables públicas requeridas.')
  process.exit(1)
}

const supabase = createClient(url, publishableKey, {
  auth: {
    autoRefreshToken: false,
    detectSessionInUrl: false,
    persistSession: false,
  },
})

const expectedCounts = {
  local: 1,
  mesa: 6,
  categoria: 5,
  producto: 10,
}

const selections = {
  local: 'id,codigo,nombre,activo',
  mesa: 'id,local_id,codigo,nombre,estado,activo',
  categoria: 'id,local_id,codigo,nombre,orden,activo',
  producto: 'id,local_id,categoria_id,codigo,nombre,precio,activo',
}

function isPermissionDenial(error) {
  return error?.code === '42501'
    || /permission denied|row-level security/i.test(error?.message ?? '')
}

function assertPermissionDenied(label, error) {
  if (!error) {
    throw new Error(`${label}: la operación fue permitida inesperadamente.`)
  }
  if (!isPermissionDenial(error)) {
    throw new Error(`${label}: el rechazo no provino de permisos o RLS.`)
  }
  console.log(`${label}: rechazada por permisos/RLS.`)
}

async function readPublicData() {
  const snapshot = {}

  for (const table of Object.keys(expectedCounts)) {
    let query = supabase.from(table).select(selections[table]).eq('activo', true)
    if (table === 'categoria') {
      query = query.order('orden').order('codigo')
    } else if (table === 'producto') {
      query = query.order('categoria_id').order('codigo')
    } else {
      query = query.order('codigo')
    }

    const { data, error } = await query
    if (error) {
      throw new Error(`TP-14 ${table}: la lectura anónima falló.`)
    }
    if (data.length !== expectedCounts[table]) {
      throw new Error(`TP-14 ${table}: se esperaban ${expectedCounts[table]} filas y se obtuvieron ${data.length}.`)
    }

    snapshot[table] = data
    console.log(`TP-14 ${table}: ${data.length} filas activas.`)
  }

  return snapshot
}

async function verifyPrivateReadDenied() {
  const { error } = await supabase.from('pedido').select('id').limit(1)
  assertPermissionDenied('TP-14 pedido SELECT', error)
}

async function verifyWritesDenied(snapshot) {
  const local = snapshot.local[0]
  const table = snapshot.mesa[0]
  const category = snapshot.categoria[0]
  const product = snapshot.producto[0]
  const missingUuid = '00000000-0000-0000-0000-000000000000'

  const operations = [
    ['local INSERT', supabase.from('local').insert({ codigo: local.codigo, nombre: 'Control T-12', activo: true })],
    ['local UPDATE', supabase.from('local').update({ nombre: 'Control T-12' }).eq('id', missingUuid)],
    ['local DELETE', supabase.from('local').delete().eq('id', missingUuid)],
    ['mesa INSERT', supabase.from('mesa').insert({ local_id: table.local_id, codigo: table.codigo, nombre: 'Control T-12', estado: 'LIBRE', activo: true })],
    ['mesa UPDATE', supabase.from('mesa').update({ nombre: 'Control T-12' }).eq('id', missingUuid)],
    ['mesa DELETE', supabase.from('mesa').delete().eq('id', missingUuid)],
    ['categoria INSERT', supabase.from('categoria').insert({ local_id: category.local_id, codigo: category.codigo, nombre: 'Control T-12', orden: 999, activo: true })],
    ['categoria UPDATE', supabase.from('categoria').update({ nombre: 'Control T-12' }).eq('id', missingUuid)],
    ['categoria DELETE', supabase.from('categoria').delete().eq('id', missingUuid)],
    ['producto INSERT', supabase.from('producto').insert({ local_id: product.local_id, categoria_id: product.categoria_id, codigo: product.codigo, nombre: 'Control T-12', precio: 0, activo: true })],
    ['producto UPDATE', supabase.from('producto').update({ nombre: 'Control T-12' }).eq('id', missingUuid)],
    ['producto DELETE', supabase.from('producto').delete().eq('id', missingUuid)],
    ['pedido INSERT', supabase.from('pedido').insert({ local_id: local.id, mesa_id: table.id, creado_por: missingUuid, estado: 'ABIERTO' })],
    ['pedido UPDATE', supabase.from('pedido').update({ estado: 'ANULADO' }).eq('id', -1)],
    ['pedido DELETE', supabase.from('pedido').delete().eq('id', -1)],
  ]

  for (const [label, operation] of operations) {
    const { error } = await operation
    assertPermissionDenied(`TP-17 ${label}`, error)
  }
}

function stableIdentitySnapshot(snapshot) {
  return JSON.stringify(
    Object.fromEntries(
      Object.entries(snapshot).map(([table, rows]) => [
        table,
        rows.map(({ id, codigo }) => ({ id, codigo })),
      ]),
    ),
  )
}

try {
  const before = await readPublicData()
  const beforeIdentitySnapshot = stableIdentitySnapshot(before)
  await verifyPrivateReadDenied()
  await verifyWritesDenied(before)
  const after = await readPublicData()
  const afterIdentitySnapshot = stableIdentitySnapshot(after)

  if (beforeIdentitySnapshot !== afterIdentitySnapshot) {
    throw new Error('TP-17: los conteos o identificadores cambiaron durante la prueba.')
  }

  console.log('TP-17 comparación anterior/posterior: datos sin cambios.')
  console.log('TP-14 y TP-17: aprobadas.')
} catch (error) {
  const message = error instanceof Error ? error.message : 'Fallo no identificado.'
  console.error(message)
  process.exitCode = 1
}
