import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import { test } from 'node:test'
import { createCatalogService } from '../src/services/catalogService.ts'

function createContext(roleCode = 'ADMINISTRADOR') {
  return {
    profile: {
      id: 'test-user-own',
      local_id: 'test-local-own',
      rol_id: 1,
      nombre: 'Administrador de prueba',
      activo: true,
    },
    role: { id: 1, codigo: roleCode, activo: true },
    local: { id: 'test-local-own', activo: true },
  }
}

function createCategory(overrides = {}) {
  return {
    id: 'category-main',
    codigo: 'Original',
    nombre: 'Categoría original',
    orden: 1,
    activo: true,
    ...overrides,
  }
}

function createProduct(overrides = {}) {
  return {
    id: 'product-main',
    categoria_id: 'category-main',
    codigo: 'Product-01',
    nombre: 'Producto de prueba',
    precio: 10,
    activo: true,
    ...overrides,
  }
}

function createInput(overrides = {}) {
  return {
    codigo: ' Nueva-Cat ',
    nombre: ' Nueva categoría ',
    orden: 2,
    activo: true,
    ...overrides,
  }
}

function createClient({
  categories = [createCategory()],
  products = [createProduct()],
  mutationError = null,
  rejection = null,
  reloadError = null,
} = {}) {
  const calls = []
  const currentCategories = [...categories]

  const client = {
    from(table) {
      const call = {
        table,
        operation: null,
        payload: null,
        columns: null,
        filters: [],
        orders: [],
      }
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
          if (reloadError) {
            return { data: null, error: reloadError }
          }

          return {
            data: table === 'categoria'
              ? currentCategories.map((category) => ({ ...category }))
              : products.map((product) => ({ ...product })),
            error: null,
          }
        },

        then(onFulfilled, onRejected) {
          return Promise.resolve()
            .then(() => {
              if (rejection) {
                throw rejection
              }

              if (mutationError) {
                return { error: mutationError }
              }

              const targetId = call.filters.find((filter) => filter.column === 'id')?.value

              if (call.operation === 'insert') {
                currentCategories.push({
                  id: 'category-created',
                  codigo: call.payload.codigo,
                  nombre: call.payload.nombre,
                  orden: call.payload.orden,
                  activo: call.payload.activo,
                })
              }

              if (call.operation === 'update') {
                const index = currentCategories.findIndex((category) => category.id === targetId)
                if (index >= 0) {
                  currentCategories[index] = {
                    ...currentCategories[index],
                    ...call.payload,
                  }
                }
              }

              if (call.operation === 'delete') {
                const index = currentCategories.findIndex((category) => category.id === targetId)
                if (index >= 0) {
                  currentCategories.splice(index, 1)
                }
              }

              return { error: null }
            })
            .then(onFulfilled, onRejected)
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

function assertCatalogReloaded(calls) {
  const reads = calls.filter((call) => call.operation === 'select')
  assert.deepEqual(reads.map((call) => call.table), ['categoria', 'producto'])
  assert.equal(reads.every((call) => call.filters.some((filter) =>
    filter.column === 'local_id' && filter.value === 'test-local-own',
  )), true)
}

test('crea una categoría válida, conserva mayúsculas/minúsculas y recorta solo extremos', async () => {
  const fixture = createClient()

  const result = await createCatalogService(fixture.client)
    .createCategory(createContext(), createInput())

  assert.equal(result.ok, true)
  assert.equal(result.data.status, 'completed')
  assert.match(result.data.message, /creó correctamente/)
  assert.deepEqual(findMutation(fixture.calls).payload, {
    local_id: 'test-local-own',
    codigo: 'Nueva-Cat',
    nombre: 'Nueva categoría',
    orden: 2,
    activo: true,
  })
  assert.equal(result.data.catalog.categories.length, 2)
  assertCatalogReloaded(fixture.calls)
})

test('edita una categoría válida sin enviar identificadores ni columnas protegidas', async () => {
  const fixture = createClient()

  const result = await createCatalogService(fixture.client)
    .updateCategory(createContext(), 'category-main', createInput({ activo: false }))

  assert.equal(result.ok, true)
  const mutation = findMutation(fixture.calls)
  assert.equal(mutation.operation, 'update')
  assert.deepEqual(mutation.payload, {
    codigo: 'Nueva-Cat',
    nombre: 'Nueva categoría',
    orden: 2,
    activo: false,
  })
  assert.deepEqual(mutation.filters, [
    { column: 'id', value: 'category-main' },
    { column: 'local_id', value: 'test-local-own' },
  ])
  assert.equal(result.data.catalog.categories[0].activo, false)
  assertCatalogReloaded(fixture.calls)
})

test('activa una categoría enviando únicamente la columna activo', async () => {
  const fixture = createClient({ categories: [createCategory({ activo: false })] })

  const result = await createCatalogService(fixture.client)
    .setCategoryActive(createContext(), 'category-main', true)

  assert.equal(result.ok, true)
  assert.deepEqual(findMutation(fixture.calls).payload, { activo: true })
  assert.equal(result.data.catalog.categories[0].activo, true)
  assert.match(result.data.message, /activó correctamente/)
  assertCatalogReloaded(fixture.calls)
})

test('desactiva una categoría enviando únicamente la columna activo', async () => {
  const fixture = createClient()

  const result = await createCatalogService(fixture.client)
    .setCategoryActive(createContext(), 'category-main', false)

  assert.equal(result.ok, true)
  assert.deepEqual(findMutation(fixture.calls).payload, { activo: false })
  assert.equal(result.data.catalog.categories[0].activo, false)
  assert.match(result.data.message, /desactivó correctamente/)
  assertCatalogReloaded(fixture.calls)
})

test('elimina físicamente una categoría únicamente tras confirmación explícita', async () => {
  const fixture = createClient({ products: [] })

  const result = await createCatalogService(fixture.client)
    .deleteCategory(createContext(), 'category-main', true)

  assert.equal(result.ok, true)
  assert.equal(findMutation(fixture.calls).operation, 'delete')
  assert.deepEqual(findMutation(fixture.calls).filters, [
    { column: 'id', value: 'category-main' },
    { column: 'local_id', value: 'test-local-own' },
  ])
  assert.deepEqual(result.data.catalog.categories, [])
  assert.match(result.data.message, /eliminó correctamente/)
  assertCatalogReloaded(fixture.calls)
})

test('cancelar una eliminación no llama a Supabase ni consulta el catálogo', async () => {
  const fixture = createClient()

  const result = await createCatalogService(fixture.client)
    .deleteCategory(createContext(), 'category-main', false)

  assert.equal(result.ok, true)
  assert.equal(result.data.status, 'cancelled')
  assert.equal(result.data.catalog, null)
  assert.deepEqual(fixture.calls, [])
})

test('traduce la eliminación rechazada por productos relacionados sin revelar restricciones', async () => {
  const fixture = createClient({
    mutationError: {
      code: '23503',
      message: 'fk_producto_categoria_local SQL internal details test-user-own',
    },
  })

  const result = await createCatalogService(fixture.client)
    .deleteCategory(createContext(), 'category-main', true)

  assert.equal(result.ok, false)
  assert.equal(result.error.kind, 'category-has-products')
  assert.match(result.error.message, /productos relacionados/)
  assert.match(result.error.message, /desactivarla/)
  assert.doesNotMatch(result.error.message, /fk_|SQL|test-user-own/i)
  assert.equal(fixture.calls.length, 1)
})

test('la confirmación de categoría identifica nombre y código y bloquea duplicados', () => {
  const source = readFileSync(
    new URL('../src/pages/CategoryAdministrationPage.tsx', import.meta.url),
    'utf8',
  )
  const start = source.indexOf('function deleteCategory(')
  const end = source.indexOf('async function runProductMutation(', start)
  const deletion = source.slice(start, end)

  assert.match(deletion, /if \(!service \|\| saving \|\| mutationPending\.current\)/)
  assert.match(deletion, /window\.confirm\(/)
  assert.match(deletion, /categoría «\$\{category\.nombre\}» \(\$\{category\.codigo\}\)/)
  assert.match(deletion, /service\.deleteCategory\(context, category\.id, confirmed\)/)
})

test('elimina únicamente la categoría seleccionada y conserva el resto del catálogo', async () => {
  const fixture = createClient({
    categories: [
      createCategory(),
      createCategory({ id: 'category-other', codigo: 'Other', nombre: 'Otra categoría' }),
    ],
    products: [createProduct({ categoria_id: 'category-other' })],
  })
  const result = await createCatalogService(fixture.client)
    .deleteCategory(createContext(), 'category-main', true)

  assert.equal(result.ok, true)
  assert.deepEqual(result.data.catalog.categories.map((category) => category.id), ['category-other'])
  assert.deepEqual(result.data.catalog.products.map((product) => product.id), ['product-main'])
  assert.deepEqual(fixture.calls.filter((call) => call.operation === 'delete').map((call) => call.table), [
    'categoria',
  ])
  assert.equal(fixture.calls.some((call) => call.operation === 'update'), false)
})

test('conserva categoría y productos tras rechazo de dependencia sin eliminar ni desactivar otros', async () => {
  const fixture = createClient({ mutationError: { code: '23503', message: 'private SQL constraint' } })
  const service = createCatalogService(fixture.client)
  const rejected = await service.deleteCategory(createContext(), 'category-main', true)
  const catalog = await service.getAdministrativeCatalog(createContext())

  assert.equal(rejected.ok, false)
  assert.equal(catalog.ok, true)
  assert.deepEqual(catalog.data.categories.map((category) => category.id), ['category-main'])
  assert.equal(catalog.data.categories[0].activo, true)
  assert.deepEqual(catalog.data.products.map((product) => product.id), ['product-main'])
  assert.deepEqual(fixture.calls.filter((call) => call.operation === 'delete').map((call) => call.table), [
    'categoria',
  ])
  assert.equal(fixture.calls.some((call) => call.operation === 'update'), false)
})

test('traduce denegaciones de eliminación de categoría sin revelar detalles internos', async () => {
  for (const code of ['42501', 'PGRST301']) {
    const fixture = createClient({ mutationError: { code, message: 'private SQL internal-token' } })
    const result = await createCatalogService(fixture.client)
      .deleteCategory(createContext(), 'category-main', true)

    assert.equal(result.ok, false)
    assert.equal(result.error.kind, 'authorization-error')
    assert.match(result.error.message, /operación no está permitida/)
    assert.doesNotMatch(result.error.message, /SQL|token/)
    assert.equal(fixture.calls.length, 1)
  }
})

test('traduce errores inesperados al eliminar una categoría sin desactivarla', async () => {
  const fixture = createClient({ mutationError: {
    code: 'XX000', message: 'private SQL constraint internal-token',
  } })
  const result = await createCatalogService(fixture.client)
    .deleteCategory(createContext(), 'category-main', true)

  assert.equal(result.ok, false)
  assert.equal(result.error.recoverable, true)
  assert.doesNotMatch(result.error.message, /SQL|constraint|token/)
  assert.equal(fixture.calls.length, 1)
  assert.equal(fixture.calls[0].operation, 'delete')
})

test('traduce un código de categoría duplicado sin revelar restricciones internas', async () => {
  const fixture = createClient({
    mutationError: {
      code: '23505',
      message: 'uq_categoria_local_id_codigo SQL private-token',
    },
  })

  const result = await createCatalogService(fixture.client)
    .createCategory(createContext(), createInput())

  assert.equal(result.ok, false)
  assert.equal(result.error.kind, 'duplicate-category-code')
  assert.match(result.error.message, /ya existe una categoría con ese código/i)
  assert.doesNotMatch(result.error.message, /uq_|SQL|private-token/i)
  assert.equal(fixture.calls.length, 1)
})

test('rechaza códigos vacíos o compuestos únicamente por espacios', async () => {
  for (const codigo of ['', '   ']) {
    const fixture = createClient()
    const result = await createCatalogService(fixture.client)
      .createCategory(createContext(), createInput({ codigo }))

    assert.equal(result.ok, false)
    assert.equal(result.error.kind, 'validation-error')
    assert.match(result.error.message, /código/)
    assert.deepEqual(fixture.calls, [])
  }
})

test('rechaza nombres vacíos o compuestos únicamente por espacios', async () => {
  for (const nombre of ['', '   ']) {
    const fixture = createClient()
    const result = await createCatalogService(fixture.client)
      .updateCategory(createContext(), 'category-main', createInput({ nombre }))

    assert.equal(result.ok, false)
    assert.equal(result.error.kind, 'validation-error')
    assert.match(result.error.message, /nombre/)
    assert.deepEqual(fixture.calls, [])
  }
})

test('rechaza orden negativo, decimal o no numérico sin invocar Supabase', async () => {
  for (const orden of [
    -1, 1.5, '', '   ', 'texto', null, undefined,
    Number.NaN, Number.POSITIVE_INFINITY, Number.NEGATIVE_INFINITY,
  ]) {
    const fixture = createClient()
    const result = await createCatalogService(fixture.client)
      .createCategory(createContext(), createInput({ orden }))

    assert.equal(result.ok, false)
    assert.equal(result.error.kind, 'validation-error')
    assert.match(result.error.message, /entero mayor o igual que cero/)
    assert.deepEqual(fixture.calls, [])
  }
})

test('rechaza orden vacío antes de convertirlo accidentalmente en cero', () => {
  const source = readFileSync(
    new URL('../src/pages/CategoryAdministrationPage.tsx', import.meta.url),
    'utf8',
  )
  const start = source.indexOf('function submitCategory(')
  const end = source.indexOf('function toggleCategory(', start)
  const submit = source.slice(start, end)

  assert.match(submit, /if \(!form\.orden\.trim\(\)\)/)
  assert.match(submit, /setError\('Ingresa el orden de la categoría\.'\)/)
  assert.ok(submit.indexOf('!form.orden.trim()') < submit.indexOf('Number(form.orden)'))
})

test('conserva el formulario de categorías ante error y bloquea envíos duplicados', () => {
  const source = readFileSync(
    new URL('../src/pages/CategoryAdministrationPage.tsx', import.meta.url),
    'utf8',
  )
  const start = source.indexOf('async function runCategoryMutation(')
  const end = source.indexOf('function submitCategory(', start)
  const mutation = source.slice(start, end)

  assert.match(mutation, /if \(mutationPending\.current\) \{\s*return\s*\}/)
  assert.match(mutation, /mutationPending\.current = true/)
  assert.match(mutation, /if \(!result\.ok\) \{\s*setError\(result\.error\.message\)\s*return\s*\}/)
  assert.ok(mutation.indexOf('if (!result.ok)') < mutation.indexOf('resetForm()'))
  assert.match(mutation, /finally \{\s*mutationPending\.current = false/)
})

test('acepta orden cero como valor entero válido', async () => {
  const fixture = createClient()

  const result = await createCatalogService(fixture.client)
    .createCategory(createContext(), createInput({ orden: 0 }))

  assert.equal(result.ok, true)
  assert.equal(findMutation(fixture.calls).payload.orden, 0)
})

test('rechaza completamente propiedades protegidas en una inserción manipulada', async () => {
  const fixture = createClient()
  const unsafeInput = {
    ...createInput(),
    local_id: 'test-local-foreign',
    id: 'test-category-forged',
    creado_en: 'test-forged-date',
  }

  const result = await createCatalogService(fixture.client)
    .createCategory(createContext(), unsafeInput)

  assert.equal(result.ok, false)
  assert.equal(result.error.kind, 'authorization-error')
  assert.deepEqual(fixture.calls, [])
})

test('rechaza completamente columnas protegidas y local_id en una edición manipulada', async () => {
  const fixture = createClient()
  const unsafeInput = {
    ...createInput(),
    local_id: 'test-local-foreign',
    id: 'test-category-forged',
    creado_en: 'test-forged-date',
  }

  const result = await createCatalogService(fixture.client)
    .updateCategory(createContext(), 'category-main', unsafeInput)

  assert.equal(result.ok, false)
  assert.equal(result.error.kind, 'authorization-error')
  assert.deepEqual(fixture.calls, [])
})

test('recarga categorías, productos y agrupaciones tras una mutación exitosa', async () => {
  const fixture = createClient()

  const result = await createCatalogService(fixture.client)
    .updateCategory(createContext(), 'category-main', createInput({ nombre: 'Categoría renovada' }))

  assert.equal(result.ok, true)
  assert.equal(result.data.catalog.categories.length, 1)
  assert.equal(result.data.catalog.products.length, 1)
  assert.equal(result.data.catalog.groups.length, 1)
  assert.equal(result.data.catalog.groups[0].category.nombre, 'Categoría renovada')
  assert.equal(result.data.catalog.groups[0].products[0].id, 'product-main')
  assertCatalogReloaded(fixture.calls)
})

test('traduce una denegación PostgreSQL a un mensaje seguro de autorización', async () => {
  const fixture = createClient({
    mutationError: {
      code: '42501',
      message: 'permission denied SQL access_token=test-secret',
    },
  })

  const result = await createCatalogService(fixture.client)
    .setCategoryActive(createContext(), 'category-main', false)

  assert.equal(result.ok, false)
  assert.equal(result.error.kind, 'authorization-error')
  assert.match(result.error.message, /operación no está permitida/)
  assert.doesNotMatch(result.error.message, /SQL|access_token|test-secret/i)
})

test('rechaza mutaciones de roles no administradores antes de consultar Supabase', async () => {
  for (const roleCode of ['MOZO', 'COCINA', 'CAJA']) {
    const fixture = createClient()
    const result = await createCatalogService(fixture.client)
      .createCategory(createContext(roleCode), createInput())

    assert.equal(result.ok, false)
    assert.equal(result.error.kind, 'authorization-error')
    assert.deepEqual(fixture.calls, [])
  }
})

test('traduce errores internos desconocidos a un mensaje recuperable seguro', async () => {
  const fixture = createClient({
    mutationError: {
      code: 'XX000',
      message: 'SQL constraint private-token test-user-own',
    },
  })

  const result = await createCatalogService(fixture.client)
    .updateCategory(createContext(), 'category-main', createInput())

  assert.equal(result.ok, false)
  assert.equal(result.error.kind, 'connection-error')
  assert.equal(result.error.recoverable, true)
  assert.match(result.error.message, /intenta nuevamente/i)
  assert.doesNotMatch(result.error.message, /SQL|constraint|private-token|test-user-own/i)
})

test('traduce excepciones de red sin revelar detalles sensibles', async () => {
  const fixture = createClient({
    rejection: new Error('SQL private-token test-user-own'),
  })

  const result = await createCatalogService(fixture.client)
    .deleteCategory(createContext(), 'category-main', true)

  assert.equal(result.ok, false)
  assert.equal(result.error.recoverable, true)
  assert.doesNotMatch(result.error.message, /SQL|private-token|test-user-own/i)
})

test('informa un error recuperable si falla la recarga posterior a una mutación', async () => {
  const fixture = createClient({
    reloadError: { message: 'SQL private-token test-user-own' },
  })

  const result = await createCatalogService(fixture.client)
    .createCategory(createContext(), createInput())

  assert.equal(result.ok, false)
  assert.equal(result.error.kind, 'connection-error')
  assert.equal(result.error.recoverable, true)
  assert.doesNotMatch(result.error.message, /SQL|private-token|test-user-own/i)
  assertCatalogReloaded(fixture.calls)
})

test('preserva los espacios interiores y la capitalización original de código y nombre', async () => {
  const fixture = createClient()

  const result = await createCatalogService(fixture.client)
    .createCategory(createContext(), createInput({
      codigo: '  Mi Código  ',
      nombre: '  Nombre Con Espacios  ',
    }))

  assert.equal(result.ok, true)
  assert.equal(findMutation(fixture.calls).payload.codigo, 'Mi Código')
  assert.equal(findMutation(fixture.calls).payload.nombre, 'Nombre Con Espacios')
})
