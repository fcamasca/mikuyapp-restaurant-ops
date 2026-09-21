import test from 'node:test'
import assert from 'node:assert/strict'
import { readFile } from 'node:fs/promises'
import { createSalesService, csv } from '../src/services/salesService.ts'

const context = (role) => ({ role: { codigo: role }, local: { id: 'local-1', nombre: 'Demo' } })
test('H6-TP01/02: resume filas autorizadas y normaliza cantidades/importes', async () => { const s=createSalesService({rpc:async()=>({data:[{medio:'EFECTIVO',pedidos_pagados:2,importe:'40.50'}],error:null})}); assert.deepEqual(await s.getSummary(context('CAJA')),{ok:true,data:[{method:'EFECTIVO',paidOrders:2,amount:40.5}]}) })
test('H6-TP04: roles no autorizados se rechazan sin RPC', async () => { let called=false; const s=createSalesService({rpc:async()=>{called=true;return {data:[],error:null}}}); assert.equal((await s.getSummary(context('MOZO'))).ok,false); assert.equal(called,false) })
test('H6-TP05/06: CSV escapa comillas y termina en CRLF', () => { assert.equal(csv([{a:'uno,"dos"',b:2}]), '"a","b"\r\n"uno,""dos""","2"\r\n') })
test('H6-TP07: exportaciones solo están disponibles para administrador', async () => { const s=createSalesService({rpc:async()=>({data:[],error:null})}); assert.equal((await s.exportSales(context('CAJA'))).ok,false); assert.equal((await s.exportProducts(context('MOZO'))).ok,false) })
test('E1-TP57: resumen diario consume totales autoritativos y normaliza el snapshot', async () => {
  const calls=[];const s=createSalesService({rpc:async(name)=>{calls.push(name);return{error:null,data:[{fecha_operativa:'2026-09-17',total_vendido:'90',venta_efectivo:'40',venta_yape:'50',venta_plin:'0',venta_tarjeta:'0',total_propinas:'7',propina_efectivo:'5',propina_yape:'2',propina_plin:'0',propina_tarjeta:'0',descuentos:'10',cantidad_anulaciones:1,cantidad_pagos:2,pagos_parciales:2,cantidad_pedidos_completados:1}]}}})
  const result=await s.getDailyCashSummary(context('CAJA'));assert.equal(result.ok,true);assert.equal(result.data.totalSold,90);assert.deepEqual(result.data.salesByMethod,{EFECTIVO:40,YAPE:50,PLIN:0,TARJETA:0});assert.equal(result.data.completedOrders,1);assert.deepEqual(calls,['rpc_obtener_resumen_diario_caja'])
})
test('E1-TP56/58: reporte de sesión conserva actores, snapshots y solicita filtro autoritativo', async () => {
  const calls=[];const s=createSalesService({rpc:async(name,args)=>{calls.push([name,args]);return{error:null,data:[{sesion_caja_id:'s1',caja_codigo:'C1',caja_nombre:'Principal',estado:'CERRADA',abierta_por_nombre:'Caja A',cerrada_por_nombre:'Caja B',abierta_en:'2026-09-17T13:00:00Z',cerrada_en:'2026-09-17T23:00:00Z',monto_inicial:'100',venta_efectivo:'40',venta_yape:'50',venta_plin:'0',venta_tarjeta:'0',propina_efectivo:'5',propina_yape:'2',propina_plin:'0',propina_tarjeta:'0',entradas:'20',salidas:'5',efectivo_esperado:'160',efectivo_contado:'158',diferencia:'-2',descuentos:'10',cantidad_anulaciones:1,cantidad_pagos:2,pagos_parciales:2,cantidad_pedidos_completados:1}]}}})
  const result=await s.getSessionReports(context('ADMINISTRADOR'));assert.equal(result.ok,true);assert.equal(result.data[0].expectedCash,160);assert.equal(result.data[0].closedBy,'Caja B');assert.deepEqual(calls,[['rpc_obtener_reportes_sesion_caja',{p_sesion_caja_id:null}]])
})
test('E1-T12: roles operativos ajenos se rechazan antes de invocar reportes', async()=>{let called=false;const s=createSalesService({rpc:async()=>{called=true;return{data:[],error:null}}});assert.equal((await s.getDailyCashSummary(context('MOZO'))).ok,false);assert.equal((await s.getSessionReports(context('COCINA'))).ok,false);assert.equal(called,false)})
test('E1-TP58: CSV usa los snapshots cargados sin recalcular totales financieros',async()=>{const page=await readFile(new URL('../src/pages/SalesPage.tsx',import.meta.url),'utf8');assert.match(page,/dailyCsv\(daily\)/);assert.match(page,/sessionCsv\(selected\)/);assert.doesNotMatch(page,/summary\.reduce|total\s*=\s*.*reduce/)})
test('H6-T02: administrador y caja tienen navegación visible de ida y retorno', async () => {
  const [menu, app, adminPage, cashierPage, salesPage] = await Promise.all([
    readFile(new URL('../src/components/AuthenticatedUserMenu.tsx', import.meta.url), 'utf8'),
    readFile(new URL('../src/App.tsx', import.meta.url), 'utf8'),
    readFile(new URL('../src/pages/CategoryAdministrationPage.tsx', import.meta.url), 'utf8'),
    readFile(new URL('../src/pages/CashierPage.tsx', import.meta.url), 'utf8'),
    readFile(new URL('../src/pages/SalesPage.tsx', import.meta.url), 'utf8'),
  ])
  assert.doesNotMatch(menu, /Resumen diario|onNavigateToSales/)
  assert.match(app, /onNavigateToSales=\{\(\) => navigate\('\/ventas'\)\}/g)
  assert.match(adminPage, /onClick=\{onNavigateToSales\}[\s\S]*?Resumen diario/)
  assert.match(cashierPage, /onClick=\{onNavigateToSales\}[\s\S]*?Resumen diario/)
  assert.match(app, /onBack=\{\(\) => navigate\(getRoleDestination\(role\)\)\}/)
  assert.match(salesPage, /context\.role\.codigo === 'CAJA' \? 'Volver a cobros pendientes' : 'Volver a Inicio'/)
})
