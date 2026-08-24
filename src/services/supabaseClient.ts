import { createClient, type SupabaseClient } from '@supabase/supabase-js'

export type SupabaseConfigurationErrorCode =
  | 'missing-url'
  | 'missing-publishable-key'
  | 'invalid-url'
  | 'client-initialization-failed'

export interface SupabaseConfigurationError {
  readonly kind: 'configuration-error'
  readonly code: SupabaseConfigurationErrorCode
  readonly message: string
}

export type SupabaseClientResult =
  | { readonly ok: true; readonly client: SupabaseClient }
  | { readonly ok: false; readonly error: SupabaseConfigurationError }

let client: SupabaseClient | undefined

export function getSupabaseClient(): SupabaseClientResult {
  if (client) {
    return { ok: true, client }
  }

  const url = import.meta.env.VITE_SUPABASE_URL?.trim()
  const publishableKey = import.meta.env.VITE_SUPABASE_PUBLISHABLE_KEY?.trim()

  if (!url) {
    return {
      ok: false,
      error: {
        kind: 'configuration-error',
        code: 'missing-url',
        message: 'Falta configurar la URL pública de Supabase.',
      },
    }
  }

  if (!publishableKey) {
    return {
      ok: false,
      error: {
        kind: 'configuration-error',
        code: 'missing-publishable-key',
        message: 'Falta configurar la Publishable key de Supabase.',
      },
    }
  }

  try {
    const parsedUrl = new URL(url)
    if (parsedUrl.protocol !== 'https:') {
      throw new Error('Supabase requires HTTPS')
    }
  } catch {
    return {
      ok: false,
      error: {
        kind: 'configuration-error',
        code: 'invalid-url',
        message: 'La URL pública de Supabase no es válida.',
      },
    }
  }

  try {
    client = createClient(url, publishableKey, {
      auth: {
        autoRefreshToken: false,
        detectSessionInUrl: false,
        persistSession: false,
      },
    })
    return { ok: true, client }
  } catch {
    return {
      ok: false,
      error: {
        kind: 'configuration-error',
        code: 'client-initialization-failed',
        message: 'No se pudo inicializar la conexión pública con Supabase.',
      },
    }
  }
}
