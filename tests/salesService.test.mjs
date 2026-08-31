import test from 'node:test'
import assert from 'node:assert/strict'
import { readFile } from 'node:fs/promises'
import { createSalesService, csv } from '../src/services/salesService.ts'

const context = (role) => ({ role: { codigo: role }, local: { id: 'local-1', nombre: 'Demo' } })
test('H6-TP01/02: resume filas autorizadas y normaliza cantidades/importes', async () => { const s=createSalesService({rpc:async()=>({data:[{medio:'EFECTIVO',pedidos_pagados:2,importe:'40.50'}],error:null})}); assert.deepEqual(await s.getSummary(context('CAJA')),{ok:true,data:[{method:'EFECTIVO',paidOrders:2,amount:40.5}]}) })
test('H6-TP04: roles no autorizados se rechazan sin RPC', async () => { let called=false; const s=createSalesService({rpc:async()=>{called=true;return {data:[],error:null}}}); assert.equal((await s.getSummary(context('MOZO'))).ok,false); assert.equal(called,false) })
test('H6-TP05/06: CSV escapa comillas y termina en CRLF', () => { assert.equal(csv([{a:'uno,"dos"',b:2}]), '"a","b"\r\n"uno,""dos""","2"\r\n') })
test('H6-TP07: exportaciones solo están disponibles para administrador', async () => { const s=createSalesService({rpc:async()=>({data:[],error:null})}); assert.equal((await s.exportSales(context('CAJA'))).ok,false); assert.equal((await s.exportProducts(context('MOZO'))).ok,false) })
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
  assert.match(salesPage, /context\.role\.codigo === 'CAJA' \? 'Volver a cobros pendientes' : 'Volver al catálogo'/)
})
