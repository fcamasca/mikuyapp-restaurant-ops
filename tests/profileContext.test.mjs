import assert from 'node:assert/strict'
import { test } from 'node:test'
import { createProfileContextController } from '../src/services/profileContext.ts'

const ownUserId = 'test-user-own'

function createSession(id = ownUserId) {
  return { user: { id } }
}

function createProfile(overrides = {}) {
  return {
    id: ownUserId,
    local_id: 'test-local-own',
    rol_id: 1,
    nombre: 'Usuario de prueba',
    activo: true,
    rol: { id: 1, codigo: 'ADMINISTRADOR', activo: true },
    local: { id: 'test-local-own', nombre: 'Local de prueba', activo: true },
    ...overrides,
  }
}

function createClient(result = { data: createProfile(), error: null }) {
  const calls = { table: null, columns: null, filter: null, count: 0 }
  let currentResult = result

  const client = {
    from(table) {
      calls.table = table
      return {
        select(columns) {
          calls.columns = columns
          return {
            eq(column, value) {
              calls.filter = { column, value }
              return {
                async maybeSingle() {
                  calls.count += 1
                  if (typeof currentResult === 'function') {
                    return currentResult()
                  }
                  return currentResult
                },
              }
            },
          }
        },
      }
    },
  }

  return {
    client,
    calls,
    setResult(nextResult) {
      currentResult = nextResult
    },
  }
}

test('acepta un perfil propio con rol y local activos y coherentes', async () => {
  const fixture = createClient()
  const controller = createProfileContextController(fixture.client)

  await controller.load(createSession())

  assert.equal(controller.getSnapshot().status, 'valid')
  assert.equal(controller.getSnapshot().context.role.codigo, 'ADMINISTRADOR')
  assert.equal(controller.getSnapshot().context.local.id, 'test-local-own')
  assert.equal(controller.getSnapshot().context.local.nombre, 'Local de prueba')
})

test('rechaza un usuario sin perfil sin revelar datos internos', async () => {
  const fixture = createClient({ data: null, error: null })
  const controller = createProfileContextController(fixture.client)

  await controller.load(createSession())

  assert.equal(controller.getSnapshot().status, 'invalid')
  assert.equal(controller.getSnapshot().context, null)
  assert.match(controller.getSnapshot().message, /acceso no está habilitado/)
  assert.doesNotMatch(controller.getSnapshot().message, /test-user-own/)
})

test('rechaza un perfil inactivo', async () => {
  const fixture = createClient({ data: createProfile({ activo: false }), error: null })
  const controller = createProfileContextController(fixture.client)

  await controller.load(createSession())

  assert.equal(controller.getSnapshot().status, 'invalid')
  assert.equal(controller.getSnapshot().context, null)
})

test('rechaza un rol inactivo', async () => {
  const fixture = createClient({
    data: createProfile({ rol: { id: 1, codigo: 'ADMINISTRADOR', activo: false } }),
    error: null,
  })
  const controller = createProfileContextController(fixture.client)

  await controller.load(createSession())

  assert.equal(controller.getSnapshot().status, 'invalid')
})

test('rechaza un código de rol no reconocido', async () => {
  const fixture = createClient({
    data: createProfile({ rol: { id: 1, codigo: 'NO_AUTORIZADO', activo: true } }),
    error: null,
  })
  const controller = createProfileContextController(fixture.client)

  await controller.load(createSession())

  assert.equal(controller.getSnapshot().status, 'invalid')
})

test('rechaza un local inactivo', async () => {
  const fixture = createClient({
    data: createProfile({ local: { id: 'test-local-own', nombre: 'Local de prueba', activo: false } }),
    error: null,
  })
  const controller = createProfileContextController(fixture.client)

  await controller.load(createSession())

  assert.equal(controller.getSnapshot().status, 'invalid')
})

test('rechaza relaciones de rol o local incoherentes', async () => {
  const fixture = createClient({
    data: createProfile({ rol: { id: 99, codigo: 'ADMINISTRADOR', activo: true } }),
    error: null,
  })
  const controller = createProfileContextController(fixture.client)
  await controller.load(createSession())
  assert.equal(controller.getSnapshot().status, 'invalid')

  fixture.setResult({
    data: createProfile({ local: { id: 'another-local', nombre: 'Otro local', activo: true } }),
    error: null,
  })
  await controller.retry()
  assert.equal(controller.getSnapshot().status, 'invalid')
})

test('distingue un error recuperable y permite reintentar', async () => {
  const fixture = createClient({ data: null, error: { code: 'NETWORK_FAILURE' } })
  const controller = createProfileContextController(fixture.client)

  await controller.load(createSession())
  assert.equal(controller.getSnapshot().status, 'error')
  assert.match(controller.getSnapshot().message, /intenta nuevamente/)

  fixture.setResult({ data: createProfile(), error: null })
  await controller.retry()
  assert.equal(controller.getSnapshot().status, 'valid')
  assert.equal(fixture.calls.count, 2)
})

test('consulta exclusivamente el UUID de la sesión y columnas mínimas', async () => {
  const fixture = createClient()
  const controller = createProfileContextController(fixture.client)

  await controller.load(createSession())

  assert.equal(fixture.calls.table, 'perfil_usuario')
  assert.deepEqual(fixture.calls.filter, { column: 'id', value: ownUserId })
  assert.equal(
    fixture.calls.columns,
    'id,local_id,rol_id,nombre,activo,rol:rol_id(id,codigo,activo),local:local_id(id,nombre,activo)',
  )
})

test('limpia el contexto cuando se cierra la sesión', async () => {
  const fixture = createClient()
  const controller = createProfileContextController(fixture.client)
  await controller.load(createSession())

  controller.clear()

  assert.equal(controller.getSnapshot().status, 'idle')
  assert.equal(controller.getSnapshot().context, null)
})

test('descarta el contexto anterior cuando cambia la sesión', async () => {
  const fixture = createClient()
  const controller = createProfileContextController(fixture.client)
  await controller.load(createSession())

  fixture.setResult({
    data: createProfile({ id: 'test-user-next', nombre: 'Otro usuario de prueba' }),
    error: null,
  })
  const nextLoad = controller.load(createSession('test-user-next'))

  assert.equal(controller.getSnapshot().status, 'loading')
  assert.equal(controller.getSnapshot().context, null)
  await nextLoad
  assert.equal(controller.getSnapshot().context.profile.id, 'test-user-next')
})

test('descarta respuestas asíncronas obsoletas de otra sesión', async () => {
  let resolveFirst
  const firstResponse = new Promise((resolve) => {
    resolveFirst = resolve
  })
  const fixture = createClient(() => firstResponse)
  const controller = createProfileContextController(fixture.client)

  const oldLoad = controller.load(createSession())
  fixture.setResult({
    data: createProfile({ id: 'test-user-next', nombre: 'Otro usuario de prueba' }),
    error: null,
  })
  await controller.load(createSession('test-user-next'))

  resolveFirst({ data: createProfile(), error: null })
  await oldLoad

  assert.equal(controller.getSnapshot().status, 'valid')
  assert.equal(controller.getSnapshot().context.profile.id, 'test-user-next')
})

test('descarta una respuesta pendiente después de cerrar sesión', async () => {
  let resolvePending
  const pendingResponse = new Promise((resolve) => {
    resolvePending = resolve
  })
  const fixture = createClient(() => pendingResponse)
  const controller = createProfileContextController(fixture.client)

  const pendingLoad = controller.load(createSession())
  controller.clear()
  resolvePending({ data: createProfile(), error: null })
  await pendingLoad

  assert.equal(controller.getSnapshot().status, 'idle')
  assert.equal(controller.getSnapshot().context, null)
})

test('trata un resultado múltiple como contexto inválido', async () => {
  const fixture = createClient({ data: null, error: { code: 'PGRST116' } })
  const controller = createProfileContextController(fixture.client)

  await controller.load(createSession())

  assert.equal(controller.getSnapshot().status, 'invalid')
  assert.equal(controller.getSnapshot().context, null)
})
