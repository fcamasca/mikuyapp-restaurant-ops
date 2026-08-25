import assert from 'node:assert/strict'
import { test } from 'node:test'
import { createCatalogService } from '../src/services/catalogService.ts'

const categoryColumns = 'id,codigo,nombre,orden,activo'
const productColumns = 'id,categoria_id,codigo,nombre,precio,activo'

function createContext(roleCode = 'ADMINISTRADOR') {
  return {
    profile: {
      id: 'test-user-own',
      local_id: 'test-local-own',
      rol_id: 1,
      nombre: 'Usuario de prueba',
      activo: true,
    },
    role: {
      id: 1,
      codigo: roleCode,
      activo: true,
    },
    local: {
      id: 'test-local-own',
      activo: true,
    },
  }
}

function createCategory(overrides = {}) {
  return {
    id: 'category-main',
    codigo: 'MAIN',
    nombre: 'Principal',
    orden: 1,
    activo: true,
    ...overrides,
  }
}

function createProduct(overrides = {}) {
  return {
    id: 'product-main',
    categoria_id: 'category-main',
    codigo: 'MAIN-01',
    nombre: 'Producto principal',
    precio: 12.5,
    activo: true,
    ...overrides,
  }
}

function createClient({ categories = [], products = [], errors = {}, rejection = null } = {}) {
  const calls = []

  const client = {
    from(table) {
      const call = { table, columns: null, filters: [], orders: [] }
      calls.push(call)

      const query = {
        select(columns) {
          call.columns = columns
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
          if (rejection) {
            throw rejection
          }

          return {
            data: table === 'categoria' ? categories : products,
            error: errors[table] ?? null,
          }
        },
      }

      return query
    },
  }

  return { client, calls }
}

test('administrador conserva categorías y productos activos e inactivos', async () => {
  const categories = [
    createCategory(),
    createCategory({ id: 'category-inactive', codigo: 'INACTIVE', activo: false }),
  ]
  const products = [
    createProduct(),
    createProduct({
      id: 'product-inactive',
      categoria_id: 'category-inactive',
      codigo: 'INACTIVE-01',
      activo: false,
    }),
  ]
  const fixture = createClient({ categories, products })

  const result = await createCatalogService(fixture.client)
    .getAdministrativeCatalog(createContext())

  assert.equal(result.ok, true)
  assert.equal(result.data.categories.length, 2)
  assert.equal(result.data.products.length, 2)
  assert.equal(result.data.categories.some((category) => !category.activo), true)
  assert.equal(result.data.products.some((product) => !product.activo), true)
  assert.equal(fixture.calls.every((call) =>
    !call.filters.some((filter) => filter.column === 'activo'),
  ), true)
})

test('administración conserva categorías activas sin productos', async () => {
  const categories = [
    createCategory(),
    createCategory({ id: 'category-empty', codigo: 'EMPTY', nombre: 'Vacía', orden: 2 }),
  ]
  const fixture = createClient({ categories, products: [createProduct()] })

  const result = await createCatalogService(fixture.client)
    .getAdministrativeCatalog(createContext())

  assert.equal(result.ok, true)
  assert.equal(result.data.groups.length, 2)
  assert.deepEqual(result.data.groups[1].products, [])
})

test('carta operativa omite grupos de categorías activas sin productos', async () => {
  const categories = [
    createCategory(),
    createCategory({ id: 'category-empty', codigo: 'EMPTY', orden: 2 }),
  ]
  const fixture = createClient({ categories, products: [createProduct()] })

  const result = await createCatalogService(fixture.client)
    .getOperationalCatalog(createContext('MOZO'))

  assert.equal(result.ok, true)
  assert.equal(result.data.groups.length, 1)
  assert.equal(result.data.groups[0].category.id, 'category-main')
})

test('carta operativa excluye productos activos de categorías inactivas', async () => {
  const categories = [
    createCategory(),
    createCategory({ id: 'category-inactive', codigo: 'INACTIVE', activo: false }),
  ]
  const products = [
    createProduct(),
    createProduct({
      id: 'product-hidden',
      categoria_id: 'category-inactive',
      codigo: 'HIDDEN',
      activo: true,
    }),
  ]
  const fixture = createClient({ categories, products })

  const result = await createCatalogService(fixture.client)
    .getOperationalCatalog(createContext('COCINA'))

  assert.equal(result.ok, true)
  assert.deepEqual(
    result.data.groups.flatMap((group) => group.products.map((product) => product.id)),
    ['product-main'],
  )
})

test('carta operativa excluye productos inactivos aunque el doble los entregue', async () => {
  const products = [
    createProduct(),
    createProduct({ id: 'product-inactive', codigo: 'INACTIVE', activo: false }),
  ]
  const fixture = createClient({ categories: [createCategory()], products })

  const result = await createCatalogService(fixture.client)
    .getOperationalCatalog(createContext('CAJA'))

  assert.equal(result.ok, true)
  assert.deepEqual(result.data.groups[0].products.map((product) => product.id), ['product-main'])
})

test('agrupa correctamente cada producto bajo su propia categoría', async () => {
  const categories = [
    createCategory({ id: 'category-food', codigo: 'FOOD', nombre: 'Comidas', orden: 1 }),
    createCategory({ id: 'category-drinks', codigo: 'DRINKS', nombre: 'Bebidas', orden: 2 }),
  ]
  const products = [
    createProduct({ id: 'drink', categoria_id: 'category-drinks', nombre: 'Limonada' }),
    createProduct({ id: 'food', categoria_id: 'category-food', nombre: 'Saltado' }),
  ]
  const fixture = createClient({ categories, products })

  const result = await createCatalogService(fixture.client)
    .getOperationalCatalog(createContext('MOZO'))

  assert.equal(result.ok, true)
  assert.deepEqual(
    result.data.groups.map((group) => ({
      category: group.category.id,
      products: group.products.map((product) => product.id),
    })),
    [
      { category: 'category-food', products: ['food'] },
      { category: 'category-drinks', products: ['drink'] },
    ],
  )
})

test('ordena categorías por orden/nombre y productos por nombre/código estable', async () => {
  const categories = [
    createCategory({ id: 'category-z', codigo: 'Z', nombre: 'Zumos', orden: 2 }),
    createCategory({ id: 'category-a', codigo: 'A', nombre: 'Almuerzos', orden: 2 }),
    createCategory({ id: 'category-first', codigo: 'FIRST', nombre: 'Bebidas', orden: 1 }),
  ]
  const products = [
    createProduct({
      id: 'product-z', categoria_id: 'category-first', codigo: 'Z', nombre: 'Agua',
    }),
    createProduct({
      id: 'product-b', categoria_id: 'category-first', codigo: 'B', nombre: 'Zumo',
    }),
    createProduct({
      id: 'product-a', categoria_id: 'category-first', codigo: 'A', nombre: 'Agua',
    }),
  ]
  const fixture = createClient({ categories, products })

  const result = await createCatalogService(fixture.client)
    .getAdministrativeCatalog(createContext())

  assert.equal(result.ok, true)
  assert.deepEqual(
    result.data.categories.map((category) => category.id),
    ['category-first', 'category-a', 'category-z'],
  )
  assert.deepEqual(
    result.data.products.map((product) => product.id),
    ['product-a', 'product-z', 'product-b'],
  )
  assert.deepEqual(
    fixture.calls.find((call) => call.table === 'categoria').orders,
    [
      { column: 'orden', options: { ascending: true } },
      { column: 'nombre', options: { ascending: true } },
    ],
  )
  assert.deepEqual(
    fixture.calls.find((call) => call.table === 'producto').orders,
    [
      { column: 'nombre', options: { ascending: true } },
      { column: 'codigo', options: { ascending: true } },
    ],
  )
})

test('devuelve carta vacía cuando no existen productos visibles', async () => {
  const categories = [createCategory()]
  const products = [createProduct({ activo: false })]
  const fixture = createClient({ categories, products })

  const result = await createCatalogService(fixture.client)
    .getOperationalCatalog(createContext('MOZO'))

  assert.equal(result.ok, true)
  assert.deepEqual(result.data.groups, [])
})

test('devuelve carta vacía cuando RLS no entrega categorías', async () => {
  const fixture = createClient({ categories: [], products: [createProduct()] })

  const result = await createCatalogService(fixture.client)
    .getOperationalCatalog(createContext('CAJA'))

  assert.equal(result.ok, true)
  assert.deepEqual(result.data.groups, [])
})

test('filtra ambas consultas exclusivamente por el local del contexto validado', async () => {
  const fixture = createClient({ categories: [createCategory()], products: [createProduct()] })

  await createCatalogService(fixture.client)
    .getOperationalCatalog(createContext('COCINA'))

  assert.equal(fixture.calls.length, 2)
  for (const call of fixture.calls) {
    assert.deepEqual(call.filters[0], { column: 'local_id', value: 'test-local-own' })
    assert.deepEqual(call.filters[1], { column: 'activo', value: true })
  }
})

test('consulta únicamente las columnas mínimas de categorías y productos', async () => {
  const fixture = createClient({ categories: [createCategory()], products: [createProduct()] })

  await createCatalogService(fixture.client)
    .getAdministrativeCatalog(createContext())

  assert.equal(fixture.calls.find((call) => call.table === 'categoria').columns, categoryColumns)
  assert.equal(fixture.calls.find((call) => call.table === 'producto').columns, productColumns)
})

test('traduce un error de categoría a un mensaje recuperable sin información sensible', async () => {
  const fixture = createClient({
    errors: {
      categoria: {
        message: 'SQL select perfil_usuario token-private test-user-own',
      },
    },
  })

  const result = await createCatalogService(fixture.client)
    .getOperationalCatalog(createContext('MOZO'))

  assert.equal(result.ok, false)
  assert.equal(result.error.kind, 'connection-error')
  assert.equal(result.error.recoverable, true)
  assert.match(result.error.message, /intenta nuevamente/)
  assert.doesNotMatch(result.error.message, /SQL|token-private|test-user-own|perfil_usuario/i)
})

test('traduce un error de productos a un mensaje recuperable seguro', async () => {
  const fixture = createClient({
    categories: [createCategory()],
    errors: { producto: { message: 'refresh_token=internal-secret' } },
  })

  const result = await createCatalogService(fixture.client)
    .getAdministrativeCatalog(createContext())

  assert.equal(result.ok, false)
  assert.equal(result.error.kind, 'connection-error')
  assert.equal(result.error.recoverable, true)
  assert.doesNotMatch(result.error.message, /refresh_token|internal-secret/i)
})

test('traduce una excepción de red a un mensaje recuperable seguro', async () => {
  const fixture = createClient({
    rejection: new Error('SQL internal connection token-private'),
  })

  const result = await createCatalogService(fixture.client)
    .getOperationalCatalog(createContext('CAJA'))

  assert.equal(result.ok, false)
  assert.equal(result.error.recoverable, true)
  assert.doesNotMatch(result.error.message, /SQL|token-private/i)
})

test('no reconstruye categorías ni productos ocultos por la respuesta RLS', async () => {
  const visibleCategory = createCategory()
  const products = [
    createProduct(),
    createProduct({
      id: 'product-hidden-category',
      categoria_id: 'category-hidden-by-rls',
      codigo: 'HIDDEN',
    }),
  ]
  const adminFixture = createClient({ categories: [visibleCategory], products })
  const operationalFixture = createClient({ categories: [visibleCategory], products })

  const administrative = await createCatalogService(adminFixture.client)
    .getAdministrativeCatalog(createContext())
  const operational = await createCatalogService(operationalFixture.client)
    .getOperationalCatalog(createContext('MOZO'))

  assert.equal(administrative.ok, true)
  assert.deepEqual(administrative.data.products.map((product) => product.id), ['product-main'])
  assert.equal(operational.ok, true)
  assert.deepEqual(
    operational.data.groups.flatMap((group) => group.products.map((product) => product.id)),
    ['product-main'],
  )
})

test('rechaza la consulta administrativa de roles no administradores sin consultar Supabase', async () => {
  const fixture = createClient({ categories: [createCategory()], products: [createProduct()] })

  const result = await createCatalogService(fixture.client)
    .getAdministrativeCatalog(createContext('MOZO'))

  assert.equal(result.ok, false)
  assert.equal(result.error.kind, 'authorization-error')
  assert.equal(result.error.recoverable, false)
  assert.match(result.error.message, /autorización/)
  assert.deepEqual(fixture.calls, [])
})

test('permite reintentar una consulta después de un error recuperable', async () => {
  const failedFixture = createClient({ errors: { producto: { message: 'network failure' } } })
  const successFixture = createClient({
    categories: [createCategory()],
    products: [createProduct()],
  })

  const failed = await createCatalogService(failedFixture.client)
    .getOperationalCatalog(createContext('MOZO'))
  const retried = await createCatalogService(successFixture.client)
    .getOperationalCatalog(createContext('MOZO'))

  assert.equal(failed.ok, false)
  assert.equal(failed.error.recoverable, true)
  assert.equal(retried.ok, true)
  assert.equal(retried.data.groups.length, 1)
})
