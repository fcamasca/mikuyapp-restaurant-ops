import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import test from 'node:test'
import { getRoleDestination, resolveApplicationRoute } from '../src/services/appRoutes.ts'

const page = readFileSync(new URL('../src/pages/VerificationPage.tsx', import.meta.url), 'utf8')
const app = readFileSync(new URL('../src/App.tsx', import.meta.url), 'utf8')

function resolve(pathname, overrides = {}) {
  return resolveApplicationRoute({ pathname, authenticationStatus: 'authenticated', contextStatus: 'valid', role: 'ADMINISTRADOR', ...overrides })
}

test('TP-02: técnica muestra únicamente los cinco indicadores aprobados', () => {
  for (const text of ['Aplicación cargada', 'Sesión autenticada', 'Conexión con Supabase disponible', 'Configuración pública disponible', 'Rol:']) {
    assert.match(page, new RegExp(text))
  }
})

test('TP-02 y TP-19: técnica no consulta catálogos, mesas ni ejecuta mutaciones', () => {
  assert.doesNotMatch(page, /getDemoCatalog|getOperationalCatalog|getAdministrativeCatalog/)
  assert.doesNotMatch(page, /getOperationalTables|getAdministrativeTables|\.from\(/)
  assert.doesNotMatch(page, /insert|update|delete|upsert|rpc/i)
  assert.doesNotMatch(page, /demoCatalogService|catalogService|supabaseClient/)
})

test('TP-02: técnica no expone identificadores, credenciales ni valores de configuración', () => {
  assert.doesNotMatch(page, /session\.user|\.id\}|access_token|refresh_token|publishable_key|service_role/i)
  assert.doesNotMatch(page, /VITE_SUPABASE_URL|VITE_SUPABASE_PUBLISHABLE_KEY/)
  assert.match(page, /roleNames\[role\]/)
})

test('TP-09 y TP-10: los cuatro roles válidos acceden directamente a técnica', () => {
  for (const role of ['ADMINISTRADOR', 'MOZO', 'COCINA', 'CAJA']) {
    assert.deepEqual(resolve('/tecnica', { role }), { status: 'allowed', pathname: '/tecnica' })
  }
})

test('TP-09: usuario anónimo es enviado a login y contexto inválido es rechazado', () => {
  assert.deepEqual(resolve('/tecnica', { authenticationStatus: 'unauthenticated', contextStatus: 'idle', role: null }), { status: 'redirect', pathname: '/login' })
  assert.deepEqual(resolve('/tecnica', { contextStatus: 'invalid', role: null }), { status: 'invalid-context' })
})

test('TP-10 y H4-T06: cocina llega a su tablero y caja conserva técnica', () => {
  assert.equal(getRoleDestination('COCINA'), '/cocina')
  assert.equal(getRoleDestination('CAJA'), '/tecnica')
  assert.deepEqual(resolve('/login', { role: 'COCINA' }), { status: 'redirect', pathname: '/cocina' })
  assert.deepEqual(resolve('/login', { role: 'CAJA' }), { status: 'redirect', pathname: '/tecnica' })
})

test('TP-27: rutas operativas ajenas al rol continúan enviando a 403', () => {
  assert.deepEqual(resolve('/admin/catalogo', { role: 'COCINA' }), { status: 'redirect', pathname: '/403' })
  assert.deepEqual(resolve('/mozo/mesas', { role: 'CAJA' }), { status: 'redirect', pathname: '/403' })
})

test('App entrega a técnica solo el rol validado y conserva cierre de sesión', () => {
  assert.match(app, /<VerificationPage role=\{role\} \/>/)
  assert.match(app, /resolution\.pathname === '\/tecnica'/)
  assert.match(app, /void signOut\(\)/)
})
