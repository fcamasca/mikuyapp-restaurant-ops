import type { AuthenticationStatus } from './authSession'
import type { ProfileContextStatus } from './profileContext'
import type { RoleCode } from '../types/operations'

export type ApplicationRoute =
  | '/login'
  | '/tecnica'
  | '/admin/catalogo'
  | '/mozo/mesas'
  | '/403'

export interface RouteAuthorizationInput {
  readonly pathname: string
  readonly authenticationStatus: AuthenticationStatus
  readonly contextStatus: ProfileContextStatus
  readonly role: RoleCode | null
}

export type RouteAuthorization =
  | { readonly status: 'loading' }
  | { readonly status: 'invalid-context' }
  | { readonly status: 'recoverable-error' }
  | { readonly status: 'redirect'; readonly pathname: ApplicationRoute }
  | { readonly status: 'allowed'; readonly pathname: ApplicationRoute }

const knownRoutes = new Set<ApplicationRoute>([
  '/login',
  '/tecnica',
  '/admin/catalogo',
  '/mozo/mesas',
  '/403',
])

export function getRoleDestination(role: RoleCode): ApplicationRoute {
  switch (role) {
    case 'ADMINISTRADOR':
      return '/admin/catalogo'
    case 'MOZO':
      return '/mozo/mesas'
    case 'COCINA':
    case 'CAJA':
      return '/tecnica'
  }
}

function isSafeInternalPath(pathname: string): boolean {
  return pathname.startsWith('/')
    && !pathname.startsWith('//')
    && !pathname.includes('\\')
}

export function resolveApplicationRoute(input: RouteAuthorizationInput): RouteAuthorization {
  const { pathname, authenticationStatus, contextStatus, role } = input

  if (authenticationStatus === 'loading') {
    return { status: 'loading' }
  }

  if (authenticationStatus !== 'authenticated') {
    return pathname === '/login'
      ? { status: 'allowed', pathname: '/login' }
      : { status: 'redirect', pathname: '/login' }
  }

  if (contextStatus === 'idle' || contextStatus === 'loading') {
    return { status: 'loading' }
  }

  if (contextStatus === 'invalid') {
    return { status: 'invalid-context' }
  }

  if (contextStatus === 'error') {
    return { status: 'recoverable-error' }
  }

  if (contextStatus !== 'valid' || !role) {
    return { status: 'invalid-context' }
  }

  if (pathname === '/' || pathname === '/login') {
    return { status: 'redirect', pathname: getRoleDestination(role) }
  }

  if (!isSafeInternalPath(pathname) || !knownRoutes.has(pathname as ApplicationRoute)) {
    return { status: 'redirect', pathname: '/403' }
  }

  if (pathname === '/admin/catalogo' && role !== 'ADMINISTRADOR') {
    return { status: 'redirect', pathname: '/403' }
  }

  if (pathname === '/mozo/mesas' && role !== 'MOZO') {
    return { status: 'redirect', pathname: '/403' }
  }

  return { status: 'allowed', pathname: pathname as ApplicationRoute }
}
