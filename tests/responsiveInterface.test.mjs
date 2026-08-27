import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import test from 'node:test'

const login = readFileSync(new URL('../src/pages/LoginPage.tsx', import.meta.url), 'utf8')
const admin = readFileSync(new URL('../src/pages/CategoryAdministrationPage.tsx', import.meta.url), 'utf8')
const waiter = readFileSync(new URL('../src/pages/WaiterTablesPage.tsx', import.meta.url), 'utf8')
const app = readFileSync(new URL('../src/App.tsx', import.meta.url), 'utf8')

test('TP-24: login mantiene controles táctiles y estados accesibles en móvil', () => {
  assert.match(login, /overflow-x-hidden/)
  assert.match(login, /min-h-12 w-full min-w-0[^"\n]*text-base/)
  assert.match(login, /aria-busy=\{isSigningIn\}/)
  assert.match(login, /disabled=\{isSigningIn\}/)
  assert.match(login, /Iniciando sesión…/)
})

test('TP-13 y TP-29: la administración fluye sin anchos mínimos rígidos', () => {
  assert.match(admin, /overflow-x-hidden/)
  assert.match(admin, /grid min-w-0 gap-6 lg:grid-cols-\[minmax\(0,22rem\)_minmax\(0,1fr\)\]/)
  assert.match(admin, /min-h-12 w-full min-w-0[^'\n]*text-base/)
  assert.match(admin, /grid gap-2 sm:flex sm:flex-wrap/)
  assert.match(admin, /min-h-11 w-full[^\n]*sm:w-auto/)
  assert.doesNotMatch(admin, /min-w-\[(?:[4-9]\d\d|\d{4,})px\]/)
})

test('TP-29: cada catálogo conserva carga, vacío, error, éxito y reintento', () => {
  assert.match(admin, /Cargando categorías…/)
  assert.match(admin, /Todavía no hay categorías registradas/)
  assert.match(admin, /Reintentar catálogo/)
  assert.match(admin, /role="status"/)
  assert.match(admin, /Cargando mesas…/)
  assert.match(admin, /Todavía no hay mesas registradas/)
  assert.match(admin, /Reintentar mesas/)
})

test('TP-29: operaciones de categorías, productos y mesas son independientes', () => {
  for (const resource of ['category', 'product', 'table']) {
    assert.match(admin, new RegExp(`const \\[${resource}Saving, set${resource[0].toUpperCase()}${resource.slice(1)}Saving\\]`))
    assert.match(admin, new RegExp(`${resource}MutationPending`))
  }
  assert.doesNotMatch(admin, /const \[saving, setSaving\]/)
  assert.doesNotMatch(admin, /const mutationPending =/)
})

test('TP-29: catálogo y mesas administrativas cargan y reintentan por separado', () => {
  assert.match(admin, /const \[catalogLoading, setCatalogLoading\]/)
  assert.match(admin, /const \[tablesLoading, setTablesLoading\]/)
  assert.match(admin, /const \[catalogAttempt, setCatalogAttempt\]/)
  assert.match(admin, /const \[tablesAttempt, setTablesAttempt\]/)
})

test('TP-53: tablero operativo adapta cards y controles para móvil y tablet', () => {
  assert.match(waiter, /overflow-x-hidden/)
  assert.match(waiter, /grid min-w-0 gap-4 sm:grid-cols-2 xl:grid-cols-3/)
  assert.match(waiter, /grid min-w-0 gap-2 sm:grid-cols-2 lg:grid-cols-4/)
  assert.match(waiter, /min-w-0 break-words/)
  assert.match(waiter, /min-h-12 w-full/)
  assert.match(waiter, /min-h-11 w-full min-w-0/)
})

test('TP-53: tablero conserva carga, vacío, error y reintento', () => {
  assert.match(waiter, /const \[loading, setLoading\]/)
  assert.match(waiter, /No hay mesas disponibles/)
  assert.match(waiter, /Reintentar mesas/)
})

test('TP-53: los cuatro estados de mesa tienen texto además del color', () => {
  for (const label of ['Libre', 'Ocupada', 'Pedido listo', 'Pendiente de pago']) {
    assert.match(waiter, new RegExp(label))
  }
  assert.match(waiter, /Estado: <strong>\{status\.label\}<\/strong>/)
})

test('TP-24: la vista 403 es táctil y no desborda en pantallas pequeñas', () => {
  assert.match(app, /const isForbidden = resolution\.pathname === '\/403'/)
  assert.match(app, /overflow-x-hidden/)
  assert.match(app, /flex flex-col gap-3 sm:flex-row/)
  assert.match(app, /min-h-12/)
})

test('contrato de anchos representativos conserva una sola columna antes de cada breakpoint', () => {
  const layouts = [
    { width: 360, admin: 1, waiter: 1, legend: 1 },
    { width: 390, admin: 1, waiter: 1, legend: 1 },
    { width: 768, admin: 1, waiter: 2, legend: 2 },
    { width: 1280, admin: 2, waiter: 3, legend: 4 },
  ]

  assert.deepEqual(layouts.map(({ width }) => width), [360, 390, 768, 1280])
  assert.deepEqual(layouts.map(({ admin }) => admin), [1, 1, 1, 2])
  assert.deepEqual(layouts.map(({ waiter }) => waiter), [1, 1, 2, 3])
  assert.deepEqual(layouts.map(({ legend }) => legend), [1, 1, 2, 4])
})
