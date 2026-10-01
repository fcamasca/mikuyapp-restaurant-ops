import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import test from 'node:test'
import { createOperationalDayService } from '../src/services/operationalDayService.ts'
import { resolveApplicationRoute } from '../src/services/appRoutes.ts'

const read = (path) => readFileSync(new URL(path, import.meta.url), 'utf8')
const panel = read('../src/components/OperationalDayAdminPanel.tsx')
const history = read('../src/pages/AdminOperationalDaysPage.tsx')
const home = read('../src/pages/AdminHomePage.tsx')
const shell = read('../src/components/AdminShell.tsx')
const app = read('../src/App.tsx')

const context = (role = 'ADMINISTRADOR') => ({
  profile: { id: 'admin-1', local_id: 'local-1', rol_id: 1, nombre: 'Ana', activo: true },
  role: { id: 1, codigo: role, activo: true },
  local: { id: 'local-1', nombre: 'Cebichería', activo: true },
})

function rpcClient(responses) {
  const calls = []
  return { calls, client: { async rpc(name, args) { calls.push({ name, args }); return responses[name] ?? { data: [], error: null } } } }
}

const resolve = (pathname, role) => resolveApplicationRoute({ pathname, authenticationStatus: 'authenticated', contextStatus: 'valid', role })

// ===== Servicio ADMIN (TP20, parte de servicio)

test('E9-T05 abrir envía sólo la clave de solicitud e informa ya_existia sin tratarlo como error', async () => {
  const fixture = rpcClient({ rpc_abrir_jornada_operativa: { data: [{ jornada_operativa_id: 3, identificacion: 'Jornada 2026-10-01 (1)', estado: 'ABIERTA', ya_existia: true }], error: null } })
  const result = await createOperationalDayService(fixture.client).open(context(), 'key-1')
  assert.deepEqual(fixture.calls, [{ name: 'rpc_abrir_jornada_operativa', args: { p_idempotency_key: 'key-1' } }])
  assert.deepEqual(result, { ok: true, data: { id: 3, identificacion: 'Jornada 2026-10-01 (1)', estado: 'ABIERTA', yaExistia: true } })
})

test('E9-T05 cerrar envía sólo la jornada; ya_estaba_cerrada no es error; PT409 conserva los conteos del servidor', async () => {
  const ok = rpcClient({ rpc_cerrar_jornada_operativa: { data: [{ jornada_operativa_id: 3, identificacion: 'Jornada 2026-10-01 (1)', cerrada_en: '2026-10-02T07:30:00Z', ya_estaba_cerrada: true }], error: null } })
  assert.deepEqual(await createOperationalDayService(ok.client).close(context(), 3),
    { ok: true, data: { id: 3, identificacion: 'Jornada 2026-10-01 (1)', cerradaEn: '2026-10-02T07:30:00Z', yaEstabaCerrada: true } })
  assert.deepEqual(ok.calls, [{ name: 'rpc_cerrar_jornada_operativa', args: { p_jornada_operativa_id: 3 } }])
  const blocked = rpcClient({ rpc_cerrar_jornada_operativa: { data: null, error: { code: 'PT409', message: 'No se puede cerrar la jornada: 1 pedidos pendientes y 1 sesiones de caja abiertas' } } })
  assert.deepEqual(await createOperationalDayService(blocked.client).close(context(), 3),
    { ok: false, error: { kind: 'conflict', message: 'No se puede cerrar la jornada: 1 pedidos pendientes y 1 sesiones de caja abiertas' } })
})

test('E9-T05 pendientes e historial se mapean sin importes y sólo ADMIN llama a las RPC', async () => {
  const fixture = rpcClient({
    rpc_obtener_pendientes_cierre_jornada: { data: [
      { tipo: 'PEDIDO', pedido_id: 9, mesa_codigo: 'M1', estado: 'ENTREGADO', sesion_caja_id: null, caja_codigo: null, abierta_por_nombre: null, desde: '2026-10-01T20:00:00Z' },
      { tipo: 'SESION_CAJA', pedido_id: null, mesa_codigo: null, estado: 'ABIERTA', sesion_caja_id: 's-1', caja_codigo: 'CAJA-01', abierta_por_nombre: 'Caja', desde: '2026-10-01T14:00:00Z' },
    ], error: null },
    rpc_obtener_historial_jornadas_operativas: { data: [
      { jornada_operativa_id: 2, identificacion: 'Jornada 2026-10-01 (2)', estado: 'ABIERTA', abierta_por_nombre: 'Ana', abierta_en: '2026-10-02T02:00:00Z', cerrada_por_nombre: null, cerrada_en: null },
    ], error: null },
  })
  const svc = createOperationalDayService(fixture.client)
  const blockers = await svc.getClosingBlockers(context())
  assert.deepEqual(blockers.data.map((b) => [b.tipo, b.pedidoId, b.mesaCodigo, b.cajaCodigo]), [['PEDIDO', 9, 'M1', null], ['SESION_CAJA', null, null, 'CAJA-01']])
  const items = await svc.getHistory(context(), 20, 40)
  assert.deepEqual(fixture.calls.at(-1), { name: 'rpc_obtener_historial_jornadas_operativas', args: { p_limite: 20, p_offset: 40 } })
  assert.deepEqual(Object.keys(items.data[0]).sort(), ['abiertaEn', 'abiertaPorNombre', 'cerradaEn', 'cerradaPorNombre', 'estado', 'id', 'identificacion'])
  const before = fixture.calls.length
  for (const role of ['MOZO', 'COCINA', 'CAJA']) {
    assert.equal((await svc.open(context(role), 'k')).ok, false)
    assert.equal((await svc.close(context(role), 1)).ok, false)
    assert.equal((await svc.getHistory(context(role), 20, 0)).ok, false)
  }
  assert.equal(fixture.calls.length, before)
})

// ===== Ruta y navegación

test('E9-T05 /admin/jornadas sólo para ADMINISTRADOR y en OPERACIÓN → Jornadas', () => {
  assert.deepEqual(resolve('/admin/jornadas', 'ADMINISTRADOR'), { status: 'allowed', pathname: '/admin/jornadas' })
  for (const role of ['MOZO', 'COCINA', 'CAJA']) assert.deepEqual(resolve('/admin/jornadas', role), { status: 'redirect', pathname: '/403' })
  assert.match(shell, /label: "OPERACIÓN", items: \[[^\]]*\{ icon: "◷", label: "Jornadas", route: "\/admin\/jornadas" \}\]/)
  assert.match(app, /resolution\.pathname === '\/admin\/jornadas'\) content = <AdminOperationalDaysPage context=\{profileContext\.context\} \/>/)
})

// ===== Inicio: bloque de jornada (TP20)

test('E9-T05 el bloque de jornada es el primero de Inicio y no altera los bloques existentes', () => {
  assert.match(home, /<OperationalDayAdminPanel context=\{context\} onCash=\{onCash\} onOrders=\{onOrders\} \/>/)
  const panelIndex = home.indexOf('<OperationalDayAdminPanel')
  for (const label of ['Indicadores de hoy', 'Requiere tu atención', 'Flujo actual de pedidos', 'Ventas por medio', 'Operación de caja']) {
    assert.ok(home.indexOf(label) > panelIndex, label)
  }
})

test('E9-T05 abrir y cerrar con confirmación, una sola llamada ante doble clic y avisos de idempotencia', () => {
  assert.match(panel, /¿Abrir la jornada operativa del local\? Mozo, Cocina y Caja podrán operar\./)
  assert.match(panel, /Se verificará que no queden pedidos ni cajas abiertas\./)
  assert.match(panel, />Abrir jornada</)
  assert.match(panel, />Cerrar jornada</)
  assert.match(panel, /if \(pending\.current\) return;\s*pending\.current = true;/)
  assert.match(panel, /disabled=\{busy\}/)
  assert.match(panel, /openKey\.current \?\?= crypto\.randomUUID\(\)/)
  assert.match(panel, /La jornada ya estaba abierta/)
  assert.match(panel, /La jornada ya estaba cerrada/)
  assert.match(panel, /subscribeToOperationalDay\(clientResult\.client/)
})

test('E9-T05 un cierre impedido muestra los pendientes con enlaces y la secuencia sugerida', () => {
  assert.match(panel, /if \(result\.error\.kind === "conflict"\) \{\s*const pendingItems = await service\.getClosingBlockers\(context\)/)
  assert.match(panel, /Pendientes para cerrar la jornada/)
  assert.match(panel, /Cobra o anula los pedidos, cierra la caja y vuelve a cerrar la jornada\./)
  assert.match(panel, />Ver pedidos</)
  assert.match(panel, />Ver caja</)
})

test('E9-T05 / R25: sin métricas ni totales en el bloque ni en el historial; historial paginado con Cargar más', () => {
  const code = (source) => source.replace(/\/\*[\s\S]*?\*\//g, '').replace(/^\s*\/\/.*$/gm, '')
  for (const source of [panel, history]) assert.doesNotMatch(code(source), /money|Intl\.NumberFormat|total|importe|ventas netas|ticket promedio/i)
  assert.match(history, /export const OPERATIONAL_DAY_PAGE_SIZE = 20/)
  assert.match(history, /service\.getHistory\(context, OPERATIONAL_DAY_PAGE_SIZE, offset\)/)
  assert.match(history, />Cargar más</)
  assert.match(history, /role="table"/)
  for (const label of ['Jornada', 'Estado', 'Apertura', 'Cierre']) assert.match(history, new RegExp(`role="columnheader">${label}<`))
})

test('E9-T05 responsive y táctil: objetivos de 44 px y filas que no fuerzan desplazamiento horizontal', () => {
  assert.match(panel, /min-h-11/)
  assert.match(history, /min-h-11/)
  assert.match(history, /grid-cols-1[^"]*sm:grid-cols-\[2fr_1fr_2fr_2fr\]/)
  assert.match(panel, /min-w-0/)
})
