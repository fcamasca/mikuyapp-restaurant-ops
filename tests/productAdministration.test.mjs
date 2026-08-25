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

function createCategory(overrides = {}) {
  return {
    id: 'category-main', codigo: 'Category-Main', nombre: 'Categoría principal',
    orden: 1, activo: true, ...overrides,
  }
}

function createProduct(overrides = {}) {
  return {
    id: 'product-main', categoria_id: 'category-main', codigo: 'Product-01',
    nombre: 'Producto principal', precio: 12.5, activo: true, ...overrides,
  }
}

function createInput(overrides = {}) {
  return {
    categoria_id: 'category-main', codigo: ' Nuevo-Prod ',
    nombre: ' Nuevo producto ', precio: 18.5, activo: true, ...overrides,
  }
}

function createClient({
  categories = [createCategory()], products = [createProduct()],
  mutationError = null, rejection = null, reloadError = null,
} = {}) {
  const calls = []
  const currentProducts = [...products]

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
          if (reloadError) {
            return { data: null, error: reloadError }
          }

          return {
            data: table === 'categoria'
              ? categories.map((category) => ({ ...category }))
              : currentProducts.map((product) => ({ ...product })),
            error: null,
          }
        },
        then(onFulfilled, onRejected) {
          return Promise.resolve().then(() => {
            if (rejection) throw rejection
            if (mutationError) return { error: mutationError }

            const targetId = call.filters.find((filter) => filter.column === 'id')?.value
            if (call.operation === 'insert') {
              currentProducts.push({
                id: 'product-created',
                categoria_id: call.payload.categoria_id,
                codigo: call.payload.codigo,
                nombre: call.payload.nombre,
                precio: call.payload.precio,
                activo: call.payload.activo,
              })
            }
            if (call.operation === 'update') {
              const index = currentProducts.findIndex((product) => product.id === targetId)
              if (index >= 0) currentProducts[index] = { ...currentProducts[index], ...call.payload }
            }
            if (call.operation === 'delete') {
              const index = currentProducts.findIndex((product) => product.id === targetId)
              if (index >= 0) currentProducts.splice(index, 1)
            }
            return { error: null }
          }).then(onFulfilled, onRejected)
        },
      }

      return query
    },
  }

  return { client, calls, categories }
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

test('crea un producto válido con columnas exactas y conserva su capitalización', async () => {
  const fixture = createClient()
  const result = await createCatalogService(fixture.client)
    .createProduct(createContext(), createInput(), fixture.categories)

  assert.equal(result.ok, true)
  assert.deepEqual(findMutation(fixture.calls).payload, {
    local_id: 'test-local-own', categoria_id: 'category-main', codigo: 'Nuevo-Prod',
    nombre: 'Nuevo producto', precio: 18.5, activo: true,
  })
  assert.equal(result.data.catalog.products.length, 2)
  assert.match(result.data.message, /creó correctamente/)
  assertCatalogReloaded(fixture.calls)
})

test('edita un producto con columnas exactas y sin campos protegidos', async () => {
  const fixture = createClient()
  const result = await createCatalogService(fixture.client)
    .updateProduct(createContext(), 'product-main', createInput({ activo: false }), fixture.categories)

  assert.equal(result.ok, true)
  const mutation = findMutation(fixture.calls)
  assert.deepEqual(mutation.payload, {
    categoria_id: 'category-main', codigo: 'Nuevo-Prod', nombre: 'Nuevo producto',
    precio: 18.5, activo: false,
  })
  assert.deepEqual(mutation.filters, [
    { column: 'id', value: 'product-main' },
    { column: 'local_id', value: 'test-local-own' },
  ])
  assertCatalogReloaded(fixture.calls)
})

test('permite cambiar el producto a otra categoría del mismo catálogo', async () => {
  const categories = [
    createCategory(),
    createCategory({ id: 'category-second', codigo: 'Second', orden: 2 }),
  ]
  const fixture = createClient({ categories })
  const result = await createCatalogService(fixture.client)
    .updateProduct(createContext(), 'product-main', createInput({
      categoria_id: 'category-second',
    }), fixture.categories)

  assert.equal(result.ok, true)
  assert.equal(findMutation(fixture.calls).payload.categoria_id, 'category-second')
  assert.equal(result.data.catalog.groups.find((group) =>
    group.category.id === 'category-second',
  ).products[0].id, 'product-main')
})

test('activa y reactiva un producto enviando exclusivamente activo', async () => {
  for (const previousState of [false]) {
    const fixture = createClient({ products: [createProduct({ activo: previousState })] })
    const result = await createCatalogService(fixture.client)
      .setProductActive(createContext(), 'product-main', true)

    assert.equal(result.ok, true)
    assert.deepEqual(findMutation(fixture.calls).payload, { activo: true })
    assert.equal(result.data.catalog.products[0].activo, true)
    assert.match(result.data.message, /activó correctamente/)
    assertCatalogReloaded(fixture.calls)
  }
})

test('desactiva un producto enviando exclusivamente activo', async () => {
  const fixture = createClient()
  const result = await createCatalogService(fixture.client)
    .setProductActive(createContext(), 'product-main', false)

  assert.equal(result.ok, true)
  assert.deepEqual(findMutation(fixture.calls).payload, { activo: false })
  assert.equal(result.data.catalog.products[0].activo, false)
  assert.match(result.data.message, /desactivó correctamente/)
})

test('permite producto activo en categoría inactiva y lo conserva para administración', async () => {
  const categories = [createCategory({ activo: false })]
  const fixture = createClient({ categories })
  const result = await createCatalogService(fixture.client)
    .createProduct(createContext(), createInput({ activo: true }), fixture.categories)

  assert.equal(result.ok, true)
  assert.equal(result.data.catalog.categories[0].activo, false)
  assert.equal(result.data.catalog.products.some((product) =>
    product.id === 'product-created' && product.activo,
  ), true)

  const operational = await createCatalogService(fixture.client)
    .getOperationalCatalog(createContext('MOZO'))
  assert.equal(operational.ok, true)
  assert.deepEqual(operational.data.groups, [])
})

test('elimina físicamente un producto confirmado y recarga el catálogo', async () => {
  const fixture = createClient()
  const result = await createCatalogService(fixture.client)
    .deleteProduct(createContext(), 'product-main', true)

  assert.equal(result.ok, true)
  assert.equal(findMutation(fixture.calls).operation, 'delete')
  assert.deepEqual(findMutation(fixture.calls).filters, [
    { column: 'id', value: 'product-main' },
    { column: 'local_id', value: 'test-local-own' },
  ])
  assert.deepEqual(result.data.catalog.products, [])
  assertCatalogReloaded(fixture.calls)
})

test('cancelar la eliminación de un producto no ejecuta consultas', async () => {
  const fixture = createClient()
  const result = await createCatalogService(fixture.client)
    .deleteProduct(createContext(), 'product-main', false)

  assert.equal(result.ok, true)
  assert.equal(result.data.status, 'cancelled')
  assert.equal(result.data.catalog, null)
  assert.deepEqual(fixture.calls, [])
})

test('traduce historial de pedidos y recomienda desactivar el producto', async () => {
  const fixture = createClient({ mutationError: {
    code: '23503', message: 'fk_detalle_pedido_producto SQL private-token',
  } })
  const result = await createCatalogService(fixture.client)
    .deleteProduct(createContext(), 'product-main', true)

  assert.equal(result.ok, false)
  assert.equal(result.error.kind, 'product-has-history')
  assert.match(result.error.message, /pedidos relacionados/)
  assert.match(result.error.message, /desactivarlo/)
  assert.doesNotMatch(result.error.message, /fk_|SQL|private-token/i)
})

test('la confirmación de producto identifica nombre y código y bloquea duplicados', () => {
  const source = readFileSync(
    new URL('../src/pages/CategoryAdministrationPage.tsx', import.meta.url),
    'utf8',
  )
  const start = source.indexOf('function deleteProduct(')
  const end = source.indexOf('async function runTableMutation(', start)
  const deletion = source.slice(start, end)

  assert.match(deletion, /if \(!service \|\| saving \|\| mutationPending\.current\)/)
  assert.match(deletion, /window\.confirm\(/)
  assert.match(deletion, /producto «\$\{product\.nombre\}» \(\$\{product\.codigo\}\)/)
  assert.match(deletion, /service\.deleteProduct\(context, product\.id, confirmed\)/)
})

test('elimina únicamente el producto elegido y conserva categorías y otros productos', async () => {
  const fixture = createClient({
    products: [
      createProduct(),
      createProduct({ id: 'product-other', codigo: 'Other', nombre: 'Otro producto' }),
    ],
  })
  const result = await createCatalogService(fixture.client)
    .deleteProduct(createContext(), 'product-main', true)

  assert.equal(result.ok, true)
  assert.deepEqual(result.data.catalog.products.map((product) => product.id), ['product-other'])
  assert.deepEqual(result.data.catalog.categories.map((category) => category.id), ['category-main'])
  assert.deepEqual(fixture.calls.filter((call) => call.operation === 'delete').map((call) => call.table), [
    'producto',
  ])
  assert.equal(fixture.calls.some((call) => call.operation === 'update'), false)
})

test('conserva el producto tras rechazo por historial sin eliminar detalles ni desactivarlo', async () => {
  const fixture = createClient({ mutationError: { code: '23503', message: 'private SQL constraint' } })
  const service = createCatalogService(fixture.client)
  const rejected = await service.deleteProduct(createContext(), 'product-main', true)
  const catalog = await service.getAdministrativeCatalog(createContext())

  assert.equal(rejected.ok, false)
  assert.equal(catalog.ok, true)
  assert.deepEqual(catalog.data.products.map((product) => product.id), ['product-main'])
  assert.equal(catalog.data.products[0].activo, true)
  assert.deepEqual(fixture.calls.filter((call) => call.operation === 'delete').map((call) => call.table), [
    'producto',
  ])
  assert.equal(fixture.calls.some((call) => call.operation === 'update'), false)
  assert.equal(fixture.calls.some((call) => call.table === 'detalle_pedido'), false)
})

test('traduce denegaciones de eliminación de producto sin revelar detalles internos', async () => {
  for (const code of ['42501', 'PGRST301']) {
    const fixture = createClient({ mutationError: { code, message: 'private SQL internal-token' } })
    const result = await createCatalogService(fixture.client)
      .deleteProduct(createContext(), 'product-main', true)

    assert.equal(result.ok, false)
    assert.equal(result.error.kind, 'authorization-error')
    assert.match(result.error.message, /operación no está permitida/)
    assert.doesNotMatch(result.error.message, /SQL|token/)
    assert.equal(fixture.calls.length, 1)
  }
})

test('traduce errores inesperados al eliminar un producto sin desactivarlo', async () => {
  const fixture = createClient({ mutationError: {
    code: 'XX000', message: 'private SQL constraint internal-token',
  } })
  const result = await createCatalogService(fixture.client)
    .deleteProduct(createContext(), 'product-main', true)

  assert.equal(result.ok, false)
  assert.equal(result.error.recoverable, true)
  assert.doesNotMatch(result.error.message, /SQL|constraint|token/)
  assert.equal(fixture.calls.length, 1)
  assert.equal(fixture.calls[0].operation, 'delete')
})

test('traduce códigos duplicados de productos sin revelar constraints', async () => {
  const fixture = createClient({ mutationError: {
    code: '23505', message: 'uq_producto_local_id_codigo SQL private-token',
  } })
  const result = await createCatalogService(fixture.client)
    .createProduct(createContext(), createInput(), fixture.categories)

  assert.equal(result.ok, false)
  assert.equal(result.error.kind, 'duplicate-product-code')
  assert.match(result.error.message, /ya existe un producto con ese código/i)
  assert.doesNotMatch(result.error.message, /uq_|SQL|private-token/i)
})

test('rechaza códigos vacíos o compuestos únicamente por espacios', async () => {
  for (const codigo of ['', '   ']) {
    const fixture = createClient()
    const result = await createCatalogService(fixture.client)
      .createProduct(createContext(), createInput({ codigo }), fixture.categories)
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
      .updateProduct(createContext(), 'product-main', createInput({ nombre }), fixture.categories)
    assert.equal(result.ok, false)
    assert.equal(result.error.kind, 'validation-error')
    assert.match(result.error.message, /nombre/)
    assert.deepEqual(fixture.calls, [])
  }
})

test('rechaza precios negativos, no numéricos, NaN e infinitos', async () => {
  for (const precio of [
    -1, '', '   ', '12', 'texto', null, undefined,
    Number.NaN, Number.POSITIVE_INFINITY, Number.NEGATIVE_INFINITY,
  ]) {
    const fixture = createClient()
    const result = await createCatalogService(fixture.client)
      .createProduct(createContext(), createInput({ precio }), fixture.categories)
    assert.equal(result.ok, false)
    assert.equal(result.error.kind, 'validation-error')
    assert.match(result.error.message, /precio/)
    assert.deepEqual(fixture.calls, [])
  }
})

test('rechaza precio vacío antes de convertirlo accidentalmente en cero', () => {
  const source = readFileSync(
    new URL('../src/pages/CategoryAdministrationPage.tsx', import.meta.url),
    'utf8',
  )
  const start = source.indexOf('function submitProduct(')
  const end = source.indexOf('function toggleProduct(', start)
  const submit = source.slice(start, end)

  assert.match(submit, /if \(!productForm\.precio\.trim\(\)\)/)
  assert.match(submit, /setProductError\('Ingresa el precio del producto\.'\)/)
  assert.ok(submit.indexOf('!productForm.precio.trim()') < submit.indexOf('Number(productForm.precio)'))
})

test('conserva el formulario de productos ante error y bloquea envíos duplicados', () => {
  const source = readFileSync(
    new URL('../src/pages/CategoryAdministrationPage.tsx', import.meta.url),
    'utf8',
  )
  const start = source.indexOf('async function runProductMutation(')
  const end = source.indexOf('function submitProduct(', start)
  const mutation = source.slice(start, end)

  assert.match(mutation, /if \(mutationPending\.current\) \{\s*return\s*\}/)
  assert.match(mutation, /mutationPending\.current = true/)
  assert.match(mutation, /if \(!result\.ok\) \{\s*setProductError\(result\.error\.message\)\s*return\s*\}/)
  assert.ok(mutation.indexOf('if (!result.ok)') < mutation.indexOf('resetProductForm()'))
  assert.match(mutation, /finally \{\s*mutationPending\.current = false/)
})

test('acepta un precio numérico igual a cero', async () => {
  const fixture = createClient()
  const result = await createCatalogService(fixture.client)
    .createProduct(createContext(), createInput({ precio: 0 }), fixture.categories)

  assert.equal(result.ok, true)
  assert.equal(findMutation(fixture.calls).payload.precio, 0)
})

test('rechaza una categoría ausente antes de consultar Supabase', async () => {
  for (const categoria_id of ['', '   ']) {
    const fixture = createClient()
    const result = await createCatalogService(fixture.client)
      .createProduct(createContext(), createInput({ categoria_id }), fixture.categories)
    assert.equal(result.ok, false)
    assert.equal(result.error.kind, 'validation-error')
    assert.match(result.error.message, /selecciona una categoría/i)
    assert.deepEqual(fixture.calls, [])
  }
})

test('rechaza categorías inexistentes o ajenas al catálogo del local', async () => {
  for (const categoria_id of ['category-missing', 'category-foreign-local']) {
    const fixture = createClient()
    const result = await createCatalogService(fixture.client)
      .updateProduct(createContext(), 'product-main', createInput({ categoria_id }), fixture.categories)
    assert.equal(result.ok, false)
    assert.equal(result.error.kind, 'invalid-product-category')
    assert.match(result.error.message, /no está disponible para tu local/)
    assert.deepEqual(fixture.calls, [])
  }
})

test('traduce el rechazo de la FK compuesta como categoría inexistente o ajena', async () => {
  const fixture = createClient({ mutationError: {
    code: '23503', message: 'fk_producto_categoria_local SQL private-token',
  } })
  const result = await createCatalogService(fixture.client)
    .createProduct(createContext(), createInput(), fixture.categories)

  assert.equal(result.ok, false)
  assert.equal(result.error.kind, 'invalid-product-category')
  assert.match(result.error.message, /no existe o no pertenece a tu local/)
  assert.doesNotMatch(result.error.message, /fk_|SQL|private-token/i)
})

test('rechaza completamente campos protegidos en una inserción manipulada', async () => {
  const fixture = createClient()
  const unsafeInput = {
    ...createInput(), local_id: 'test-local-foreign',
    id: 'test-product-forged', creado_en: 'test-forged-date',
  }
  const result = await createCatalogService(fixture.client)
    .createProduct(createContext(), unsafeInput, fixture.categories)

  assert.equal(result.ok, false)
  assert.equal(result.error.kind, 'authorization-error')
  assert.deepEqual(fixture.calls, [])
})

test('rechaza completamente id, local_id y creado_en manipulados durante UPDATE', async () => {
  const fixture = createClient()
  const unsafeInput = {
    ...createInput(), local_id: 'test-local-foreign',
    id: 'test-product-forged', creado_en: 'test-forged-date',
  }
  const result = await createCatalogService(fixture.client)
    .updateProduct(createContext(), 'product-main', unsafeInput, fixture.categories)

  assert.equal(result.ok, false)
  assert.equal(result.error.kind, 'authorization-error')
  assert.deepEqual(fixture.calls, [])
})

test('recarga categorías, productos y agrupaciones después de modificar un producto', async () => {
  const fixture = createClient()
  const result = await createCatalogService(fixture.client)
    .updateProduct(createContext(), 'product-main', createInput({
      nombre: 'Producto actualizado',
    }), fixture.categories)

  assert.equal(result.ok, true)
  assert.equal(result.data.catalog.categories.length, 1)
  assert.equal(result.data.catalog.products[0].nombre, 'Producto actualizado')
  assert.equal(result.data.catalog.groups[0].products[0].nombre, 'Producto actualizado')
  assertCatalogReloaded(fixture.calls)
})

test('traduce permisos PostgreSQL denegados a un mensaje seguro', async () => {
  const fixture = createClient({ mutationError: {
    code: '42501', message: 'permission denied SQL private-token',
  } })
  const result = await createCatalogService(fixture.client)
    .setProductActive(createContext(), 'product-main', false)

  assert.equal(result.ok, false)
  assert.equal(result.error.kind, 'authorization-error')
  assert.match(result.error.message, /operación no está permitida/)
  assert.doesNotMatch(result.error.message, /SQL|private-token/i)
})

test('rechaza mutaciones de usuarios que no son administradores', async () => {
  for (const role of ['MOZO', 'COCINA', 'CAJA']) {
    const fixture = createClient()
    const result = await createCatalogService(fixture.client)
      .createProduct(createContext(role), createInput(), fixture.categories)
    assert.equal(result.ok, false)
    assert.equal(result.error.kind, 'authorization-error')
    assert.deepEqual(fixture.calls, [])
  }
})

test('traduce errores internos a mensajes recuperables sin SQL ni tokens', async () => {
  const fixture = createClient({ mutationError: {
    code: 'XX000', message: 'SQL constraint private-token test-user-own',
  } })
  const result = await createCatalogService(fixture.client)
    .updateProduct(createContext(), 'product-main', createInput(), fixture.categories)

  assert.equal(result.ok, false)
  assert.equal(result.error.kind, 'connection-error')
  assert.equal(result.error.recoverable, true)
  assert.doesNotMatch(result.error.message, /SQL|constraint|private-token|test-user-own/i)
})

test('traduce errores de red a mensajes recuperables seguros', async () => {
  const fixture = createClient({ rejection: new Error('SQL private-token test-user-own') })
  const result = await createCatalogService(fixture.client)
    .deleteProduct(createContext(), 'product-main', true)

  assert.equal(result.ok, false)
  assert.equal(result.error.recoverable, true)
  assert.doesNotMatch(result.error.message, /SQL|private-token|test-user-own/i)
})

test('traduce validaciones PostgreSQL de precio sin revelar restricciones', async () => {
  const fixture = createClient({ mutationError: {
    code: '23514', message: 'ck_producto_precio_no_negativo SQL private-token',
  } })
  const result = await createCatalogService(fixture.client)
    .createProduct(createContext(), createInput(), fixture.categories)

  assert.equal(result.ok, false)
  assert.equal(result.error.kind, 'validation-error')
  assert.match(result.error.message, /precio/)
  assert.doesNotMatch(result.error.message, /ck_|SQL|private-token/i)
})

test('informa fallo recuperable cuando la recarga posterior no está disponible', async () => {
  const fixture = createClient({ reloadError: { message: 'SQL private-token' } })
  const result = await createCatalogService(fixture.client)
    .createProduct(createContext(), createInput(), fixture.categories)

  assert.equal(result.ok, false)
  assert.equal(result.error.recoverable, true)
  assert.doesNotMatch(result.error.message, /SQL|private-token/i)
  assertCatalogReloaded(fixture.calls)
})

test('conserva espacios interiores y mayúsculas originales en código y nombre', async () => {
  const fixture = createClient()
  const result = await createCatalogService(fixture.client)
    .createProduct(createContext(), createInput({
      codigo: '  Mi Código  ', nombre: '  Nombre Con Espacios  ',
    }), fixture.categories)

  assert.equal(result.ok, true)
  assert.equal(findMutation(fixture.calls).payload.codigo, 'Mi Código')
  assert.equal(findMutation(fixture.calls).payload.nombre, 'Nombre Con Espacios')
})
