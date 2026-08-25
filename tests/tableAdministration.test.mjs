import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import { test } from 'node:test'
import { createCatalogService } from '../src/services/catalogService.ts'

function createContext(roleCode = 'ADMINISTRADOR') {
  return {
    profile: {
      id: 'test-user-own', local_id: 'test-local-own', rol_id: 1,
      nombre: 'Administrador de prueba', activo: true,
    },
    role: { id: 1, codigo: roleCode, activo: true },
    local: { id: 'test-local-own', activo: true },
  }
}

function createTable(overrides = {}) {
  return {
    id: 'table-main', codigo: 'Mesa-01', nombre: 'Mesa principal',
    estado: 'LIBRE', activo: true, ...overrides,
  }
}

function createInput(overrides = {}) {
  return { codigo: ' Nueva-Mesa ', nombre: ' Nueva mesa ', activo: true, ...overrides }
}

function createClient({
  tables = [createTable()], mutationError = null, rejection = null,
  reloadError = null, createdStatus = 'LIBRE',
} = {}) {
  const calls = []
  const currentTables = [...tables]

  const client = {
    from(table) {
      const call = { table, operation: null, payload: null, columns: null, filters: [], orders: [] }
      calls.push(call)

      const query = {
        select(columns) {
          call.operation = 'select'
          call.columns = columns
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
        delete() {
          call.operation = 'delete'
          return query
        },
        eq(column, value) {
          call.filters.push({ column, value })
          return query
        },
        order(column, options) {
          call.orders.push({ column, options })
          return query
        },
        async returns() {
          if (reloadError) return { data: null, error: reloadError }
          return { data: currentTables.map((item) => ({ ...item })), error: null }
        },
        then(onFulfilled, onRejected) {
          return Promise.resolve().then(() => {
            if (rejection) throw rejection
            if (mutationError) return { error: mutationError }

            const targetId = call.filters.find((filter) => filter.column === 'id')?.value
            if (call.operation === 'insert') {
              currentTables.push({
                id: 'table-created', codigo: call.payload.codigo, nombre: call.payload.nombre,
                estado: createdStatus, activo: call.payload.activo,
              })
            }
            if (call.operation === 'update') {
              const index = currentTables.findIndex((item) => item.id === targetId)
              if (index >= 0) currentTables[index] = { ...currentTables[index], ...call.payload }
            }
            if (call.operation === 'delete') {
              const index = currentTables.findIndex((item) => item.id === targetId)
              if (index >= 0) currentTables.splice(index, 1)
            }
            return { error: null }
          }).then(onFulfilled, onRejected)
        },
      }

      return query
    },
  }

  return { client, calls }
}

function findMutation(calls) {
  return calls.find((call) => call.operation !== 'select')
}

function assertTablesReloaded(calls) {
  const reads = calls.filter((call) => call.operation === 'select')
  assert.equal(reads.length, 1)
  assert.equal(reads[0].table, 'mesa')
  assert.equal(reads[0].columns, 'id,codigo,nombre,estado,activo')
  assert.deepEqual(reads[0].filters, [{ column: 'local_id', value: 'test-local-own' }])
}

test('consulta mesas activas e inactivas con las columnas administrativas exactas', async () => {
  const fixture = createClient({
    tables: [createTable(), createTable({ id: 'table-inactive', activo: false })],
  })
  const result = await createCatalogService(fixture.client).getAdministrativeTables(createContext())

  assert.equal(result.ok, true)
  assert.deepEqual(result.data.map((item) => item.activo), [true, false])
  assertTablesReloaded(fixture.calls)
  assert.deepEqual(fixture.calls[0].orders.map((item) => item.column), ['codigo', 'nombre'])
})

test('rechaza la consulta administrativa de mesas desde otro rol', async () => {
  const fixture = createClient()
  const result = await createCatalogService(fixture.client)
    .getAdministrativeTables(createContext('MOZO'))

  assert.equal(result.ok, false)
  assert.equal(result.error.kind, 'authorization-error')
  assert.deepEqual(fixture.calls, [])
})

test('crea una mesa con columnas exactas sin enviar estado y comprueba LIBRE', async () => {
  const fixture = createClient()
  const result = await createCatalogService(fixture.client).createTable(createContext(), createInput())

  assert.equal(result.ok, true)
  assert.deepEqual(findMutation(fixture.calls).payload, {
    local_id: 'test-local-own', codigo: 'Nueva-Mesa', nombre: 'Nueva mesa', activo: true,
  })
  assert.equal(result.data.tables.find((item) => item.id === 'table-created').estado, 'LIBRE')
  assert.match(result.data.message, /estado libre/)
  assertTablesReloaded(fixture.calls)
})

test('rechaza una creación cuyo estado resultante no es LIBRE', async () => {
  const fixture = createClient({ createdStatus: 'OCUPADA' })
  const result = await createCatalogService(fixture.client).createTable(createContext(), createInput())

  assert.equal(result.ok, false)
  assert.equal(result.error.kind, 'table-not-free')
  assert.match(result.error.message, /confirmar/)
  assertTablesReloaded(fixture.calls)
})

test('edita una mesa con las columnas exactas y conserva su estado operativo', async () => {
  const table = createTable({ estado: 'OCUPADA' })
  const fixture = createClient({ tables: [table] })
  const result = await createCatalogService(fixture.client)
    .updateTable(createContext(), table, createInput())

  assert.equal(result.ok, true)
  assert.deepEqual(findMutation(fixture.calls).payload, {
    codigo: 'Nueva-Mesa', nombre: 'Nueva mesa', activo: true,
  })
  assert.deepEqual(findMutation(fixture.calls).filters, [
    { column: 'id', value: 'table-main' },
    { column: 'local_id', value: 'test-local-own' },
  ])
  assert.equal(result.data.tables[0].estado, 'OCUPADA')
  assertTablesReloaded(fixture.calls)
})

test('activa o reactiva una mesa sin alterar su estado operativo', async () => {
  for (const estado of ['LIBRE', 'OCUPADA']) {
    const table = createTable({ estado, activo: false })
    const fixture = createClient({ tables: [table] })
    const result = await createCatalogService(fixture.client)
      .setTableActive(createContext(), table, true)

    assert.equal(result.ok, true)
    assert.deepEqual(findMutation(fixture.calls).payload, { activo: true })
    assert.equal(result.data.tables[0].estado, estado)
    assert.equal(result.data.tables[0].activo, true)
    assertTablesReloaded(fixture.calls)
  }
})

test('desactiva una mesa LIBRE enviando exclusivamente activo', async () => {
  const fixture = createClient()
  const result = await createCatalogService(fixture.client)
    .setTableActive(createContext(), createTable(), false)

  assert.equal(result.ok, true)
  assert.deepEqual(findMutation(fixture.calls).payload, { activo: false })
  assert.equal(result.data.tables[0].activo, false)
  assert.equal(result.data.tables[0].estado, 'LIBRE')
  assertTablesReloaded(fixture.calls)
})

for (const estado of ['OCUPADA', 'PEDIDO_LISTO', 'PENDIENTE_PAGO']) {
  test(`rechaza desactivar una mesa ${estado} sin llamar a Supabase`, async () => {
    const table = createTable({ estado })
    const fixture = createClient({ tables: [table] })
    const result = await createCatalogService(fixture.client)
      .setTableActive(createContext(), table, false)

    assert.equal(result.ok, false)
    assert.equal(result.error.kind, 'table-not-free')
    assert.match(result.error.message, /mesas libres/)
    assert.deepEqual(fixture.calls, [])
  })
}

test('rechaza editar una mesa no LIBRE para dejarla inactiva', async () => {
  const table = createTable({ estado: 'OCUPADA' })
  const fixture = createClient({ tables: [table] })
  const result = await createCatalogService(fixture.client)
    .updateTable(createContext(), table, createInput({ activo: false }))

  assert.equal(result.ok, false)
  assert.equal(result.error.kind, 'table-not-free')
  assert.deepEqual(fixture.calls, [])
})

test('rechaza estado, identificadores y creado_en proporcionados en una inserción', async () => {
  const fixture = createClient()
  const result = await createCatalogService(fixture.client).createTable(createContext(), createInput({
    id: 'injected-id', local_id: 'injected-local', estado: 'OCUPADA', creado_en: 'injected-date',
  }))

  assert.equal(result.ok, false)
  assert.equal(result.error.kind, 'authorization-error')
  assert.deepEqual(fixture.calls, [])
})

test('rechaza estado, identificadores y creado_en proporcionados en una actualización', async () => {
  const fixture = createClient()
  const result = await createCatalogService(fixture.client)
    .updateTable(createContext(), createTable(), createInput({
      id: 'injected-id', local_id: 'injected-local', estado: 'OCUPADA', creado_en: 'injected-date',
    }))

  assert.equal(result.ok, false)
  assert.equal(result.error.kind, 'authorization-error')
  assert.deepEqual(fixture.calls, [])
})

test('elimina una mesa confirmada, sin modificar estado ni pedidos, y recarga', async () => {
  const fixture = createClient()
  const result = await createCatalogService(fixture.client)
    .deleteTable(createContext(), createTable(), true)

  assert.equal(result.ok, true)
  assert.equal(findMutation(fixture.calls).table, 'mesa')
  assert.equal(findMutation(fixture.calls).operation, 'delete')
  assert.deepEqual(findMutation(fixture.calls).filters, [
    { column: 'id', value: 'table-main' },
    { column: 'local_id', value: 'test-local-own' },
  ])
  assert.deepEqual(result.data.tables, [])
  assertTablesReloaded(fixture.calls)
})

test('cancelar la eliminación no ejecuta consultas en Supabase', async () => {
  const fixture = createClient()
  const result = await createCatalogService(fixture.client)
    .deleteTable(createContext(), createTable(), false)

  assert.equal(result.ok, true)
  assert.equal(result.data.status, 'cancelled')
  assert.equal(result.data.tables, null)
  assert.deepEqual(fixture.calls, [])
})

test('una mesa LIBRE con pedidos relacionados recomienda desactivación', async () => {
  const fixture = createClient({ mutationError: {
    code: '23503', message: 'private constraint SQL internal-token',
  } })
  const result = await createCatalogService(fixture.client)
    .deleteTable(createContext(), createTable(), true)

  assert.equal(result.ok, false)
  assert.equal(result.error.kind, 'table-has-orders')
  assert.match(result.error.message, /pedidos relacionados.*desactivarla si está libre/)
  assert.doesNotMatch(result.error.message, /constraint|SQL|token/)
})

test('una mesa no LIBRE con pedidos relacionados no recomienda desactivación', async () => {
  const table = createTable({ estado: 'OCUPADA' })
  const fixture = createClient({ tables: [table], mutationError: { code: '23503' } })
  const result = await createCatalogService(fixture.client).deleteTable(createContext(), table, true)

  assert.equal(result.ok, false)
  assert.equal(result.error.kind, 'table-has-orders')
  assert.doesNotMatch(result.error.message, /desactiv/)
})

test('la confirmación de mesa identifica nombre y código y bloquea duplicados', () => {
  const source = readFileSync(
    new URL('../src/pages/CategoryAdministrationPage.tsx', import.meta.url),
    'utf8',
  )
  const start = source.indexOf('function deleteTable(')
  const end = source.indexOf('\n  return (', start)
  const deletion = source.slice(start, end)

  assert.match(deletion, /if \(!service \|\| saving \|\| mutationPending\.current\)/)
  assert.match(deletion, /window\.confirm\(/)
  assert.match(deletion, /mesa «\$\{table\.nombre\}» \(\$\{table\.codigo\}\)/)
  assert.match(deletion, /service\.deleteTable\(context, table, confirmed\)/)
})

test('elimina únicamente la mesa seleccionada y conserva las demás', async () => {
  const fixture = createClient({
    tables: [
      createTable(),
      createTable({ id: 'table-other', codigo: 'Mesa-02', nombre: 'Otra mesa' }),
    ],
  })
  const result = await createCatalogService(fixture.client)
    .deleteTable(createContext(), createTable(), true)

  assert.equal(result.ok, true)
  assert.deepEqual(result.data.tables.map((table) => table.id), ['table-other'])
  assert.deepEqual(fixture.calls.filter((call) => call.operation === 'delete').map((call) => call.table), [
    'mesa',
  ])
  assert.equal(fixture.calls.some((call) => call.operation === 'update'), false)
})

test('conserva la mesa tras rechazo por pedidos sin eliminar dependencias ni desactivarla', async () => {
  const fixture = createClient({ mutationError: { code: '23503', message: 'private SQL constraint' } })
  const service = createCatalogService(fixture.client)
  const rejected = await service.deleteTable(createContext(), createTable(), true)
  const tables = await service.getAdministrativeTables(createContext())

  assert.equal(rejected.ok, false)
  assert.equal(tables.ok, true)
  assert.deepEqual(tables.data.map((table) => table.id), ['table-main'])
  assert.equal(tables.data[0].activo, true)
  assert.deepEqual(fixture.calls.filter((call) => call.operation === 'delete').map((call) => call.table), [
    'mesa',
  ])
  assert.equal(fixture.calls.some((call) => call.operation === 'update'), false)
  assert.equal(fixture.calls.some((call) => call.table === 'pedido'), false)
})

test('traduce denegaciones de eliminación de mesa sin revelar detalles internos', async () => {
  for (const code of ['42501', 'PGRST301']) {
    const fixture = createClient({ mutationError: { code, message: 'private SQL internal-token' } })
    const result = await createCatalogService(fixture.client)
      .deleteTable(createContext(), createTable(), true)

    assert.equal(result.ok, false)
    assert.equal(result.error.kind, 'authorization-error')
    assert.match(result.error.message, /operación no está permitida/)
    assert.doesNotMatch(result.error.message, /SQL|token/)
    assert.equal(fixture.calls.length, 1)
  }
})

test('traduce errores inesperados al eliminar una mesa sin desactivarla', async () => {
  const fixture = createClient({ mutationError: {
    code: 'XX000', message: 'private SQL constraint internal-token',
  } })
  const result = await createCatalogService(fixture.client)
    .deleteTable(createContext(), createTable(), true)

  assert.equal(result.ok, false)
  assert.equal(result.error.recoverable, true)
  assert.doesNotMatch(result.error.message, /SQL|constraint|token/)
  assert.equal(fixture.calls.length, 1)
  assert.equal(fixture.calls[0].operation, 'delete')
})

test('traduce error de conexión al eliminar una mesa sin mostrar detalles sensibles', async () => {
  const fixture = createClient({ rejection: new Error('private SQL internal-token') })
  const result = await createCatalogService(fixture.client)
    .deleteTable(createContext(), createTable(), true)

  assert.equal(result.ok, false)
  assert.equal(result.error.kind, 'connection-error')
  assert.equal(result.error.recoverable, true)
  assert.doesNotMatch(result.error.message, /SQL|token/)
  assert.equal(fixture.calls.length, 1)
})

test('traduce el código duplicado sin revelar detalles internos', async () => {
  const fixture = createClient({ mutationError: {
    code: '23505', message: 'private SQL constraint token',
  } })
  const result = await createCatalogService(fixture.client).createTable(createContext(), createInput())

  assert.equal(result.ok, false)
  assert.equal(result.error.kind, 'duplicate-table-code')
  assert.match(result.error.message, /mesa con ese código/)
  assert.doesNotMatch(result.error.message, /SQL|constraint|token/)
})

test('rechaza código vacío sin ejecutar consultas', async () => {
  for (const codigo of ['', '   ']) {
    const fixture = createClient()
    const result = await createCatalogService(fixture.client)
      .createTable(createContext(), createInput({ codigo }))

    assert.equal(result.ok, false)
    assert.equal(result.error.kind, 'validation-error')
    assert.match(result.error.message, /código/)
    assert.deepEqual(fixture.calls, [])
  }
})

test('rechaza nombre vacío sin ejecutar consultas', async () => {
  for (const nombre of ['', '   ']) {
    const fixture = createClient()
    const result = await createCatalogService(fixture.client)
      .updateTable(createContext(), createTable(), createInput({ nombre }))

    assert.equal(result.ok, false)
    assert.equal(result.error.kind, 'validation-error')
    assert.match(result.error.message, /nombre/)
    assert.deepEqual(fixture.calls, [])
  }
})

test('conserva mayúsculas, minúsculas y espacios interiores', async () => {
  const fixture = createClient()
  const result = await createCatalogService(fixture.client).createTable(createContext(), createInput({
    codigo: ' Mi Mesa-01 ', nombre: ' Mesa  Principal ',
  }))

  assert.equal(result.ok, true)
  assert.equal(findMutation(fixture.calls).payload.codigo, 'Mi Mesa-01')
  assert.equal(findMutation(fixture.calls).payload.nombre, 'Mesa  Principal')
})

test('obtiene local_id exclusivamente del contexto validado en alta y filtros', async () => {
  const context = createContext()
  const fixture = createClient()
  const result = await createCatalogService(fixture.client)
    .createTable(context, createInput())

  assert.equal(result.ok, true)
  assert.equal(findMutation(fixture.calls).payload.local_id, context.local.id)
  assertTablesReloaded(fixture.calls)
})

test('traduce falta de autorización sin mostrar detalles internos', async () => {
  const fixture = createClient({ mutationError: {
    code: '42501', message: 'private SQL policy internal-token',
  } })
  const result = await createCatalogService(fixture.client).createTable(createContext(), createInput())

  assert.equal(result.ok, false)
  assert.equal(result.error.kind, 'authorization-error')
  assert.match(result.error.message, /autorización|permitida/)
  assert.doesNotMatch(result.error.message, /SQL|policy|token/)
})

test('traduce rechazo RLS al desactivar como mesa no libre', async () => {
  const fixture = createClient({ mutationError: { code: '42501', message: 'private SQL policy' } })
  const result = await createCatalogService(fixture.client)
    .setTableActive(createContext(), createTable(), false)

  assert.equal(result.ok, false)
  assert.equal(result.error.kind, 'table-not-free')
  assert.doesNotMatch(result.error.message, /SQL|policy/)
})

test('traduce errores inesperados a un mensaje recuperable y seguro', async () => {
  const fixture = createClient({ mutationError: {
    code: 'XX000', message: 'private SQL internal-token',
  } })
  const result = await createCatalogService(fixture.client).createTable(createContext(), createInput())

  assert.equal(result.ok, false)
  assert.equal(result.error.kind, 'connection-error')
  assert.equal(result.error.recoverable, true)
  assert.doesNotMatch(result.error.message, /SQL|token/)
})

test('traduce excepciones de conexión sin revelar información interna', async () => {
  const fixture = createClient({ rejection: new Error('private SQL internal-token') })
  const result = await createCatalogService(fixture.client).createTable(createContext(), createInput())

  assert.equal(result.ok, false)
  assert.equal(result.error.kind, 'connection-error')
  assert.doesNotMatch(result.error.message, /SQL|token/)
})

test('informa como recuperable un error durante la recarga de mesas', async () => {
  const fixture = createClient({ reloadError: { message: 'private SQL internal-token' } })
  const result = await createCatalogService(fixture.client).createTable(createContext(), createInput())

  assert.equal(result.ok, false)
  assert.equal(result.error.kind, 'connection-error')
  assert.doesNotMatch(result.error.message, /SQL|token/)
})

test('rechaza mutaciones administrativas de mesas desde roles no autorizados', async () => {
  for (const role of ['MOZO', 'COCINA', 'CAJA']) {
    const fixture = createClient()
    const result = await createCatalogService(fixture.client)
      .createTable(createContext(role), createInput())

    assert.equal(result.ok, false)
    assert.equal(result.error.kind, 'authorization-error')
    assert.deepEqual(fixture.calls, [])
  }
})

test('el formulario administrativo no incorpora controles para cambiar estado', () => {
  const source = readFileSync(new URL('../src/pages/CategoryAdministrationPage.tsx', import.meta.url), 'utf8')
  const start = source.indexOf('<form className="mt-6 space-y-5" onSubmit={submitTable}>')
  assert.notEqual(start, -1)
  const end = source.indexOf('</form>', start)
  const form = source.slice(start, end)

  assert.match(form, /id="table-code"/)
  assert.match(form, /id="table-name"/)
  assert.match(form, /type="checkbox"/)
  assert.doesNotMatch(form, /id="table-(?:state|status|estado)"|name="estado"|<select/)
  assert.match(source, /disabled=\{saving \|\| \(table\.activo && table\.estado !== 'LIBRE'\)\}/)
})

test('conserva el formulario de mesas ante error y bloquea envíos duplicados', () => {
  const source = readFileSync(
    new URL('../src/pages/CategoryAdministrationPage.tsx', import.meta.url),
    'utf8',
  )
  const start = source.indexOf('async function runTableMutation(')
  const end = source.indexOf('function submitTable(', start)
  const mutation = source.slice(start, end)

  assert.match(mutation, /if \(mutationPending\.current\) \{\s*return\s*\}/)
  assert.match(mutation, /mutationPending\.current = true/)
  assert.match(mutation, /if \(!result\.ok\) \{\s*setTableError\(result\.error\.message\)\s*return\s*\}/)
  assert.ok(mutation.indexOf('if (!result.ok)') < mutation.indexOf('resetTableForm()'))
  assert.match(mutation, /finally \{\s*mutationPending\.current = false/)
})
