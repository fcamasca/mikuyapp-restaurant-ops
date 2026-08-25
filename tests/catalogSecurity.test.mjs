import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import { test } from 'node:test'
import { createCatalogService } from '../src/services/catalogService.ts'

const privilegeMigration = readFileSync(
  new URL('../supabase/migrations/20260825000200_h2_authenticated_table_privileges.sql', import.meta.url),
  'utf8',
)
const policyMigration = readFileSync(
  new URL('../supabase/migrations/20260825000300_h2_authenticated_rls_policies.sql', import.meta.url),
  'utf8',
)
const schemaMigration = readFileSync(
  new URL('../supabase/migrations/20260823235106_h1_initial_schema.sql', import.meta.url),
  'utf8',
)
const administrativePage = readFileSync(
  new URL('../src/pages/CategoryAdministrationPage.tsx', import.meta.url),
  'utf8',
)
const serviceSource = readFileSync(
  new URL('../src/services/catalogService.ts', import.meta.url),
  'utf8',
)

const context = {
  profile: {
    id: 'test-user-own', local_id: 'test-local-own', rol_id: 1,
    nombre: 'Administrador de prueba', activo: true,
  },
  role: { id: 1, codigo: 'ADMINISTRADOR', activo: true },
  local: { id: 'test-local-own', activo: true },
}

const category = {
  id: 'category-main', codigo: 'Category-01', nombre: 'Categoría principal', orden: 1, activo: true,
}
const product = {
  id: 'product-main', categoria_id: 'category-main', codigo: 'Product-01',
  nombre: 'Producto principal', precio: 10, activo: true,
}
const table = {
  id: 'table-main', codigo: 'Mesa-01', nombre: 'Mesa principal', estado: 'LIBRE', activo: true,
}

function createClient({ tableStatus = 'LIBRE', mutationError = null } = {}) {
  const records = {
    categoria: [{ ...category }],
    producto: [{ ...product }],
    mesa: [{ ...table, estado: tableStatus }],
  }
  const calls = []
  const client = {
    from(resource) {
      const call = { resource, operation: null, payload: null, filters: [] }
      calls.push(call)
      const query = {
        select() {
          call.operation = 'select'
          return query
        },
        insert(payload) {
          call.operation = 'insert'
          call.payload = payload
          return query
        },
        update(payload) {
          call.operation = 'update'
          call.payload = payload
          return query
        },
        eq(column, value) {
          call.filters.push({ column, value })
          return query
        },
        order() { return query },
        async returns() {
          return { data: records[resource].map((record) => ({ ...record })), error: null }
        },
        then(onFulfilled, onRejected) {
          return Promise.resolve().then(() => {
            if (mutationError) return { error: mutationError }
            if (call.operation === 'insert') {
              records[resource].push({
                id: `${resource}-created`, ...call.payload,
                ...(resource === 'mesa' ? { estado: 'LIBRE' } : {}),
              })
            }
            if (call.operation === 'update') {
              const target = records[resource].find((item) =>
                item.id === call.filters.find((filter) => filter.column === 'id')?.value,
              )
              if (target) Object.assign(target, call.payload)
            }
            return { error: null }
          }).then(onFulfilled, onRejected)
        },
      }
      return query
    },
  }
  return { client, calls, records }
}

function grantColumns(operation, resource) {
  const pattern = new RegExp(
    `grant\\s+${operation}\\s*\\(([^)]+)\\)\\s+on\\s+table\\s+public\\.${resource}\\s+to\\s+authenticated`,
    'i',
  )
  const match = privilegeMigration.match(pattern)
  assert.ok(match, `Debe existir GRANT ${operation} por columnas para ${resource}`)
  return match[1].split(',').map((column) => column.trim())
}

function policy(name) {
  const pattern = new RegExp(`create\\s+policy\\s+${name}\\b[\\s\\S]*?;`, 'i')
  const match = policyMigration.match(pattern)
  assert.ok(match, `Debe existir la política ${name}`)
  return match[0]
}

test('T07 concede exactamente las columnas aprobadas para categorías', () => {
  assert.deepEqual(grantColumns('insert', 'categoria'), [
    'local_id', 'codigo', 'nombre', 'orden', 'activo',
  ])
  assert.deepEqual(grantColumns('update', 'categoria'), ['codigo', 'nombre', 'orden', 'activo'])
})

test('T07 concede exactamente las columnas aprobadas para productos', () => {
  assert.deepEqual(grantColumns('insert', 'producto'), [
    'local_id', 'categoria_id', 'codigo', 'nombre', 'precio', 'activo',
  ])
  assert.deepEqual(new Set(grantColumns('update', 'producto')), new Set([
    'categoria_id', 'codigo', 'nombre', 'precio', 'activo',
  ]))
})

test('T07 concede exactamente las columnas aprobadas para mesas', () => {
  assert.deepEqual(grantColumns('insert', 'mesa'), ['local_id', 'codigo', 'nombre', 'activo'])
  assert.deepEqual(grantColumns('update', 'mesa'), ['codigo', 'nombre', 'activo'])
})

test('T07 no concede id, creado_en, local_id en UPDATE ni mesa.estado', () => {
  for (const resource of ['categoria', 'producto', 'mesa']) {
    const insert = grantColumns('insert', resource)
    const update = grantColumns('update', resource)
    assert.equal(insert.includes('id'), false)
    assert.equal(insert.includes('creado_en'), false)
    assert.equal(update.includes('id'), false)
    assert.equal(update.includes('creado_en'), false)
    assert.equal(update.includes('local_id'), false)
  }
  assert.equal(grantColumns('insert', 'mesa').includes('estado'), false)
  assert.equal(grantColumns('update', 'mesa').includes('estado'), false)
  assert.match(privilegeMigration, /revoke all privileges[\s\S]*?from authenticated;/i)
  assert.match(privilegeMigration, /has_table_privilege\('authenticated', h2_table_reference, 'INSERT'\)/)
  assert.match(privilegeMigration, /has_column_privilege\(/)
})

test('las políticas INSERT y UPDATE exigen local propio y rol administrador', () => {
  for (const [resource, suffix] of [
    ['categoria', 'categories'], ['producto', 'products'], ['mesa', 'tables'],
  ]) {
    for (const operation of ['insert', 'update']) {
      const source = policy(`h2_${operation}_admin_${suffix}`)
      assert.match(source, /to authenticated/i)
      assert.match(source, /with check/i)
      assert.match(source, new RegExp(`auth_context\\.local_id = public\\.${resource}\\.local_id`))
      assert.match(source, /auth_context\.rol_codigo = 'ADMINISTRADOR'/)
    }
  }
})

test('H1 define LIBRE por defecto y T08 lo exige al insertar una mesa', () => {
  assert.match(schemaMigration, /create table public\.mesa \([\s\S]*?estado text not null default 'LIBRE'/)
  assert.match(policy('h2_insert_admin_tables'), /public\.mesa\.estado = 'LIBRE'/)
})

test('T08 permite conservar mesas activas y exige LIBRE para desactivarlas', () => {
  const source = policy('h2_update_admin_tables')
  assert.match(source, /public\.mesa\.activo = true\s+or public\.mesa\.estado = 'LIBRE'/)
  assert.match(source, /using \(/i)
  assert.match(source, /with check \(/i)
})

for (const resource of ['categoria', 'producto', 'mesa']) {
  test(`rechaza completamente payload mixto en INSERT de ${resource}`, async () => {
    const fixture = createClient()
    const before = structuredClone(fixture.records)
    const service = createCatalogService(fixture.client)
    let result

    if (resource === 'categoria') {
      result = await service.createCategory(context, {
        codigo: 'Cambio', nombre: 'Categoría alterada', orden: 1, activo: true,
        id: 'protected-id', creado_en: 'protected-date', local_id: 'foreign-local',
      })
    } else if (resource === 'producto') {
      result = await service.createProduct(context, {
        categoria_id: category.id, codigo: 'Cambio', nombre: 'Producto alterado',
        precio: 5, activo: true, id: 'protected-id', creado_en: 'protected-date',
        local_id: 'foreign-local',
      }, [category])
    } else {
      result = await service.createTable(context, {
        codigo: 'Cambio', nombre: 'Mesa alterada', activo: true,
        id: 'protected-id', creado_en: 'protected-date', local_id: 'foreign-local', estado: 'OCUPADA',
      })
    }

    assert.equal(result.ok, false)
    assert.equal(result.error.kind, 'authorization-error')
    assert.doesNotMatch(result.error.message, /SQL|protected|foreign|token/i)
    assert.deepEqual(fixture.calls, [])
    assert.deepEqual(fixture.records, before)
  })

  test(`rechaza completamente payload mixto en UPDATE de ${resource} sin cambios parciales`, async () => {
    const fixture = createClient()
    const before = structuredClone(fixture.records)
    const service = createCatalogService(fixture.client)
    let result

    if (resource === 'categoria') {
      result = await service.updateCategory(context, category.id, {
        codigo: 'Cambio', nombre: 'Categoría alterada', orden: 2, activo: false,
        id: 'protected-id', creado_en: 'protected-date', local_id: 'foreign-local',
      })
    } else if (resource === 'producto') {
      result = await service.updateProduct(context, product.id, {
        categoria_id: category.id, codigo: 'Cambio', nombre: 'Producto alterado',
        precio: 20, activo: false, id: 'protected-id', creado_en: 'protected-date',
        local_id: 'foreign-local',
      }, [category])
    } else {
      result = await service.updateTable(context, table, {
        codigo: 'Cambio', nombre: 'Mesa alterada', activo: false,
        id: 'protected-id', creado_en: 'protected-date', local_id: 'foreign-local', estado: 'OCUPADA',
      })
    }

    assert.equal(result.ok, false)
    assert.equal(result.error.kind, 'authorization-error')
    assert.deepEqual(fixture.calls, [])
    assert.deepEqual(fixture.records, before)
  })
}

test('los INSERT válidos construyen exclusivamente columnas autorizadas y local contextual', async () => {
  for (const resource of ['categoria', 'producto', 'mesa']) {
    const fixture = createClient()
    const service = createCatalogService(fixture.client)
    let result

    if (resource === 'categoria') {
      result = await service.createCategory(context, {
        codigo: 'Nueva', nombre: 'Nueva categoría', orden: 2, activo: true,
      })
    } else if (resource === 'producto') {
      result = await service.createProduct(context, {
        categoria_id: category.id, codigo: 'Nuevo', nombre: 'Nuevo producto', precio: 5, activo: true,
      }, [category])
    } else {
      result = await service.createTable(context, {
        codigo: 'Nueva', nombre: 'Nueva mesa', activo: true,
      })
    }

    assert.equal(result.ok, true)
    const insert = fixture.calls.find((call) => call.operation === 'insert')
    assert.deepEqual(new Set(Object.keys(insert.payload)), new Set(grantColumns('insert', resource)))
    assert.equal(insert.payload.local_id, context.local.id)
    if (resource === 'mesa') {
      assert.equal('estado' in insert.payload, false)
      assert.equal(fixture.records.mesa.find((item) => item.id === 'mesa-created').estado, 'LIBRE')
    }
  }
})

test('los UPDATE válidos construyen exclusivamente columnas autorizadas', async () => {
  for (const resource of ['categoria', 'producto', 'mesa']) {
    const fixture = createClient()
    const service = createCatalogService(fixture.client)
    let result

    if (resource === 'categoria') {
      result = await service.updateCategory(context, category.id, {
        codigo: 'Actualizada', nombre: 'Categoría actualizada', orden: 2, activo: true,
      })
    } else if (resource === 'producto') {
      result = await service.updateProduct(context, product.id, {
        categoria_id: category.id, codigo: 'Actualizado', nombre: 'Producto actualizado',
        precio: 20, activo: true,
      }, [category])
    } else {
      result = await service.updateTable(context, table, {
        codigo: 'Actualizada', nombre: 'Mesa actualizada', activo: true,
      })
    }

    assert.equal(result.ok, true)
    const update = fixture.calls.find((call) => call.operation === 'update')
    assert.deepEqual(new Set(Object.keys(update.payload)), new Set(grantColumns('update', resource)))
    for (const protectedColumn of ['id', 'creado_en', 'local_id']) {
      assert.equal(protectedColumn in update.payload, false)
    }
    if (resource === 'mesa') assert.equal('estado' in update.payload, false)
  }
})

for (const estado of ['OCUPADA', 'PEDIDO_LISTO', 'PENDIENTE_PAGO']) {
  test(`rechaza por completo desactivar una mesa ${estado}`, async () => {
    const fixture = createClient({ tableStatus: estado })
    const before = structuredClone(fixture.records)
    const currentTable = { ...table, estado }
    const result = await createCatalogService(fixture.client)
      .setTableActive(context, currentTable, false)

    assert.equal(result.ok, false)
    assert.equal(result.error.kind, 'table-not-free')
    assert.deepEqual(fixture.calls, [])
    assert.deepEqual(fixture.records, before)
  })
}

test('edita código y nombre de una mesa activa no libre sin alterar su estado', async () => {
  const fixture = createClient({ tableStatus: 'PEDIDO_LISTO' })
  const currentTable = { ...table, estado: 'PEDIDO_LISTO' }
  const result = await createCatalogService(fixture.client).updateTable(context, currentTable, {
    codigo: 'Mesa-renovada', nombre: 'Mesa actualizada', activo: true,
  })

  assert.equal(result.ok, true)
  assert.equal(fixture.records.mesa[0].estado, 'PEDIDO_LISTO')
  assert.equal(fixture.records.mesa[0].codigo, 'Mesa-renovada')
})

test('activar una mesa no modifica ni transmite su estado', async () => {
  const fixture = createClient({ tableStatus: 'PENDIENTE_PAGO' })
  fixture.records.mesa[0].activo = false
  const currentTable = { ...table, estado: 'PENDIENTE_PAGO', activo: false }
  const result = await createCatalogService(fixture.client).setTableActive(context, currentTable, true)

  assert.equal(result.ok, true)
  assert.deepEqual(fixture.calls.find((call) => call.operation === 'update').payload, { activo: true })
  assert.equal(fixture.records.mesa[0].estado, 'PENDIENTE_PAGO')
})

test('traduce 42501 sin cambios parciales ni detalles internos', async () => {
  const fixture = createClient({ mutationError: {
    code: '42501', message: 'private SQL constraint internal-token protected-id',
  } })
  const before = structuredClone(fixture.records)
  const result = await createCatalogService(fixture.client).updateCategory(context, category.id, {
    codigo: 'Cambio', nombre: 'Categoría alterada', orden: 2, activo: true,
  })

  assert.equal(result.ok, false)
  assert.equal(result.error.kind, 'authorization-error')
  assert.doesNotMatch(result.error.message, /SQL|constraint|token|protected/i)
  assert.deepEqual(fixture.records, before)
})

test('servicio y formularios no propagan objetos de entrada a INSERT o UPDATE', () => {
  assert.doesNotMatch(serviceSource, /\.(?:insert|update)\(\s*\{\s*\.\.\.(?:input|validated)/)
  const start = administrativePage.indexOf('<form className="mt-6 space-y-5" onSubmit={submitTable}>')
  const end = administrativePage.indexOf('</form>', start)
  const tableForm = administrativePage.slice(start, end)
  assert.doesNotMatch(tableForm, /id="table-(?:state|status|estado)"|name="estado"|<select/)
  assert.match(administrativePage, /disabled=\{tableSaving \|\| \(table\.activo && table\.estado !== 'LIBRE'\)\}/)
})
