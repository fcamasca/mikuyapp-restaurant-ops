import { readFile } from 'node:fs/promises'

const STATES = new Set(['LEGACY_SHARED', 'TRANSITIONING', 'SEPARATED'])
const LOGICAL_ENVIRONMENTS = new Set(['DEV', 'SHARED', 'PROD'])

export class EnvironmentGuardError extends Error {
  constructor(code, message) {
    super(message)
    this.name = 'EnvironmentGuardError'
    this.code = code
  }
}

function required(value, code, label) {
  const normalized = value?.trim()
  if (!normalized) {
    throw new EnvironmentGuardError(code, `Configuración incompleta: falta ${label}.`)
  }
  return normalized
}

function normalizeRef(value, code, label) {
  const ref = required(value, code, label).toLowerCase()
  if (!/^[a-z0-9]+$/.test(ref)) {
    throw new EnvironmentGuardError(code, `${label} no tiene un formato válido.`)
  }
  return ref
}

export function extractSupabaseProjectRef(rawUrl) {
  const value = required(rawUrl, 'MISSING_SUPABASE_URL', 'VITE_SUPABASE_URL')
  let parsed
  try {
    parsed = new URL(value)
  } catch {
    throw new EnvironmentGuardError('INVALID_SUPABASE_URL', 'La URL pública de Supabase no es válida.')
  }

  if (parsed.protocol !== 'https:') {
    throw new EnvironmentGuardError('INVALID_SUPABASE_URL', 'La URL pública de Supabase debe usar HTTPS.')
  }

  const match = parsed.hostname.match(/^([a-z0-9]+)\.supabase\.co$/i)
  if (!match) {
    throw new EnvironmentGuardError('UNSUPPORTED_SUPABASE_HOST', 'La URL no contiene un project ref de Supabase reconocible.')
  }
  return match[1].toLowerCase()
}

export function resolveDeploymentContext(env) {
  if (env.CF_PAGES !== '1') {
    return 'local'
  }

  const branch = required(env.CF_PAGES_BRANCH, 'MISSING_CLOUDFLARE_BRANCH', 'CF_PAGES_BRANCH')
  const productionBranch = env.MIKUY_PRODUCTION_BRANCH?.trim() || 'main'
  return branch === productionBranch ? 'production' : 'preview'
}

function expectedLogicalEnvironment(context, state) {
  if (context === 'local' || context === 'preview') {
    return 'DEV'
  }
  return state === 'SEPARATED' ? 'PROD' : 'SHARED'
}

function refVariableFor(logicalEnvironment) {
  return {
    DEV: 'MIKUY_DEV_SUPABASE_PROJECT_REF',
    SHARED: 'MIKUY_SHARED_SUPABASE_PROJECT_REF',
    PROD: 'MIKUY_PROD_SUPABASE_PROJECT_REF',
  }[logicalEnvironment]
}

export function validateEnvironmentConfiguration(env, localLinkedProjectRef) {
  const context = resolveDeploymentContext(env)
  const state = (env.MIKUY_ENVIRONMENT_STATE?.trim() || (context === 'local' ? 'LEGACY_SHARED' : ''))
    .toUpperCase()
  if (!STATES.has(state)) {
    throw new EnvironmentGuardError('INVALID_ENVIRONMENT_STATE', 'El estado de ambientes es obligatorio y no es válido.')
  }

  const logicalEnvironment = (
    env.MIKUY_LOGICAL_ENVIRONMENT?.trim() || (context === 'local' ? 'DEV' : '')
  ).toUpperCase()
  if (!LOGICAL_ENVIRONMENTS.has(logicalEnvironment)) {
    throw new EnvironmentGuardError('INVALID_LOGICAL_ENVIRONMENT', 'La identidad lógica del ambiente es obligatoria y no es válida.')
  }

  const allowedLogicalEnvironment = expectedLogicalEnvironment(context, state)
  if (logicalEnvironment !== allowedLogicalEnvironment) {
    throw new EnvironmentGuardError('CONTEXT_ENVIRONMENT_MISMATCH', 'El contexto de deployment no coincide con la identidad lógica permitida.')
  }

  const effectiveRef = extractSupabaseProjectRef(env.VITE_SUPABASE_URL)
  required(env.VITE_SUPABASE_PUBLISHABLE_KEY, 'MISSING_PUBLISHABLE_KEY', 'VITE_SUPABASE_PUBLISHABLE_KEY')

  const localFallback = context === 'local' ? localLinkedProjectRef?.trim() : undefined
  const expectedRef = normalizeRef(
    env.MIKUY_EXPECTED_SUPABASE_PROJECT_REF || localFallback,
    'MISSING_EXPECTED_PROJECT_REF',
    'MIKUY_EXPECTED_SUPABASE_PROJECT_REF',
  )
  const roleRefName = refVariableFor(logicalEnvironment)
  const roleRef = normalizeRef(
    env[roleRefName] || localFallback,
    'MISSING_LOGICAL_PROJECT_REF',
    roleRefName,
  )

  if (expectedRef !== roleRef || effectiveRef !== expectedRef) {
    throw new EnvironmentGuardError('PROJECT_REF_MISMATCH', 'El project ref efectivo no coincide con el esperado para este ambiente.')
  }

  return { context, state, logicalEnvironment, effectiveRef }
}

export async function readLocalLinkedProjectRef(path = 'supabase/.temp/project-ref') {
  try {
    return (await readFile(path, 'utf8')).trim()
  } catch (error) {
    if (error?.code === 'ENOENT') {
      return undefined
    }
    throw error
  }
}

export function maskProjectRef(ref) {
  if (ref.length <= 8) return '***'
  return `${ref.slice(0, 4)}…${ref.slice(-4)}`
}
