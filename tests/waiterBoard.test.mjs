import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import test from 'node:test'
import { getWaiterOrderId, resolveApplicationRoute } from '../src/services/appRoutes.ts'
import { combineOrderObservation, createWaiterOrderService, filterAndSortWaiterTables } from '../src/services/waiterOrderService.ts'

const pageSource = readFileSync(new URL('../src/pages/WaiterTablesPage.tsx', import.meta.url), 'utf8')
const orderPageSource = readFileSync(new URL('../src/pages/WaiterOrderPage.tsx', import.meta.url), 'utf8')
const appSource = readFileSync(new URL('../src/App.tsx', import.meta.url), 'utf8')
const serviceSource = readFileSync(new URL('../src/services/waiterOrderService.ts', import.meta.url), 'utf8')
const modelMigration = readFileSync(new URL('../supabase/migrations/20260826000100_h3_t01_order_detail_state.sql', import.meta.url), 'utf8')
const orderMigration = readFileSync(new URL('../supabase/migrations/20260826000200_h3_t02_open_or_recover_order.sql', import.meta.url), 'utf8')
const sendMigration = readFileSync(new URL('../supabase/migrations/20260826000700_send_order_to_kitchen.sql', import.meta.url), 'utf8')
const consolidationMigration = readFileSync(new URL('../supabase/migrations/20260826000800_consolidate_open_order_details.sql', import.meta.url), 'utf8')
const releaseMigration = readFileSync(new URL('../supabase/migrations/20260827000100_release_empty_order_table.sql', import.meta.url), 'utf8')
const auditMigration = readFileSync(new URL('../supabase/migrations/20260827000200_order_audit_trail.sql', import.meta.url), 'utf8')
const creatorLookupFixMigration = readFileSync(new URL('../supabase/migrations/20260827000300_fix_order_creator_lookup.sql', import.meta.url), 'utf8')
const reopenDeliveredMigration = readFileSync(new URL('../supabase/migrations/20260830000200_h5_reopen_delivered_order.sql', import.meta.url), 'utf8')

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

function createClient({ tables = [], orders = [], details = [], mutationRows = [{ id: 31 }], errors = {}, rpcData = [{ pedido_id: 12, fue_creado: true }], creatorData = [], rpcError = null } = {}) {
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
          is(column, value) { call.filters.push({ column, value }); return query },
          in(column, values) { call.inFilters.push({ column, values }); return query },
          update(values) { call.mutation = { kind: 'update', values }; return query },
          delete() { call.mutation = { kind: 'delete' }; return query },
          then(resolve) { resolve({ error: errors[resource] ?? null }); return Promise.resolve() },
          async returns() {
            const data = call.mutation ? mutationRows : resource === 'mesa' ? tables : resource === 'pedido' ? orders : details
            return { data, error: errors[resource] ?? null }
          },
        }
        return query
      },
      async rpc(name, args) {
        rpcCalls.push({ name, args })
        return { data: name === 'obtener_creadores_pedidos_vigentes' ? creatorData : rpcData, error: rpcError }
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
    orders: [{ id: 21, mesa_id: 'table-1', estado: 'ENVIADO', creado_por: 'waiter-one' }],
    creatorData: [{ pedido_id: 21, creador_nombre: 'Ana Mozo' }],
    details: [
      { pedido_id: 21, cantidad: 2, precio_unitario: 12.5 },
      { pedido_id: 21, cantidad: 1, precio_unitario: 5 },
    ],
  })
  const result = await createWaiterOrderService(fixture.client).getTableBoard(context())
  assert.equal(result.ok, true)
  assert.deepEqual(result.data[0].pedido, { id: 21, estado: 'ENVIADO', total: 30, creadorNombre: 'Ana Mozo' })
  assert.equal(fixture.calls[2].resource, 'detalle_pedido')
  assert.equal(fixture.calls[2].columns, 'pedido_id,cantidad,precio_unitario')
  assert.deepEqual(fixture.rpcCalls, [{ name: 'obtener_creadores_pedidos_vigentes', args: { p_pedido_ids: [21] } }])
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
  assert.match(pageSource, /if \(openingTableRef\.current\) return/)
  assert.match(pageSource, /finally \{\s*openingTableRef\.current = null/)
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

test('T09 detecta actualización obsoleta y compara el valor confirmado anterior', async () => {
  const fixture = createClient({ mutationRows: [] })
  const service = createWaiterOrderService(fixture.client)
  const quantity = await service.updateOpenDetail(context(), 31, { cantidad: 3 }, { cantidad: 2 })
  const observation = await service.updateOpenDetail(context(), 32, { observacion: 'Sin ají' }, { observacion: null })
  const removal = await service.removeOpenDetail(context(), 33)
  assert.equal(quantity.ok, false)
  assert.equal(observation.ok, false)
  assert.equal(removal.ok, false)
  assert.equal(quantity.error.kind, 'concurrent-conflict')
  assert.equal(observation.error.kind, 'concurrent-conflict')
  assert.equal(removal.error.kind, 'concurrent-conflict')
  assert.match(quantity.error.message, /otro dispositivo/)
  assert.deepEqual(fixture.calls[0].filters, [
    { column: 'id', value: 31 }, { column: 'estado', value: 'ABIERTO' }, { column: 'cantidad', value: 2 },
  ])
  assert.deepEqual(fixture.calls[1].filters, [
    { column: 'id', value: 32 }, { column: 'estado', value: 'ABIERTO' }, { column: 'observacion', value: null },
  ])
})

test('T09 observaciones concurrentes conservan al ganador y la sesión perdedora recupera servidor', async () => {
  const winner = createClient({ mutationRows: [{ id: 31 }] })
  const confirmed = [{
    id: 31, pedido_id: 12, producto_id: 'p-1', cantidad: 1, precio_unitario: 18.5,
    observacion: 'Sin cebolla', estado: 'ABIERTO',
  }]
  const loser = createClient({ mutationRows: [], details: confirmed })
  const winnerService = createWaiterOrderService(winner.client)
  const loserService = createWaiterOrderService(loser.client)

  const persisted = await winnerService.updateOpenDetail(context(), 31, { observacion: 'Sin cebolla' }, { observacion: null })
  const rejected = await loserService.updateOpenDetail(context(), 31, { observacion: 'Poco picante' }, { observacion: null })
  const recovered = await loserService.getOrderDetails(context(), 12)

  assert.equal(persisted.ok, true)
  assert.equal(rejected.ok, false)
  assert.equal(rejected.error.kind, 'concurrent-conflict')
  assert.equal(recovered.ok, true)
  assert.equal(recovered.data[0].observacion, 'Sin cebolla')
  assert.doesNotMatch(recovered.data[0].observacion, /Poco picante/)
})

test('T09 conflicto descarta borrador, cierra Guardar y permite editar de nuevo', () => {
  assert.match(orderPageSource, /const refreshed = await reload\(\)/)
  assert.match(orderPageSource, /mutationError\.kind === 'concurrent-conflict'\) resetDetailDraft\(detailId\)/)
  assert.match(orderPageSource, /resetDetailDraft\(detailId\)/)
  assert.match(orderPageSource, /setEditing\(null\)/)
  assert.match(orderPageSource, /setSelected\(\[\]\)/)
  assert.match(orderPageSource, /setFree\(''\)/)
  assert.match(orderPageSource, /setConfirmingRemoval\(null\)/)
  assert.match(serviceSource, /Este producto fue actualizado desde otro dispositivo\. Se cargó la versión más reciente\./)
  assert.match(orderPageSource, /onClick=\{\(\) => editObservation\(detail\)\}/)
  assert.match(orderPageSource, /Editar observación/)
})

test('T09 conflicto se asocia solo a la card afectada y desaparece al volver a editar', () => {
  assert.match(orderPageSource, /Readonly<Record<number, string>>/)
  assert.match(orderPageSource, /\{ \.\.\.current, \[detailId\]: 'Actualizado desde otro dispositivo\. Se cargó la versión más reciente\.' \}/)
  assert.match(orderPageSource, /const detailConflict = detailConflicts\[detail\.id\]/)
  assert.match(orderPageSource, /\{detailConflict && <p[^>]*role="status">\{detailConflict\}<\/p>\}/)
  assert.match(orderPageSource, /function clearDetailConflict\(detailId: number\)/)
  assert.match(orderPageSource, /function editObservation[\s\S]*?clearDetailConflict\(detail\.id\); setError\(null\)/)
  assert.match(orderPageSource, /async function quantity[\s\S]*?clearDetailConflict\(detail\.id\)/)
  assert.match(orderPageSource, /async function remove[\s\S]*?clearDetailConflict\(detail\.id\)/)
  assert.match(orderPageSource, /\{error && <div[^>]*role="alert"[\s\S]*?>Reintentar<\/button>/)
  assert.doesNotMatch(orderPageSource, /setError\(mutationError\.message\)[\s\S]{0,80}concurrent-conflict/)
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
  assert.match(orderPageSource, /aria-busy=\{detailBusy \|\| sending\}/)
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
  assert.match(orderPageSource, /const refreshed = await reload\(\)/)
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
  assert.match(addFunction, /setMode\('ORDER'\)/)
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

test('T08 recupera mesa y cabecera vigente para la revisión', async () => {
  const fixture = createClient({
    tables: [{ id: 'table-1', codigo: 'M-01', nombre: 'Terraza', estado: 'PEDIDO_LISTO' }],
    orders: [{ id: 12, mesa_id: 'table-1', estado: 'EN_PREPARACION' }],
  })
  const result = await createWaiterOrderService(fixture.client).getOrderReview(context(), 12)
  assert.deepEqual(result, { ok: true, data: { id: 12, estado: 'EN_PREPARACION', mesa: { id: 'table-1', codigo: 'M-01', nombre: 'Terraza', estado: 'PEDIDO_LISTO' } } })
})

test('H5-TA18 alta posterior a ENTREGADO resincroniza el snapshot autoritativo', () => {
  const addFunction = orderPageSource.slice(orderPageSource.indexOf('async function add('), orderPageSource.indexOf('async function quantity('))
  assert.match(addFunction, /await reloadOrderSnapshot\(\)/)
  assert.match(addFunction, /setMode\('ORDER'\)/)
  assert.match(reopenDeliveredMigration, /p\.estado in \('ABIERTO','ENVIADO','RECIBIDO_COCINA','EN_PREPARACION','LISTO','ENTREGADO'\)/)
  assert.match(reopenDeliveredMigration, /values\(p_pedido_id,p_producto_id,p_cantidad,v_precio,p_observacion,'ABIERTO'\)/)
  assert.match(reopenDeliveredMigration, /perform public\.sincronizar_estado_operativo_pedido\(p_pedido_id,v_usuario_id\)/)
  assert.match(reopenDeliveredMigration, /v_pedido\.estado = 'ENTREGADO' and v_estado_derivado = 'LISTO'/)
  assert.match(reopenDeliveredMigration, /v_pedido\.estado in \('PAGADO', 'ANULADO'\)/)
})

test('H5-TH01 entrega exclusivamente mediante entregar_pedido y conserva autoridad PostgreSQL', async () => {
  const fixture = createClient({
    rpcData: [{ pedido_id: 12, pedido_estado: 'ENTREGADO', mesa_id: 'table-1', mesa_estado: 'PENDIENTE_PAGO' }],
  })
  const result = await createWaiterOrderService(fixture.client).deliverOrder(context(), 12)
  assert.deepEqual(result, { ok: true, data: { mesaId: 'table-1' } })
  assert.deepEqual(fixture.rpcCalls, [{ name: 'entregar_pedido', args: { p_pedido_id: 12 } }])
  assert.doesNotMatch(serviceSource, /deliverOrder[\s\S]*?from\('detalle_pedido'\)\.update/)
})

test('H5-TH01 entrega rechaza rol ajeno y traduce conflicto sin falso éxito', async () => {
  const unauthorized = createClient()
  const denied = await createWaiterOrderService(unauthorized.client).deliverOrder(context('CAJA'), 12)
  assert.equal(denied.ok, false)
  assert.equal(unauthorized.rpcCalls.length, 0)

  const conflictFixture = createClient({ rpcData: null, rpcError: { code: '40001' } })
  const conflict = await createWaiterOrderService(conflictFixture.client).deliverOrder(context(), 12)
  assert.equal(conflict.ok, false)
  assert.equal(conflict.error.kind, 'concurrent-conflict')
  assert.match(conflict.error.message, /ya fue procesado/)

  const unconfirmed = createClient({ rpcData: [] })
  const failed = await createWaiterOrderService(unconfirmed.client).deliverOrder(context(), 12)
  assert.equal(failed.ok, false)
  assert.match(failed.error.message, /No pudimos confirmar la entrega/)
})

test('H5-TH01 UI muestra, confirma y resincroniza la entrega solo cuando todo está LISTO', () => {
  assert.match(orderPageSource, /review\?\.estado === 'LISTO' && details\.length > 0/)
  assert.match(orderPageSource, /details\.every\(\(detail\) => detail\.estado === 'LISTO'\)/)
  assert.match(orderPageSource, />Entregar pedido<\/button>/)
  assert.match(orderPageSource, /¿Entregar el pedido #\{orderId\}/)
  assert.match(orderPageSource, /Confirmar entrega/)
  assert.match(orderPageSource, /deliveringRef\.current/)
  assert.match(orderPageSource, /Entregando…/)
  assert.match(orderPageSource, /const result = await orders\.deliverOrder\(context, orderId\)/)
  assert.match(orderPageSource, /await reloadOrderSnapshot\(\)/)
  assert.match(orderPageSource, /review\.estado.*review\.mesa\.estado/)
  assert.match(orderPageSource, /Pedido entregado\. La mesa está pendiente de pago\./)
})

test('T08 envía exclusivamente mediante enviar_pedido_cocina', async () => {
  const fixture = createClient({ rpcData: [{ pedido_id: 12, detalles_enviados: 3, cabecera_actualizada: true, pedido_estado: 'ENVIADO' }] })
  const result = await createWaiterOrderService(fixture.client).sendOrderToKitchen(context(), 12)
  assert.deepEqual(result, { ok: true, data: { detallesEnviados: 3 } })
  assert.deepEqual(fixture.rpcCalls, [{ name: 'enviar_pedido_cocina', args: { p_pedido_id: 12 } }])
  assert.doesNotMatch(serviceSource, /update\(\{\s*estado:/)
})

test('T08 revisión muestra mesa, pedido, grupos, importes y total persistido', () => {
  assert.match(orderPageSource, /review\.mesa\.codigo/)
  assert.match(orderPageSource, /Pedido #\{orderId\}/)
  assert.match(orderPageSource, /Ya solicitado/)
  assert.match(orderPageSource, /Por enviar/)
  assert.match(orderPageSource, /detailAmount = detail\.cantidad \* Number\(detail\.precio_unitario\)/)
  assert.match(orderPageSource, /total = details\.reduce/)
  assert.match(orderPageSource, /Total \{money\.format\(total\)\}/)
})

test('T08 muestra envío solo con ABIERTO, feedback y bloqueo contra doble tap', () => {
  assert.match(orderPageSource, /openDetails\.length > 0 && <button/)
  assert.match(orderPageSource, /Enviar a cocina/)
  assert.match(orderPageSource, /Enviando…/)
  assert.match(orderPageSource, /sendingRef\.current/)
  assert.match(orderPageSource, /if \(!orders \|\| sendingRef\.current \|\| openDetails\.length === 0\) return/)
  assert.match(orderPageSource, /disabled=\{sending\}/)
})

test('T08 recarga PostgreSQL tras éxito o error y deriva los grupos del estado confirmado', () => {
  assert.match(orderPageSource, /const result = await orders\.sendOrderToKitchen/)
  assert.match(orderPageSource, /const refreshed = await reload\(\)/)
  assert.match(orderPageSource, /if \(!result\.ok\) setError/)
  assert.match(orderPageSource, /requestedDetails = details\.filter/)
  assert.match(orderPageSource, /openDetails = details\.filter/)
  assert.doesNotMatch(orderPageSource, /setDetails\([^\n]*estado/)
})

test('T08 conserva agregados posteriores en Por enviar hasta un nuevo envío', () => {
  assert.match(orderPageSource, /setMode\('CATALOG'\)/)
  assert.match(orderPageSource, /addOrderDetail/)
  assert.match(orderPageSource, /else await reload\(\)/)
  assert.match(orderPageSource, /detail\.estado === 'ABIERTO'/)
  assert.match(serviceSource, /enviar_pedido_cocina/)
})

test('T09 reconstruye pedido y mezcla desde PostgreSQL sin carrito efímero', async () => {
  const details = [
    { id: 31, pedido_id: 12, producto_id: 'p-1', cantidad: 2, precio_unitario: 18.5, observacion: 'Sin cebolla', estado: 'ENVIADO', producto: { nombre: 'Ceviche' } },
    { id: 32, pedido_id: 12, producto_id: 'p-2', cantidad: 1, precio_unitario: 9, observacion: null, estado: 'ABIERTO', producto: { nombre: 'Chicha' } },
  ]
  const fixture = createClient({ details })
  const result = await createWaiterOrderService(fixture.client).getOrderDetails(context(), 12)
  assert.equal(result.ok, true)
  assert.deepEqual(result.data, details)
  assert.deepEqual(fixture.calls[0].filters, [{ column: 'pedido_id', value: 12 }])
  assert.match(orderPageSource, /void load\(\)/)
  assert.match(orderPageSource, /getOrderReview\(context, orderId\)/)
  assert.match(orderPageSource, /getOrderDetails\(context, orderId\)/)
  assert.doesNotMatch(orderPageSource, /localStorage|sessionStorage|cart|carrito/i)
})

test('T09 errores de alta y envío no producen éxito local y permiten recargar', async () => {
  const addFixture = createClient({ rpcData: null, rpcError: { message: 'network' } })
  const sendFixture = createClient({ rpcData: null, rpcError: { message: 'network' } })
  const add = await createWaiterOrderService(addFixture.client).addOrderDetail(context(), 12, 'p-1')
  const send = await createWaiterOrderService(sendFixture.client).sendOrderToKitchen(context(), 12)
  assert.equal(add.ok, false)
  assert.equal(send.ok, false)
  assert.match(orderPageSource, /await reloadOrderSnapshot\(\)\s*if \(!result\.ok\) setError\(result\.error\.message\)/)
  assert.match(orderPageSource, /const refreshed = await reload\(\)/)
  assert.match(orderPageSource, /Reintentar/)
})

test('T09 libera siempre guards locales y delega concurrencia crítica a PostgreSQL', () => {
  assert.match(orderPageSource, /finally \{\s*pendingProductIds\.current\.delete/)
  assert.match(orderPageSource, /finally \{\s*pendingDetailIds\.current\.delete/g)
  assert.match(orderPageSource, /finally \{\s*sendingRef\.current = false/)
  assert.match(pageSource, /finally \{\s*openingTableRef\.current = null/)
  assert.match(orderMigration, /for update/)
  assert.match(modelMigration, /create unique index/)
  assert.match(modelMigration, /mesa_id/)
  assert.match(consolidationMigration, /pg_advisory_xact_lock/)
  assert.match(sendMigration, /for update/)
  assert.match(sendMigration, /estado = 'ABIERTO'/)
  assert.match(sendMigration, /estado = 'ENVIADO'/)
})

test('H3-TA16 libera el pedido vacío exclusivamente mediante la operación de dominio', async () => {
  const fixture = createClient({
    rpcData: [{ pedido_id: 12, mesa_id: 'table-1', pedido_estado: 'ANULADO', mesa_estado: 'LIBRE' }],
  })
  const result = await createWaiterOrderService(fixture.client).releaseEmptyOrderTable(context(), 12)
  assert.deepEqual(result, { ok: true, data: { mesaId: 'table-1' } })
  assert.deepEqual(fixture.rpcCalls, [{ name: 'liberar_mesa_pedido_vacio', args: { p_pedido_id: 12 } }])
  assert.doesNotMatch(serviceSource, /from\('pedido'\)\.update|from\('mesa'\)\.update/)
})

test('H3-TA16 rechaza cliente no MOZO y conserva error recuperable del servidor', async () => {
  const unauthorized = createClient()
  const denied = await createWaiterOrderService(unauthorized.client).releaseEmptyOrderTable(context('CAJA'), 12)
  assert.equal(denied.ok, false)
  assert.equal(unauthorized.rpcCalls.length, 0)

  const failed = createClient({ rpcData: null, rpcError: { message: 'pedido con detalles' } })
  const result = await createWaiterOrderService(failed.client).releaseEmptyOrderTable(context(), 12)
  assert.equal(result.ok, false)
  assert.match(result.error.message, /pedido siga vacío/)
})

test('H3-TA16 operación PostgreSQL es atómica, autorizada y no elimina pedidos', () => {
  assert.match(releaseMigration, /create or replace function public\.liberar_mesa_pedido_vacio/)
  assert.match(releaseMigration, /security definer/)
  assert.match(releaseMigration, /set search_path = pg_catalog/)
  assert.match(releaseMigration, /from public\.obtener_contexto_autenticado/)
  assert.match(releaseMigration, /v_rol_codigo is distinct from 'MOZO'/)
  assert.match(releaseMigration, /for update/g)
  assert.match(releaseMigration, /from public\.detalle_pedido/)
  assert.match(releaseMigration, /set estado = 'ANULADO'/)
  assert.match(releaseMigration, /set estado = 'LIBRE'/)
  assert.match(releaseMigration, /insert into public\.historial_estado/)
  assert.doesNotMatch(releaseMigration, /delete from public\.pedido/)
  assert.match(releaseMigration, /revoke all on function public\.liberar_mesa_pedido_vacio\(bigint\) from public/)
  assert.match(releaseMigration, /grant execute on function public\.liberar_mesa_pedido_vacio\(bigint\) to authenticated/)
})

test('H3-TA16 UI confirma, bloquea doble tap y navega solo tras éxito', () => {
  assert.match(orderPageSource, /review\?\.estado === 'ABIERTO' && details\.length === 0/)
  assert.match(orderPageSource, /¿Liberar \{review\.mesa\.codigo\}\? El pedido vacío será anulado/)
  assert.match(orderPageSource, /releasingRef\.current/)
  assert.match(orderPageSource, /if \(!orders \|\| releasingRef\.current/)
  assert.match(orderPageSource, /Liberando…/)
  assert.match(orderPageSource, /if \(result\.ok\) \{ onBack\(\); return \}/)
  assert.match(orderPageSource, /setConfirmingRelease\(false\)/)
  assert.match(orderPageSource, /getOrderDetails\(context, orderId\)/)
  assert.match(orderPageSource, /getOrderReview\(context, orderId\)/)
})

test('evolución H3 registra auditoría segura de pedido y detalles', () => {
  for (const column of ['modificado_por', 'modificado_en']) {
    assert.match(auditMigration, new RegExp(`add column ${column}`))
  }
  for (const column of ['creado_por', 'creado_en', 'modificado_por', 'modificado_en']) {
    assert.match(auditMigration, new RegExp(`add column ${column}`))
  }
  assert.match(auditMigration, /references public\.perfil_usuario \(id\) on delete restrict/g)
  assert.match(auditMigration, /new\.modificado_por := new\.creado_por/)
  assert.match(auditMigration, /new\.creado_por := v_usuario_id/)
  assert.match(auditMigration, /new\.creado_por := old\.creado_por/)
  assert.match(auditMigration, /set modificado_por = v_usuario_id/)
  assert.match(auditMigration, /new\.estado is distinct from old\.estado/)
  assert.doesNotMatch(auditMigration, /alter table public\.mesa[\s\S]*responsable/i)
})

test('tablero deriva y muestra el creador del pedido vigente sin consultar perfiles directamente', () => {
  assert.match(serviceSource, /obtener_creadores_pedidos_vigentes/)
  assert.match(serviceSource, /creadorNombre/)
  assert.match(pageSource, /Atendido por:/)
  assert.match(pageSource, /table\.pedido\.creadorNombre/)
  assert.doesNotMatch(serviceSource, /from\('perfil_usuario'\)/)
  assert.match(auditMigration, /order_row\.local_id = v_local_id/)
  assert.match(auditMigration, /order_row\.creado_por/)
  assert.match(creatorLookupFixMigration, /any\(coalesce\(p_pedido_ids, array\[\]::bigint\[\]\)\)/)
  assert.doesNotMatch(creatorLookupFixMigration, /pg_catalog\.coalesce/)
})

test('frontend lee auditoría persistida sin enviar UUID de autor en mutaciones', () => {
  assert.match(serviceSource, /creado_por,creado_en,modificado_por,modificado_en/)
  assert.doesNotMatch(serviceSource, /p_(creado|modificado)_por/)
  assert.match(serviceSource, /const changes: \{ cantidad\?: number; observacion\?: string \| null \} = \{\}/)
})
