import assert from 'node:assert/strict'
import { test } from 'node:test'
import {
  EnvironmentGuardError,
  extractSupabaseProjectRef,
  validateEnvironmentConfiguration,
} from '../scripts/environmentGuard.mjs'

const DEV_REF = 'abcdefghijklmnopqrst'
const PROD_REF = 'zyxwvutsrqponmlkjihg'
const PUBLIC_KEY = 'public-test-key'

function config(overrides = {}) {
  return {
    CF_PAGES: '1',
    CF_PAGES_BRANCH: 'feature/environment-separation',
    MIKUY_PRODUCTION_BRANCH: 'main',
    MIKUY_ENVIRONMENT_STATE: 'LEGACY_SHARED',
    MIKUY_LOGICAL_ENVIRONMENT: 'DEV',
    MIKUY_EXPECTED_SUPABASE_PROJECT_REF: DEV_REF,
    MIKUY_DEV_SUPABASE_PROJECT_REF: DEV_REF,
    MIKUY_SHARED_SUPABASE_PROJECT_REF: DEV_REF,
    MIKUY_PROD_SUPABASE_PROJECT_REF: PROD_REF,
    VITE_SUPABASE_URL: `https://${DEV_REF}.supabase.co`,
    VITE_SUPABASE_PUBLISHABLE_KEY: PUBLIC_KEY,
    ...overrides,
  }
}

function assertCode(expectedCode, callback) {
  assert.throws(callback, (error) => {
    assert.ok(error instanceof EnvironmentGuardError)
    assert.equal(error.code, expectedCode)
    assert.doesNotMatch(error.message, new RegExp(`${DEV_REF}|${PROD_REF}|${PUBLIC_KEY}`))
    return true
  })
}

test('TP07 permite Preview conectado al proyecto actual destinado a DEV', () => {
  const result = validateEnvironmentConfiguration(config())
  assert.deepEqual(result, {
    context: 'preview',
    state: 'LEGACY_SHARED',
    logicalEnvironment: 'DEV',
    effectiveRef: DEV_REF,
  })
})

test('TP08 permite Production al proyecto actual durante LEGACY_SHARED y TRANSITIONING', () => {
  for (const state of ['LEGACY_SHARED', 'TRANSITIONING']) {
    const result = validateEnvironmentConfiguration(config({
      CF_PAGES_BRANCH: 'main',
      MIKUY_ENVIRONMENT_STATE: state,
      MIKUY_LOGICAL_ENVIRONMENT: 'SHARED',
      MIKUY_SHARED_SUPABASE_PROJECT_REF: DEV_REF,
    }))
    assert.equal(result.context, 'production')
    assert.equal(result.state, state)
  }
})

test('TP08 permite Production conectado a PROD en SEPARATED', () => {
  const result = validateEnvironmentConfiguration(config({
    CF_PAGES_BRANCH: 'main',
    MIKUY_ENVIRONMENT_STATE: 'SEPARATED',
    MIKUY_LOGICAL_ENVIRONMENT: 'PROD',
    MIKUY_EXPECTED_SUPABASE_PROJECT_REF: PROD_REF,
    VITE_SUPABASE_URL: `https://${PROD_REF}.supabase.co`,
  }))
  assert.equal(result.logicalEnvironment, 'PROD')
})

test('TP09 bloquea Preview conectado a PROD', () => {
  assertCode('PROJECT_REF_MISMATCH', () => validateEnvironmentConfiguration(config({
    VITE_SUPABASE_URL: `https://${PROD_REF}.supabase.co`,
  })))
})

test('TP10 bloquea Production conectado a DEV exclusivo en SEPARATED', () => {
  assertCode('CONTEXT_ENVIRONMENT_MISMATCH', () => validateEnvironmentConfiguration(config({
    CF_PAGES_BRANCH: 'main',
    MIKUY_ENVIRONMENT_STATE: 'SEPARATED',
    MIKUY_LOGICAL_ENVIRONMENT: 'DEV',
  })))
})

test('TP11 bloquea estado, identidad, contexto y ref incompletos o inconsistentes', () => {
  assertCode('INVALID_ENVIRONMENT_STATE', () => validateEnvironmentConfiguration(config({ MIKUY_ENVIRONMENT_STATE: '' })))
  assertCode('INVALID_LOGICAL_ENVIRONMENT', () => validateEnvironmentConfiguration(config({ MIKUY_LOGICAL_ENVIRONMENT: '' })))
  assertCode('MISSING_CLOUDFLARE_BRANCH', () => validateEnvironmentConfiguration(config({ CF_PAGES_BRANCH: '' })))
  assertCode('PROJECT_REF_MISMATCH', () => validateEnvironmentConfiguration(config({ MIKUY_EXPECTED_SUPABASE_PROJECT_REF: PROD_REF })))
  assertCode('MISSING_PUBLISHABLE_KEY', () => validateEnvironmentConfiguration(config({ VITE_SUPABASE_PUBLISHABLE_KEY: '' })))
})

test('TP12 permite Local con DEV vinculado y bloquea Local conectado a PROD', () => {
  const local = config({
    CF_PAGES: undefined,
    CF_PAGES_BRANCH: undefined,
    MIKUY_ENVIRONMENT_STATE: undefined,
    MIKUY_LOGICAL_ENVIRONMENT: undefined,
    MIKUY_EXPECTED_SUPABASE_PROJECT_REF: undefined,
    MIKUY_DEV_SUPABASE_PROJECT_REF: undefined,
  })
  assert.equal(validateEnvironmentConfiguration(local, DEV_REF).context, 'local')
  assertCode('PROJECT_REF_MISMATCH', () => validateEnvironmentConfiguration({
    ...local,
    VITE_SUPABASE_URL: `https://${PROD_REF}.supabase.co`,
  }, DEV_REF))
})

test('extrae el project ref solo desde una URL Supabase HTTPS reconocible', () => {
  assert.equal(extractSupabaseProjectRef(`https://${DEV_REF}.supabase.co`), DEV_REF)
  assertCode('INVALID_SUPABASE_URL', () => extractSupabaseProjectRef(`http://${DEV_REF}.supabase.co`))
  assertCode('UNSUPPORTED_SUPABASE_HOST', () => extractSupabaseProjectRef('https://example.com'))
})
