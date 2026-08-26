import { createClient } from '@supabase/supabase-js'
import { randomUUID } from 'node:crypto'

const url = process.env.VITE_SUPABASE_URL?.trim()
const key = process.env.VITE_SUPABASE_PUBLISHABLE_KEY?.trim()
const roles = {
  ADMINISTRADOR: ['H2_ADMIN_EMAIL', 'H2_ADMIN_PASSWORD'],
  MOZO: ['H2_MOZO_EMAIL', 'H2_MOZO_PASSWORD'],
  COCINA: ['H2_COCINA_EMAIL', 'H2_COCINA_PASSWORD'],
  CAJA: ['H2_CAJA_EMAIL', 'H2_CAJA_PASSWORD'],
}

const required = ['VITE_SUPABASE_URL', 'VITE_SUPABASE_PUBLISHABLE_KEY', ...Object.values(roles).flat()]
const missing = required.filter((name) => !process.env[name]?.trim())
if (!url || !key || missing.length) {
  console.error(`T19 bloqueada: faltan variables locales (${missing.join(', ')}).`)
  process.exit(1)
}

const clients = new Map()
const contexts = new Map()
const stamp = `${Date.now().toString(36)}${Math.random().toString(36).slice(2, 7)}`.toUpperCase()
const codes = { category: `H2T19-C-${stamp}`, product: `H2T19-P-${stamp}`, table: `H2T19-M-${stamp}` }
const created = { category: null, product: null, table: null }
let failures = 0
let skipped = 0

function client() {
  return createClient(url, key, { auth: { autoRefreshToken: false, detectSessionInUrl: false, persistSession: false } })
}

function pass(label) { console.log(`OK ${label}`) }
function skip(label, reason) { skipped += 1; console.log(`PENDIENTE ${label}: ${reason}`) }
function fail(label) { failures += 1; console.error(`FALLO ${label}`) }
function denied(error) { return Boolean(error) && (error.code === '42501' || /permission denied|row-level security|violates row-level/i.test(error.message ?? '')) }
function restricted(error) { return Boolean(error) && error.code === '23503' }

async function expectDenied(label, request) {
  const { error } = await request
  if (denied(error)) pass(label); else fail(label)
}

async function expectDeniedOrNoRows(label, request) {
  const { data, error } = await request
  if (denied(error) || (!error && Array.isArray(data) && data.length === 0)) pass(label)
  else fail(label)
}

async function expectNoRows(label, request) {
  const { data, error } = await request
  if (!error && Array.isArray(data) && data.length === 0) pass(label); else fail(label)
}

async function authenticateAll() {
  for (const [role, [emailName, passwordName]] of Object.entries(roles)) {
    const instance = client()
    const { data, error } = await instance.auth.signInWithPassword({
      email: process.env[emailName],
      password: process.env[passwordName],
    })
    if (error || !data.session) throw new Error(`No se pudo autenticar el rol ${role}.`)
    clients.set(role, instance)
    pass(`login ${role}`)

    const { data: contextRows, error: contextError } = await instance.rpc('h2_auth_context')
    if (contextError || contextRows?.length !== 1 || contextRows[0].rol_codigo !== role) {
      throw new Error(`Contexto inválido para ${role}.`)
    }
    contexts.set(role, contextRows[0])
    pass(`h2_auth_context ${role}`)

    const { data: profiles, error: profileError } = await instance.from('perfil_usuario').select('id,local_id,rol_id,nombre,activo')
    if (profileError || profiles?.length !== 1 || !profiles[0].activo
      || profiles[0].local_id !== contextRows[0].local_id || profiles[0].rol_id !== contextRows[0].rol_id) {
      throw new Error(`Perfil propio inválido para ${role}.`)
    }
    pass(`perfil propio exclusivo ${role}`)

    const { data: roleRows, error: roleError } = await instance.from('rol').select('id,codigo,activo')
    const { data: localRows, error: localError } = await instance.from('local').select('id,activo')
    if (roleError || localError || roleRows?.length !== 1 || localRows?.length !== 1
      || roleRows[0].codigo !== role || !roleRows[0].activo || !localRows[0].activo) {
      throw new Error(`Rol/local no exclusivo para ${role}.`)
    }
    pass(`rol y local propios ${role}`)
  }
}

async function verifyPrivateResources() {
  for (const [role, instance] of clients) {
    const context = contexts.get(role)
    await expectDenied(`${role} no modifica perfil`, instance.from('perfil_usuario').update({ activo: false }).eq('id', randomUUID()))
    await expectDenied(`${role} no modifica rol`, instance.from('rol').update({ activo: false }).eq('id', context.rol_id))
    await expectDenied(`${role} no modifica local`, instance.from('local').update({ activo: false }).eq('id', context.local_id))
    for (const table of ['pedido', 'detalle_pedido', 'historial_estado', 'pago']) {
      await expectDenied(`${role} sin acceso a ${table}`, instance.from(table).select('id').limit(1))
    }
  }
}

async function verifyReadMatrix() {
  for (const [role, instance] of clients) {
    const { data: categories, error: categoryError } = await instance.from('categoria').select('id,activo')
    const { data: products, error: productError } = await instance.from('producto').select('id,activo,categoria_id')
    if (categoryError || productError) fail(`${role} lectura de carta`)
    else if (role !== 'ADMINISTRADOR' && (categories.some((row) => !row.activo) || products.some((row) => !row.activo))) fail(`${role} filtro de inactivos`)
    else pass(`${role} lectura de carta autorizada`)

    const { data: tables, error: tableError } = await instance.from('mesa').select('id,activo,estado')
    if (role === 'COCINA' || role === 'CAJA') {
      if (!tableError && tables?.length === 0) pass(`${role} no consulta mesas`); else fail(`${role} no consulta mesas`)
    } else if (tableError || (role === 'MOZO' && tables.some((row) => !row.activo))) fail(`${role} lectura de mesas`)
    else pass(`${role} lectura de mesas`)
  }
}

async function verifyNonAdminMutations() {
  for (const role of ['MOZO', 'COCINA', 'CAJA']) {
    const instance = clients.get(role)
    const localId = contexts.get(role).local_id
    await expectDenied(`${role} no inserta categoría`, instance.from('categoria').insert({ local_id: localId, codigo: codes.category, nombre: 'Control T19', orden: 999, activo: true }))
    await expectDeniedOrNoRows(`${role} no actualiza categoría`, instance.from('categoria').update({ nombre: 'Control T19' }).eq('codigo', codes.category).select('id'))
    await expectDeniedOrNoRows(`${role} no elimina categoría`, instance.from('categoria').delete().eq('codigo', codes.category).select('id'))
    await expectDenied(`${role} no inserta producto`, instance.from('producto').insert({ local_id: localId, categoria_id: randomUUID(), codigo: codes.product, nombre: 'Control T19', precio: 1, activo: true }))
    await expectDeniedOrNoRows(`${role} no actualiza producto`, instance.from('producto').update({ nombre: 'Control T19' }).eq('codigo', codes.product).select('id'))
    await expectDeniedOrNoRows(`${role} no elimina producto`, instance.from('producto').delete().eq('codigo', codes.product).select('id'))
    await expectDenied(`${role} no inserta mesa`, instance.from('mesa').insert({ local_id: localId, codigo: codes.table, nombre: 'Control T19', activo: true }))
    await expectDeniedOrNoRows(`${role} no actualiza mesa`, instance.from('mesa').update({ nombre: 'Control T19' }).eq('codigo', codes.table).select('id'))
    await expectDeniedOrNoRows(`${role} no elimina mesa`, instance.from('mesa').delete().eq('codigo', codes.table).select('id'))
  }
}

async function verifyAdministratorLifecycle() {
  const instance = clients.get('ADMINISTRADOR')
  const localId = contexts.get('ADMINISTRADOR').local_id

  let response = await instance.from('categoria').insert({ local_id: localId, codigo: codes.category, nombre: 'Control T19', orden: 999, activo: false }).select('id,codigo,nombre,orden,activo').single()
  if (response.error) throw new Error('No se pudo crear la categoría temporal.')
  created.category = response.data.id
  pass('ADMINISTRADOR crea categoría inactiva')
  response = await instance.from('categoria').update({ nombre: 'Control T19 editado', orden: 998, activo: true }).eq('id', created.category).select('id,nombre,orden,activo').single()
  if (response.error || !response.data.activo) throw new Error('No se pudo editar/activar la categoría temporal.')
  pass('ADMINISTRADOR edita y activa categoría')
  response = await instance.from('categoria').update({ activo: false }).eq('id', created.category).select('id,activo').single()
  if (response.error || response.data.activo) throw new Error('No se pudo desactivar la categoría temporal.')
  pass('ADMINISTRADOR desactiva categoría')
  await instance.from('categoria').update({ activo: true }).eq('id', created.category)

  response = await instance.from('producto').insert({ local_id: localId, categoria_id: created.category, codigo: codes.product, nombre: 'Control T19', precio: 1, activo: false }).select('id,activo').single()
  if (response.error) throw new Error('No se pudo crear el producto temporal.')
  created.product = response.data.id
  pass('ADMINISTRADOR crea producto inactivo')
  response = await instance.from('producto').update({ nombre: 'Control T19 editado', precio: 2, categoria_id: created.category, activo: true }).eq('id', created.product).select('id,activo').single()
  if (response.error || !response.data.activo) throw new Error('No se pudo editar/activar el producto temporal.')
  pass('ADMINISTRADOR edita y activa producto')
  response = await instance.from('producto').update({ activo: false }).eq('id', created.product).select('id,activo').single()
  if (response.error || response.data.activo) throw new Error('No se pudo desactivar el producto temporal.')
  pass('ADMINISTRADOR desactiva producto')
  await instance.from('producto').update({ activo: true }).eq('id', created.product)

  const dependency = await instance.from('categoria').delete().eq('id', created.category)
  if (restricted(dependency.error)) pass('categoría con producto no se elimina'); else fail('categoría con producto no se elimina')

  response = await instance.from('mesa').insert({ local_id: localId, codigo: codes.table, nombre: 'Control T19', activo: true }).select('id,estado,activo').single()
  if (response.error || response.data.estado !== 'LIBRE') throw new Error('No se pudo crear mesa LIBRE temporal.')
  created.table = response.data.id
  pass('ADMINISTRADOR crea mesa con default LIBRE')
  response = await instance.from('mesa').update({ codigo: codes.table, nombre: 'Control T19 editado', activo: false }).eq('id', created.table).select('id,estado,activo').single()
  if (response.error || response.data.activo || response.data.estado !== 'LIBRE') throw new Error('No se pudo editar/desactivar la mesa temporal.')
  pass('ADMINISTRADOR edita y desactiva mesa LIBRE')
  response = await instance.from('mesa').update({ activo: true }).eq('id', created.table).select('id,estado,activo').single()
  if (response.error || !response.data.activo || response.data.estado !== 'LIBRE') throw new Error('No se pudo reactivar la mesa temporal.')
  pass('ADMINISTRADOR reactiva mesa sin alterar estado')
}

async function verifyProtectedColumns() {
  const instance = clients.get('ADMINISTRADOR')
  const originalCategory = await instance.from('categoria').select('id,nombre,local_id,creado_en').eq('id', created.category).single()
  const originalTable = await instance.from('mesa').select('id,nombre,local_id,estado,creado_en').eq('id', created.table).single()
  const attempts = [
    ['INSERT categoría con id', instance.from('categoria').insert({ id: randomUUID(), local_id: originalCategory.data.local_id, codigo: `${codes.category}-X`, nombre: 'Control', orden: 1, activo: true })],
    ['UPDATE categoría con local_id', instance.from('categoria').update({ nombre: 'No persistir', local_id: originalCategory.data.local_id }).eq('id', created.category)],
    ['UPDATE categoría con creado_en', instance.from('categoria').update({ nombre: 'No persistir', creado_en: new Date(0).toISOString() }).eq('id', created.category)],
    ['INSERT mesa con estado', instance.from('mesa').insert({ local_id: originalTable.data.local_id, codigo: `${codes.table}-X`, nombre: 'Control', activo: true, estado: 'OCUPADA' })],
    ['UPDATE mesa con estado', instance.from('mesa').update({ nombre: 'No persistir', estado: 'OCUPADA' }).eq('id', created.table)],
  ]
  for (const [label, request] of attempts) await expectDenied(label, request)

  const afterCategory = await instance.from('categoria').select('id,nombre,local_id,creado_en').eq('id', created.category).single()
  const afterTable = await instance.from('mesa').select('id,nombre,local_id,estado,creado_en').eq('id', created.table).single()
  if (JSON.stringify(originalCategory.data) === JSON.stringify(afterCategory.data)
    && JSON.stringify(originalTable.data) === JSON.stringify(afterTable.data)) pass('payloads mixtos sin cambios parciales')
  else fail('payloads mixtos sin cambios parciales')
  await expectNoRows('INSERT protegido no dejó categoría parcial', instance.from('categoria').select('id').eq('codigo', `${codes.category}-X`))
  await expectNoRows('INSERT protegido no dejó mesa parcial', instance.from('mesa').select('id').eq('codigo', `${codes.table}-X`))
}

async function verifyControlledFixtures() {
  const instance = clients.get('ADMINISTRADOR')
  const historyProduct = process.env.H2_HISTORY_PRODUCT_ID?.trim()
  const orderedTable = process.env.H2_ORDERED_TABLE_ID?.trim()
  const otherLocal = process.env.H2_OTHER_LOCAL_ID?.trim()
  const otherCategory = process.env.H2_OTHER_CATEGORY_ID?.trim()

  if (historyProduct) {
    const result = await instance.from('producto').delete().eq('id', historyProduct)
    if (restricted(result.error)) pass('producto con historial no se elimina'); else fail('producto con historial no se elimina')
  } else skip('TP-40', 'falta H2_HISTORY_PRODUCT_ID')

  if (orderedTable) {
    const before = await instance.from('mesa').select('id,activo,estado').eq('id', orderedTable).maybeSingle()
    if (!before.error && before.data && before.data.estado !== 'LIBRE') {
      await expectDenied('mesa no libre no se desactiva', instance.from('mesa').update({ activo: false }).eq('id', orderedTable))
      const after = await instance.from('mesa').select('id,activo,estado').eq('id', orderedTable).maybeSingle()
      if (JSON.stringify(before.data) === JSON.stringify(after.data)) pass('mesa no libre sin cambio parcial'); else fail('mesa no libre sin cambio parcial')
      const deletion = await instance.from('mesa').delete().eq('id', orderedTable)
      if (restricted(deletion.error)) pass('mesa con pedido no se elimina'); else fail('mesa con pedido no se elimina')
    } else skip('TP-46/TP-48', 'fixture no visible o no está en estado no libre')
  } else skip('TP-46/TP-48', 'falta H2_ORDERED_TABLE_ID')

  if (otherLocal && otherCategory) {
    await expectNoRows('aislamiento SELECT de otro local', instance.from('categoria').select('id').eq('id', otherCategory))
    await expectDenied('no inserta categoría en otro local', instance.from('categoria').insert({ local_id: otherLocal, codigo: `${codes.category}-L`, nombre: 'Control', orden: 1, activo: true }))
    await expectDenied('no asocia producto a categoría de otro local', instance.from('producto').insert({ local_id: contexts.get('ADMINISTRADOR').local_id, categoria_id: otherCategory, codigo: `${codes.product}-L`, nombre: 'Control', precio: 1, activo: true }))
  } else skip('TP-49', 'faltan H2_OTHER_LOCAL_ID y/o H2_OTHER_CATEGORY_ID')
}

async function cleanup() {
  const instance = clients.get('ADMINISTRADOR')
  if (!instance) return
  if (created.product) await instance.from('producto').delete().eq('id', created.product)
  if (created.category) await instance.from('categoria').delete().eq('id', created.category)
  if (created.table) await instance.from('mesa').delete().eq('id', created.table)
  const checks = await Promise.all([
    instance.from('producto').select('id').eq('codigo', codes.product),
    instance.from('categoria').select('id').eq('codigo', codes.category),
    instance.from('mesa').select('id').eq('codigo', codes.table),
  ])
  if (checks.every(({ data, error }) => !error && data.length === 0)) pass('limpieza completa de datos temporales')
  else fail('limpieza completa de datos temporales')
}

try {
  await authenticateAll()
  await verifyPrivateResources()
  await verifyReadMatrix()
  await verifyNonAdminMutations()
  await verifyAdministratorLifecycle()
  await verifyProtectedColumns()
  await verifyControlledFixtures()
} catch (error) {
  failures += 1
  console.error(error instanceof Error ? error.message : 'Fallo no identificado en T19.')
} finally {
  await cleanup()
  for (const [role, instance] of clients) {
    const { error } = await instance.auth.signOut()
    if (error) fail(`logout ${role}`); else pass(`logout ${role}`)
  }
}

console.log(`T19 resultado: ${failures} fallos, ${skipped} pruebas pendientes por fixtures.`)
if (failures) process.exitCode = 1
