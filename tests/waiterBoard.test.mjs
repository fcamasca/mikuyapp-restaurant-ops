import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import test from 'node:test'
import { getWaiterOrderId, resolveApplicationRoute } from '../src/services/appRoutes.ts'
import { combineOrderObservation, createWaiterOrderService, filterAndSortWaiterTables } from '../src/services/waiterOrderService.ts'

const pageSource = readFileSync(new URL('../src/pages/WaiterTablesPage.tsx', import.meta.url), 'utf8')
const orderPageSource = readFileSync(new URL('../src/pages/WaiterOrderPage.tsx', import.meta.url), 'utf8')
const appSource = readFileSync(new URL('../src/App.tsx', import.meta.url), 'utf8')
const serviceSource = readFileSync(new URL('../src/services/waiterOrderService.ts', import.meta.url), 'utf8')
const consolidationMigration = readFileSync(new URL('../supabase/migrations/20260826000800_consolidate_open_order_details.sql', import.meta.url), 'utf8')

function context(role = 'MOZO') {
  return {
    profile: { id: 'user-own', local_id: 'local-own', rol_id: 2, nombre: 'Mozo', activo: true },
    role: { id: 2, codigo: role, activo: true },
    local: { id: 'local-own', activo: true },
  }
}

function table(overrides = {}) {
  return { id: 'table-1', codigo: 'M-01', nombre: 'Mesa 1', estado: 'LIBRE', activo: true, ...overrides }
}

function createClient({ tables = [], orders = [], details = [], errors = {}, rpcData = [{ pedido_id: 12, fue_creado: true }], rpcError = null } = {}) {
  const calls = []
  const rpcCalls = []
  return {
    calls,
    rpcCalls,
    client: {
      from(resource) {
        const call = { resource, columns: '', filters: [], inFilters: [], mutation: null }
        calls.push(call)
        const query = {
          select(columns) { call.columns = columns; return query },
          eq(column, value) { call.filters.push({ column, value }); return query },
          in(column, values) { call.inFilters.push({ column, values }); return query },
          update(values) { call.mutation = { kind: 'update', values }; return query },
          delete() { call.mutation = { kind: 'delete' }; return query },
          then(resolve) { resolve({ error: errors[resource] ?? null }); return Promise.resolve() },
          async returns() {
            const data = resource === 'mesa' ? tables : resource === 'pedido' ? orders : details
            return { data, error: errors[resource] ?? null }
          },
        }
        return query
      },
      async rpc(name, args) {
        rpcCalls.push({ name, args })
        return { data: rpcData, error: rpcError }
      },
    },
  }
}

test('consulta mesas activas, pedidos vigentes y detalles con filtros de servidor', async () => {
  const fixture = createClient({ tables: [table()] })
  const result = await createWaiterOrderService(fixture.client).getTableBoard(context())
  assert.equal(result.ok, true)
  assert.deepEqual(fixture.calls.map((call) => call.resource), ['mesa', 'pedido'])
  assert.deepEqual(fixture.calls[0].filters, [
    { column: 'local_id', value: 'local-own' }, { column: 'activo', value: true },
  ])
  assert.equal(fixture.calls[1].inFilters[0].column, 'estado')
  assert.deepEqual(fixture.calls[1].inFilters[0].values, [
    'ABIERTO', 'ENVIADO', 'RECIBIDO_COCINA', 'EN_PREPARACION', 'LISTO', 'ENTREGADO',
  ])
})

test('asocia un único pedido vigente por mesa y calcula total desde detalles persistidos', async () => {
  const fixture = createClient({
    tables: [table()],
    orders: [{ id: 21, mesa_id: 'table-1', estado: 'ENVIADO' }],
    details: [
      { pedido_id: 21, cantidad: 2, precio_unitario: 12.5 },
      { pedido_id: 21, cantidad: 1, precio_unitario: 5 },
    ],
  })
  const result = await createWaiterOrderService(fixture.client).getTableBoard(context())
  assert.equal(result.ok, true)
  assert.deepEqual(result.data[0].pedido, { id: 21, estado: 'ENVIADO', total: 30 })
  assert.equal(fixture.calls[2].resource, 'detalle_pedido')
  assert.equal(fixture.calls[2].columns, 'pedido_id,cantidad,precio_unitario')
})

test('no consulta detalles ni inventa total cuando no existen pedidos vigentes', async () => {
  const fixture = createClient({ tables: [table()] })
  const result = await createWaiterOrderService(fixture.client).getTableBoard(context())
  assert.equal(result.ok, true)
  assert.equal(result.data[0].pedido, null)
  assert.equal(fixture.calls.length, 2)
})

test('excluye defensivamente mesas inactivas', async () => {
  const fixture = createClient({ tables: [table(), table({ id: 'hidden', activo: false })] })
  const result = await createWaiterOrderService(fixture.client).getTableBoard(context())
  assert.deepEqual(result.ok && result.data.map((item) => item.id), ['table-1'])
})

test('filtra todas las opciones de estado sin búsqueda adicional', () => {
  const statuses = ['LIBRE', 'OCUPADA', 'PEDIDO_LISTO', 'PENDIENTE_PAGO']
  const rows = statuses.map((estado, index) => ({ ...table({ id: `t-${index}`, estado }), pedido: null }))
  assert.equal(filterAndSortWaiterTables(rows, 'TODAS', 'ASC').length, 4)
  for (const estado of statuses) {
    assert.deepEqual(filterAndSortWaiterTables(rows, estado, 'ASC').map((item) => item.estado), [estado])
  }
  for (const label of ['Todas', 'Libres', 'Ocupadas', 'Pedido listo', 'Pendiente de pago']) {
    assert.match(pageSource, new RegExp(label))
  }
  assert.doesNotMatch(pageSource, /type="search"|Buscar mesa|pagin/i)
})

test('ordena códigos numéricos de forma ascendente y descendente', () => {
  const rows = [
    { ...table({ id: '10', codigo: 'M-10' }), pedido: null },
    { ...table({ id: '2', codigo: 'M-2' }), pedido: null },
    { ...table({ id: '1', codigo: 'M-1' }), pedido: null },
  ]
  assert.deepEqual(filterAndSortWaiterTables(rows, 'TODAS', 'ASC').map((item) => item.id), ['1', '2', '10'])
  assert.deepEqual(filterAndSortWaiterTables(rows, 'TODAS', 'DESC').map((item) => item.id), ['10', '2', '1'])
})

test('Tomar pedido usa la RPC permanente sin enviar identidad ni local', async () => {
  const fixture = createClient()
  const result = await createWaiterOrderService(fixture.client).createOrRecoverOrder(context(), 'table-1')
  assert.deepEqual(result, { ok: true, data: { pedidoId: 12, fueCreado: true } })
  assert.deepEqual(fixture.rpcCalls, [{
    name: 'crear_o_recuperar_pedido_mesa', args: { p_mesa_id: 'table-1' },
  }])
})

test('rechaza roles distintos de MOZO antes de consultar Supabase', async () => {
  for (const role of ['ADMINISTRADOR', 'COCINA', 'CAJA']) {
    const fixture = createClient()
    const board = await createWaiterOrderService(fixture.client).getTableBoard(context(role))
    const order = await createWaiterOrderService(fixture.client).createOrRecoverOrder(context(role), 'table-1')
    assert.equal(board.ok, false)
    assert.equal(order.ok, false)
    assert.deepEqual(fixture.calls, [])
    assert.deepEqual(fixture.rpcCalls, [])
  }
})

test('traduce errores de tablero y RPC a mensajes recuperables seguros', async () => {
  const board = await createWaiterOrderService(createClient({ errors: { mesa: { message: 'SQL secret' } } }).client).getTableBoard(context())
  const order = await createWaiterOrderService(createClient({ rpcError: { message: 'SQL secret' }, rpcData: null }).client).createOrRecoverOrder(context(), 'table-1')
  assert.equal(board.ok, false)
  assert.equal(order.ok, false)
  assert.doesNotMatch(board.error.message, /SQL|secret/)
  assert.doesNotMatch(order.error.message, /SQL|secret/)
})

test('cards muestran código, estado textual, total y acción táctil', () => {
  assert.match(pageSource, /\{table\.codigo\}/)
  assert.match(pageSource, /Estado: <strong>\{status\.label\}<\/strong>/)
  assert.match(pageSource, /Total vigente/)
  assert.match(pageSource, /moneyFormatter\.format\(table\.pedido\.total\)/)
  assert.match(pageSource, /Tomar pedido/)
  assert.match(pageSource, /Ver pedido/)
  assert.match(pageSource, /min-h-12 w-full/)
})

test('bloquea repetición visual mientras abre una mesa y conserva PostgreSQL como autoridad', () => {
  assert.match(pageSource, /if \(openingTableId\) return/)
  assert.match(pageSource, /disabled=\{Boolean\(openingTableId\) \|\| unavailable\}/)
  assert.match(pageSource, /Abriendo pedido…/)
  assert.match(serviceSource, /crear_o_recuperar_pedido_mesa/)
})

test('mantiene carga, vacío, filtro vacío y error recuperable', () => {
  for (const text of ['Cargando mesas…', 'No hay mesas disponibles', 'No hay mesas para este filtro', 'Reintentar mesas']) {
    assert.match(pageSource, new RegExp(text))
  }
  assert.match(pageSource, /role="alert"/)
})

test('navega a una ruta mínima de pedido y restringe acceso al MOZO', () => {
  assert.equal(getWaiterOrderId('/mozo/pedidos/42'), 42)
  assert.equal(getWaiterOrderId('/mozo/pedidos/no-valido'), null)
  assert.deepEqual(resolveApplicationRoute({
    pathname: '/mozo/pedidos/42', authenticationStatus: 'authenticated', contextStatus: 'valid', role: 'MOZO',
  }), { status: 'allowed', pathname: '/mozo/pedidos/42' })
  assert.deepEqual(resolveApplicationRoute({
    pathname: '/mozo/pedidos/42', authenticationStatus: 'authenticated', contextStatus: 'valid', role: 'CAJA',
  }), { status: 'redirect', pathname: '/403' })
  assert.match(appSource, /onOpenOrder=\{\(orderId\) => navigate\(`\/mozo\/pedidos\/\$\{orderId\}`\)\}/)
  assert.match(orderPageSource, /Agregar productos/)
  assert.doesNotMatch(orderPageSource, /enviar_pedido_cocina/)
})

test('T07 agrega exclusivamente mediante RPC sin precio ni estado del cliente', async () => {
  const fixture = createClient({ rpcData: [{ detalle_id: 31, pedido_id: 12, producto_id: 'product-1', cantidad: 1, precio_unitario: 18.5, observacion: null, estado: 'ABIERTO' }] })
  const result = await createWaiterOrderService(fixture.client).addOrderDetail(context(), 12, 'product-1')
  assert.equal(result.ok, true)
  assert.deepEqual(fixture.rpcCalls, [{ name: 'agregar_detalle_pedido', args: { p_pedido_id: 12, p_producto_id: 'product-1', p_cantidad: 1, p_observacion: null } }])
  assert.equal('precio_unitario' in fixture.rpcCalls[0].args, false)
  assert.equal('estado' in fixture.rpcCalls[0].args, false)
  assert.equal(result.data.precio_unitario, 18.5)
  assert.equal(result.data.estado, 'ABIERTO')
})

test('T07 limita cambios directos a cantidad/observación y retiro de ABIERTO', async () => {
  const fixture = createClient()
  const service = createWaiterOrderService(fixture.client)
  assert.equal((await service.updateOpenDetail(context(), 31, { cantidad: 2 })).ok, true)
  assert.deepEqual(fixture.calls[0].mutation, { kind: 'update', values: { cantidad: 2 } })
  assert.deepEqual(fixture.calls[0].filters, [{ column: 'id', value: 31 }, { column: 'estado', value: 'ABIERTO' }])
  assert.equal((await service.removeOpenDetail(context(), 31)).ok, true)
  assert.deepEqual(fixture.calls[1].mutation, { kind: 'delete' })
  assert.deepEqual(fixture.calls[1].filters[1], { column: 'estado', value: 'ABIERTO' })
  assert.equal((await service.updateOpenDetail(context(), 31, { cantidad: 0 })).ok, false)
})

test('T07 ofrece catálogo filtrable, observaciones frecuentes/libres y controles táctiles', () => {
  for (const text of ['Sin cebolla', 'Sin ají', 'Poco picante', 'Sin cancha', 'Otra…', 'Editar observación', 'Retirar']) assert.match(orderPageSource, new RegExp(text))
  assert.equal(combineOrderObservation(['Sin cebolla', 'Poco picante'], 'Mesa comparte plato'), 'Sin cebolla, Poco picante, Mesa comparte plato')
  assert.equal(combineOrderObservation([], '  '), null)
  assert.match(orderPageSource, /detail\.observacion\?\.split\(','\)/)
  assert.match(orderPageSource, /detail\.estado === 'ABIERTO'/)
  assert.match(orderPageSource, /ya fue enviado y no se puede editar ni retirar/)
  assert.match(orderPageSource, /min-h-11|min-h-12/)
  assert.match(orderPageSource, /overflow-x-hidden/)
  assert.match(orderPageSource, /sm:grid-cols-2/)
})

test('T07 conserva estado persistido cuando PostgreSQL rechaza una mutación', async () => {
  const fixture = createClient({ errors: { detalle_pedido: { code: '42501' } } })
  const service = createWaiterOrderService(fixture.client)
  const update = await service.updateOpenDetail(context(), 31, { observacion: 'Sin ají' })
  const removal = await service.removeOpenDetail(context(), 31)
  assert.equal(update.ok, false)
  assert.equal(removal.ok, false)
  assert.match(update.error.message, /datos anteriores se mantienen/)
})

test('T07 confirma retiro, permite cancelar y muestra feedback local', () => {
  assert.match(orderPageSource, /¿Retirar \{productName\}/)
  assert.match(orderPageSource, /setConfirmingRemoval\(detail\.id\)/)
  assert.match(orderPageSource, /setConfirmingRemoval\(null\)/)
  assert.match(orderPageSource, /⏳ Retirando…/)
  assert.match(orderPageSource, /aria-busy=\{detailBusy\}/)
})

test('T07 impide doble mutación por línea y no usa menos uno para eliminar', () => {
  assert.match(orderPageSource, /pendingDetailIds\.current\.has\(detail\.id\)/)
  assert.match(orderPageSource, /pendingDetailIds\.current\.add\(detail\.id\)/)
  assert.match(orderPageSource, /pendingDetailIds\.current\.delete\(detail\.id\)/)
  assert.match(orderPageSource, /detail\.cantidad <= 1/)
  assert.match(orderPageSource, /value < 1\) return/)
  assert.doesNotMatch(orderPageSource, /quantity\([^)]*remove|detail\.cantidad === 1[^\n]*remove/)
})

test('T07 muestra actualización local y rehabilita controles tras respuesta', () => {
  assert.match(orderPageSource, /Actualizando…/)
  assert.match(orderPageSource, /disabled=\{detailBusy\}/)
  assert.match(orderPageSource, /setBusyDetails\(\(ids\) => ids\.filter/)
  assert.match(orderPageSource, /if \(!result\.ok\) \{ await reload\(\); setError/)
})

test('T07 recarga persistencia tras cada mutación y no muestra éxito optimista', () => {
  assert.match(orderPageSource, /else await reload\(\)/)
  assert.match(orderPageSource, /else if \(await reload\(\)\)/)
  assert.match(orderPageSource, /if \(!result\.ok\) setError\(result\.error\.message\)/)
  assert.doesNotMatch(orderPageSource, /setDetails\(\[\.\.\.details|filter\(\(detail\) => detail\.id/)
})

test('T07 abre carta para pedido vacío y resumen para pedido con detalles', () => {
  assert.match(orderPageSource, /setMode\(detailResult\.data\.length > 0 \? 'ORDER' : 'CATALOG'\)/)
  assert.match(orderPageSource, /mode === 'CATALOG' && <section/)
  assert.match(orderPageSource, /mode === 'ORDER' && <section/)
  assert.match(orderPageSource, /Pedido actual/)
  assert.match(orderPageSource, /\+ Agregar productos/)
})

test('T07 alterna Pedido y Carta sin ruta adicional ni salida automática tras agregar', () => {
  assert.match(orderPageSource, /onClick=\{\(\) => setMode\('CATALOG'\)\}/)
  assert.match(orderPageSource, /Volver al pedido/)
  assert.match(orderPageSource, /onClick=\{\(\) => setMode\('ORDER'\)\}/)
  const addFunction = orderPageSource.slice(orderPageSource.indexOf('async function add('), orderPageSource.indexOf('async function quantity('))
  assert.doesNotMatch(addFunction, /setMode/)
  assert.match(orderPageSource, /\{details\.length\} líneas · Total/)
})

test('T07 separa ya solicitado de por enviar y conserva edición solo para ABIERTO', () => {
  assert.match(orderPageSource, /requestedDetails = details\.filter\(\(detail\) => detail\.estado !== 'ABIERTO'\)/)
  assert.match(orderPageSource, /openDetails = details\.filter\(\(detail\) => detail\.estado === 'ABIERTO'\)/)
  assert.match(orderPageSource, /Ya solicitado/)
  assert.match(orderPageSource, /Por enviar/)
  assert.match(orderPageSource, /\{open \? <>/)
  assert.match(orderPageSource, /detail\.observacion/)
})

test('T07 consolida atómicamente solo producto y observación equivalentes en ABIERTO', () => {
  assert.match(consolidationMigration, /pg_advisory_xact_lock/)
  assert.match(consolidationMigration, /detail_row\.producto_id = p_producto_id/)
  assert.match(consolidationMigration, /detail_row\.estado = 'ABIERTO'/)
  assert.match(consolidationMigration, /is not distinct from/)
  assert.match(consolidationMigration, /set cantidad = detail_row\.cantidad \+ p_cantidad/)
  assert.match(consolidationMigration, /insert into public\.detalle_pedido/)
  assert.doesNotMatch(consolidationMigration, /p_precio|p_estado/)
})

test('T07 bloquea taps repetidos de agregar antes del siguiente render', () => {
  assert.match(orderPageSource, /pendingProductIds\.current\.has\(productId\)/)
  assert.match(orderPageSource, /pendingProductIds\.current\.add\(productId\)/)
  assert.match(orderPageSource, /pendingProductIds\.current\.delete\(productId\)/)
})

test('T07 usa card compacta ABIERTO y cantidad de solo lectura para enviados', () => {
  assert.match(orderPageSource, /aria-label=\{`Retirar \$\{productName\}`\}/)
  assert.match(orderPageSource, /className="h-5 w-5"/)
  assert.match(orderPageSource, /className="grid h-11 w-11/)
  assert.match(orderPageSource, /<svg aria-hidden="true"/)
  assert.doesNotMatch(orderPageSource, /🗑/)
  assert.match(orderPageSource, /!open && ` · Estado:/)
  assert.match(orderPageSource, /: <strong className="shrink-0">× \{detail\.cantidad\}<\/strong>/)
  assert.match(orderPageSource, /detail\.cantidad <= 1/)
})
