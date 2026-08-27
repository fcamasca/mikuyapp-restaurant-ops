import assert from 'node:assert/strict'
import { test } from 'node:test'
import { getRoleDestination, resolveApplicationRoute } from '../src/services/appRoutes.ts'

function resolve(pathname, overrides = {}) {
  return resolveApplicationRoute({
    pathname,
    authenticationStatus: 'authenticated',
    contextStatus: 'valid',
    role: 'ADMINISTRADOR',
    ...overrides,
  })
}

test('redirige usuarios anónimos desde todas las rutas protegidas a login', () => {
  for (const pathname of ['/tecnica', '/admin/catalogo', '/cocina', '/mozo/mesas', '/403']) {
    assert.deepEqual(
      resolve(pathname, { authenticationStatus: 'unauthenticated', contextStatus: 'idle', role: null }),
      { status: 'redirect', pathname: '/login' },
    )
  }
})

test('permite abrir login a usuarios sin sesión', () => {
  assert.deepEqual(
    resolve('/login', { authenticationStatus: 'unauthenticated', contextStatus: 'idle', role: null }),
    { status: 'allowed', pathname: '/login' },
  )
})

test('mantiene carga sin exponer contenido durante restauración de sesión', () => {
  assert.deepEqual(
    resolve('/admin/catalogo', { authenticationStatus: 'loading', contextStatus: 'idle', role: null }),
    { status: 'loading' },
  )
})

test('mantiene carga sin exponer contenido mientras se valida el contexto', () => {
  assert.deepEqual(
    resolve('/admin/catalogo', { contextStatus: 'loading', role: null }),
    { status: 'loading' },
  )
})

test('redirige cada rol a su destino inicial autorizado', () => {
  const destinations = {
    ADMINISTRADOR: '/admin/catalogo',
    MOZO: '/mozo/mesas',
    COCINA: '/cocina',
    CAJA: '/tecnica',
  }

  for (const [role, pathname] of Object.entries(destinations)) {
    assert.equal(getRoleDestination(role), pathname)
    assert.deepEqual(resolve('/', { role }), { status: 'redirect', pathname })
  }
})

test('envía a 403 cuando un rol abre directamente una ruta ajena', () => {
  assert.deepEqual(resolve('/admin/catalogo', { role: 'MOZO' }), {
    status: 'redirect',
    pathname: '/403',
  })
  assert.deepEqual(resolve('/mozo/mesas', { role: 'ADMINISTRADOR' }), {
    status: 'redirect',
    pathname: '/403',
  })
  assert.deepEqual(resolve('/admin/catalogo', { role: 'COCINA' }), {
    status: 'redirect',
    pathname: '/403',
  })
  assert.deepEqual(resolve('/cocina', { role: 'MOZO' }), {
    status: 'redirect',
    pathname: '/403',
  })
  assert.deepEqual(resolve('/cocina', { role: 'COCINA' }), {
    status: 'allowed',
    pathname: '/cocina',
  })
})

test('permite acceso a técnica a los cuatro roles autorizados', () => {
  for (const role of ['ADMINISTRADOR', 'MOZO', 'COCINA', 'CAJA']) {
    assert.deepEqual(resolve('/tecnica', { role }), { status: 'allowed', pathname: '/tecnica' })
  }
})

test('redirige un usuario autenticado que abre login a su destino por rol', () => {
  assert.deepEqual(resolve('/login', { role: 'ADMINISTRADOR' }), {
    status: 'redirect',
    pathname: '/admin/catalogo',
  })
  assert.deepEqual(resolve('/login', { role: 'MOZO' }), {
    status: 'redirect',
    pathname: '/mozo/mesas',
  })
  assert.deepEqual(resolve('/login', { role: 'CAJA' }), {
    status: 'redirect',
    pathname: '/tecnica',
  })
})

test('bloquea acceso operativo cuando el contexto es inválido', () => {
  assert.deepEqual(resolve('/admin/catalogo', { contextStatus: 'invalid', role: null }), {
    status: 'invalid-context',
  })
})

test('mantiene visible el error recuperable sin mostrar contenido protegido', () => {
  assert.deepEqual(resolve('/admin/catalogo', { contextStatus: 'error', role: null }), {
    status: 'recoverable-error',
  })
})

test('redirige una ruta inexistente a 403 sin generar bucles', () => {
  assert.deepEqual(resolve('/ruta-inexistente'), { status: 'redirect', pathname: '/403' })
  assert.deepEqual(resolve('/403'), { status: 'allowed', pathname: '/403' })
})

test('rechaza rutas de retorno externas o ambiguas', () => {
  assert.deepEqual(resolve('//example.invalid'), { status: 'redirect', pathname: '/403' })
  assert.deepEqual(resolve('https://example.invalid'), { status: 'redirect', pathname: '/403' })
  assert.deepEqual(resolve('/\\example.invalid'), { status: 'redirect', pathname: '/403' })
})

test('permite únicamente la ruta operativa correspondiente a cada rol', () => {
  assert.deepEqual(resolve('/admin/catalogo', { role: 'ADMINISTRADOR' }), {
    status: 'allowed',
    pathname: '/admin/catalogo',
  })
  assert.deepEqual(resolve('/mozo/mesas', { role: 'MOZO' }), {
    status: 'allowed',
    pathname: '/mozo/mesas',
  })
})
