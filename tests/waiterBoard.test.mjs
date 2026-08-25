import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import { test } from 'node:test'
import { resolveApplicationRoute } from '../src/services/appRoutes.ts'
import { createCatalogService } from '../src/services/catalogService.ts'

function createContext(roleCode = 'MOZO') {
  return {
    profile: {
      id: 'test-user-own', local_id: 'test-local-own', rol_id: 2,
      nombre: 'Mozo de prueba', activo: true,
    },
    role: { id: 2, codigo: roleCode, activo: true },
    local: { id: 'test-local-own', activo: true },
  }
}

function createCategory(overrides = {}) {
  return {
    id: 'category-main', codigo: 'MAIN', nombre: 'Principal',
    orden: 1, activo: true, ...overrides,
  }
}

function createProduct(overrides = {}) {
  return {
    id: 'product-main', categoria_id: 'category-main', codigo: 'MAIN-01',
    nombre: 'Producto principal', precio: 12.5, activo: true, ...overrides,
  }
}

function createTable(overrides = {}) {
  return {
    id: 'table-main', codigo: 'M-01', nombre: 'Mesa principal',
    estado: 'LIBRE', activo: true, ...overrides,
  }
}

function createClient({ categories = [], products = [], tables = [], errors = {}, rejection = null } = {}) {
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
          if (rejection) throw rejection
          const data = table === 'categoria' ? categories : table === 'producto' ? products : tables
          return { data, error: errors[table] ?? null }
        },
      }
      return query
    },
  }

  return { client, calls, errors }
}

const pageSource = readFileSync(
  new URL('../src/pages/WaiterTablesPage.tsx', import.meta.url),
  'utf8',
)

test('agrupa la carta y ordena categorías por orden/nombre y productos por nombre/código', async () => {
  const categories = [
    createCategory({ id: 'category-z', codigo: 'Z', nombre: 'Zumos', orden: 2 }),
    createCategory({ id: 'category-a', codigo: 'A', nombre: 'Almuerzos', orden: 2 }),
    createCategory({ id: 'category-first', codigo: 'FIRST', nombre: 'Bebidas', orden: 1 }),
  ]
  const products = [
    createProduct({ id: 'z', categoria_id: 'category-first', codigo: 'Z', nombre: 'Agua' }),
    createProduct({ id: 'a', categoria_id: 'category-first', codigo: 'A', nombre: 'Agua' }),
    createProduct({ id: 'meal', categoria_id: 'category-a', nombre: 'Saltado' }),
    createProduct({ id: 'juice', categoria_id: 'category-z', nombre: 'Naranja' }),
  ]
  const fixture = createClient({ categories, products })
  const result = await createCatalogService(fixture.client).getOperationalCatalog(createContext())

  assert.equal(result.ok, true)
  assert.deepEqual(result.data.groups.map((group) => group.category.nombre), [
    'Bebidas', 'Almuerzos', 'Zumos',
  ])
  assert.deepEqual(result.data.groups[0].products.map((product) => product.codigo), ['A', 'Z'])
})

test('excluye categorías inactivas y sus productos aunque aparezcan en la respuesta', async () => {
  const fixture = createClient({
    categories: [createCategory(), createCategory({ id: 'category-hidden', activo: false })],
    products: [createProduct(), createProduct({ id: 'hidden', categoria_id: 'category-hidden' })],
  })
  const result = await createCatalogService(fixture.client).getOperationalCatalog(createContext())

  assert.equal(result.ok, true)
  assert.deepEqual(result.data.groups.map((group) => group.category.id), ['category-main'])
  assert.deepEqual(result.data.groups[0].products.map((product) => product.id), ['product-main'])
})

test('excluye productos inactivos de la carta del mozo', async () => {
  const fixture = createClient({
    categories: [createCategory()],
    products: [createProduct(), createProduct({ id: 'product-hidden', activo: false })],
  })
  const result = await createCatalogService(fixture.client).getOperationalCatalog(createContext())

  assert.equal(result.ok, true)
  assert.deepEqual(result.data.groups[0].products.map((product) => product.id), ['product-main'])
})

test('omite categorías activas sin productos visibles', async () => {
  const fixture = createClient({
    categories: [createCategory(), createCategory({ id: 'category-empty', orden: 2 })],
    products: [createProduct()],
  })
  const result = await createCatalogService(fixture.client).getOperationalCatalog(createContext())

  assert.equal(result.ok, true)
  assert.deepEqual(result.data.groups.map((group) => group.category.id), ['category-main'])
})

test('devuelve carta vacía si no existen productos visibles', async () => {
  const fixture = createClient({
    categories: [createCategory()],
    products: [createProduct({ activo: false })],
  })
  const result = await createCatalogService(fixture.client).getOperationalCatalog(createContext())

  assert.equal(result.ok, true)
  assert.deepEqual(result.data.groups, [])
})

test('filtra mesas por local validado y activo, consultando únicamente columnas permitidas', async () => {
  const fixture = createClient({ tables: [createTable()] })
  const result = await createCatalogService(fixture.client).getOperationalTables(createContext())

  assert.equal(result.ok, true)
  assert.equal(fixture.calls.length, 1)
  assert.equal(fixture.calls[0].table, 'mesa')
  assert.equal(fixture.calls[0].columns, 'id,codigo,nombre,estado,activo')
  assert.deepEqual(fixture.calls[0].filters, [
    { column: 'local_id', value: 'test-local-own' },
    { column: 'activo', value: true },
  ])
  assert.deepEqual(fixture.calls[0].orders.map((order) => order.column), ['codigo', 'nombre'])
})

test('excluye mesas inactivas aunque el doble las entregue', async () => {
  const fixture = createClient({
    tables: [createTable(), createTable({ id: 'table-hidden', activo: false })],
  })
  const result = await createCatalogService(fixture.client).getOperationalTables(createContext())

  assert.equal(result.ok, true)
  assert.deepEqual(result.data.map((table) => table.id), ['table-main'])
})

test('ordena mesas de manera estable por código y después por nombre', async () => {
  const fixture = createClient({
    tables: [
      createTable({ id: 'second', codigo: 'M-02', nombre: 'Segunda' }),
      createTable({ id: 'first-z', codigo: 'M-01', nombre: 'Zona' }),
      createTable({ id: 'first-a', codigo: 'M-01', nombre: 'Acceso' }),
    ],
  })
  const result = await createCatalogService(fixture.client).getOperationalTables(createContext())

  assert.equal(result.ok, true)
  assert.deepEqual(result.data.map((table) => table.id), ['first-a', 'first-z', 'second'])
})

test('representa los cuatro estados operativos con etiquetas textuales y leyenda', async () => {
  const statuses = ['LIBRE', 'OCUPADA', 'PEDIDO_LISTO', 'PENDIENTE_PAGO']
  const fixture = createClient({
    tables: statuses.map((estado, index) => createTable({ id: `table-${index}`, estado })),
  })
  const result = await createCatalogService(fixture.client).getOperationalTables(createContext())

  assert.equal(result.ok, true)
  assert.deepEqual(new Set(result.data.map((table) => table.estado)), new Set(statuses))
  assert.match(pageSource, /label: 'Libre'/)
  assert.match(pageSource, /label: 'Ocupada'/)
  assert.match(pageSource, /label: 'Pedido listo'/)
  assert.match(pageSource, /label: 'Pendiente de pago'/)
  assert.match(pageSource, /Leyenda de estados de mesas/)
  assert.match(pageSource, /Estado: \{status\.label\}/)
})

test('el tablero muestra texto de estado además de su diferenciación visual', () => {
  assert.match(pageSource, /className=\{`rounded-2xl border p-4 \$\{status\.className\}`\}/)
  assert.match(pageSource, /Estado: \{status\.label\}/)
  assert.match(pageSource, /\{status\.description\}/)
})

test('la página del mozo no incluye controles ni operaciones de mutación', () => {
  assert.doesNotMatch(pageSource, /createTable|updateTable|setTableActive|deleteTable/)
  assert.doesNotMatch(pageSource, /\.insert\(|\.update\(|\.delete\(|\.channel\(/)
  assert.doesNotMatch(pageSource, /onClick=\{\(\) =>[^}]*table/)
  assert.doesNotMatch(pageSource, /Crear pedido|Seleccionar mesa|Editar mesa|Eliminar mesa/)
})

test('la pantalla muestra indicadores de carga independientes para carta y mesas', () => {
  assert.match(pageSource, /\[tablesLoading, setTablesLoading\]/)
  assert.match(pageSource, /\[catalogLoading, setCatalogLoading\]/)
  assert.match(pageSource, /Cargando mesas…/)
  assert.match(pageSource, /Cargando carta…/)
})

test('la pantalla diferencia vacíos de mesas y productos', () => {
  assert.match(pageSource, /No hay mesas disponibles/)
  assert.match(pageSource, /No hay productos disponibles/)
})

test('la pantalla ofrece errores y reintentos independientes', () => {
  assert.match(pageSource, /\[tablesError, setTablesError\]/)
  assert.match(pageSource, /\[catalogError, setCatalogError\]/)
  assert.match(pageSource, /setTablesAttempt\(\(attempt\) => attempt \+ 1\)/)
  assert.match(pageSource, /setCatalogAttempt\(\(attempt\) => attempt \+ 1\)/)
  assert.match(pageSource, /Reintentar mesas/)
  assert.match(pageSource, /Reintentar carta/)
})

test('muestra nombres y precios de productos con formato de moneda local', () => {
  assert.match(pageSource, /currency: 'PEN'/)
  assert.match(pageSource, /\{group\.category\.nombre\}/)
  assert.match(pageSource, /\{product\.nombre\}/)
  assert.match(pageSource, /priceFormatter\.format\(product\.precio\)/)
})

test('un error de mesas permanece seguro y no impide consultar la carta', async () => {
  const fixture = createClient({
    categories: [createCategory()], products: [createProduct()],
    errors: { mesa: { message: 'private SQL internal-token' } },
  })
  const service = createCatalogService(fixture.client)
  const tables = await service.getOperationalTables(createContext())
  const catalog = await service.getOperationalCatalog(createContext())

  assert.equal(tables.ok, false)
  assert.equal(tables.error.kind, 'connection-error')
  assert.equal(tables.error.recoverable, true)
  assert.doesNotMatch(tables.error.message, /SQL|token/)
  assert.equal(catalog.ok, true)
})

test('un error de carta no impide consultar las mesas activas', async () => {
  const fixture = createClient({
    tables: [createTable()],
    errors: { categoria: { message: 'private SQL internal-token' } },
  })
  const service = createCatalogService(fixture.client)
  const catalog = await service.getOperationalCatalog(createContext())
  const tables = await service.getOperationalTables(createContext())

  assert.equal(catalog.ok, false)
  assert.doesNotMatch(catalog.error.message, /SQL|token/)
  assert.equal(tables.ok, true)
  assert.equal(tables.data.length, 1)
})

test('permite reintentar una lectura de mesas después de un error recuperable', async () => {
  const errors = { mesa: { message: 'temporary failure' } }
  const fixture = createClient({ tables: [createTable()], errors })
  const service = createCatalogService(fixture.client)

  const initial = await service.getOperationalTables(createContext())
  assert.equal(initial.ok, false)
  delete errors.mesa

  const retried = await service.getOperationalTables(createContext())
  assert.equal(retried.ok, true)
  assert.equal(retried.data.length, 1)
})

test('traduce excepciones de red de mesas sin revelar información sensible', async () => {
  const fixture = createClient({ rejection: new Error('private SQL internal-token') })
  const result = await createCatalogService(fixture.client).getOperationalTables(createContext())

  assert.equal(result.ok, false)
  assert.equal(result.error.recoverable, true)
  assert.doesNotMatch(result.error.message, /SQL|token/)
})

test('devuelve resultado vacío cuando no hay mesas activas', async () => {
  const fixture = createClient({ tables: [createTable({ activo: false })] })
  const result = await createCatalogService(fixture.client).getOperationalTables(createContext())

  assert.equal(result.ok, true)
  assert.deepEqual(result.data, [])
})

test('bloquea por guarda y servicio el acceso de roles distintos de MOZO', async () => {
  for (const role of ['ADMINISTRADOR', 'COCINA', 'CAJA']) {
    const resolution = resolveApplicationRoute({
      pathname: '/mozo/mesas', authenticationStatus: 'authenticated',
      contextStatus: 'valid', role,
    })
    assert.deepEqual(resolution, { status: 'redirect', pathname: '/403' })

    const fixture = createClient({ tables: [createTable()] })
    const result = await createCatalogService(fixture.client).getOperationalTables(createContext(role))
    assert.equal(result.ok, false)
    assert.equal(result.error.kind, 'authorization-error')
    assert.deepEqual(fixture.calls, [])
  }
})

test('las consultas operativas conservan filtros explícitos del local y registros activos', async () => {
  const fixture = createClient({
    categories: [createCategory()], products: [createProduct()], tables: [createTable()],
  })
  const service = createCatalogService(fixture.client)
  await service.getOperationalCatalog(createContext())
  await service.getOperationalTables(createContext())

  assert.deepEqual(fixture.calls.map((call) => call.table), ['categoria', 'producto', 'mesa'])
  for (const call of fixture.calls) {
    assert.deepEqual(call.filters, [
      { column: 'local_id', value: 'test-local-own' },
      { column: 'activo', value: true },
    ])
  }
})
