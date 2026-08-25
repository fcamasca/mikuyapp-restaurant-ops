import type { AuthChangeEvent, Session, SupabaseClient } from '@supabase/supabase-js'

export type AuthenticationStatus =
  | 'loading'
  | 'unauthenticated'
  | 'authenticated'
  | 'error'

export type AuthenticationOperation = 'idle' | 'signing-in' | 'signing-out'

export interface AuthenticationState {
  readonly status: AuthenticationStatus
  readonly session: Session | null
  readonly operation: AuthenticationOperation
  readonly message: string | null
}

export interface AuthenticationResult {
  readonly ok: boolean
}

export interface AuthenticationController {
  readonly getSnapshot: () => AuthenticationState
  readonly subscribe: (listener: () => void) => () => void
  readonly initialize: () => Promise<void>
  readonly signIn: (email: string, password: string) => Promise<AuthenticationResult>
  readonly signOut: () => Promise<AuthenticationResult>
  readonly dispose: () => void
}

type AuthenticationClient = Pick<SupabaseClient, 'auth'>

const initialState: AuthenticationState = {
  status: 'loading',
  session: null,
  operation: 'idle',
  message: null,
}

const connectionErrorMessage = 'No pudimos conectar con Supabase. Verifica tu conexión e intenta nuevamente.'
const invalidCredentialsMessage = 'El correo o la contraseña no son correctos.'

function isInvalidCredentials(error: unknown): boolean {
  if (!error || typeof error !== 'object') {
    return false
  }

  const candidate = error as { readonly code?: string; readonly status?: number }
  return candidate.code === 'invalid_credentials' || candidate.status === 400
}

export function createAuthenticationController(
  client: AuthenticationClient,
): AuthenticationController {
  let state = initialState
  let subscription: { unsubscribe: () => void } | undefined
  let active = false
  const listeners = new Set<() => void>()

  function publish(nextState: AuthenticationState): void {
    state = nextState
    for (const listener of listeners) {
      listener()
    }
  }

  function publishSession(session: Session | null): void {
    publish({
      status: session ? 'authenticated' : 'unauthenticated',
      session,
      operation: 'idle',
      message: null,
    })
  }

  return {
    getSnapshot: () => state,

    subscribe(listener) {
      listeners.add(listener)
      return () => {
        listeners.delete(listener)
      }
    },

    async initialize() {
      active = true
      publish(initialState)

      try {
        const result = client.auth.onAuthStateChange(
          (_event: AuthChangeEvent, session: Session | null) => {
            if (active) {
              publishSession(session)
            }
          },
        )
        subscription = result.data.subscription

        const { data, error } = await client.auth.getSession()
        if (!active) {
          return
        }

        if (error) {
          publish({ ...initialState, status: 'error', message: connectionErrorMessage })
          return
        }

        publishSession(data.session)
      } catch {
        if (active) {
          publish({ ...initialState, status: 'error', message: connectionErrorMessage })
        }
      }
    },

    async signIn(email, password) {
      publish({ ...state, operation: 'signing-in', message: null })

      try {
        const { data, error } = await client.auth.signInWithPassword({ email, password })
        if (error) {
          publish({
            status: 'error',
            session: null,
            operation: 'idle',
            message: isInvalidCredentials(error)
              ? invalidCredentialsMessage
              : connectionErrorMessage,
          })
          return { ok: false }
        }

        publishSession(data.session)
        return { ok: true }
      } catch {
        publish({ ...initialState, status: 'error', message: connectionErrorMessage })
        return { ok: false }
      }
    },

    async signOut() {
      publish({ ...state, operation: 'signing-out', message: null })

      try {
        const { error } = await client.auth.signOut()
        if (error) {
          publish({ ...state, operation: 'idle', message: connectionErrorMessage })
          return { ok: false }
        }

        publishSession(null)
        return { ok: true }
      } catch {
        publish({ ...state, operation: 'idle', message: connectionErrorMessage })
        return { ok: false }
      }
    },

    dispose() {
      active = false
      subscription?.unsubscribe()
      subscription = undefined
    },
  }
}
