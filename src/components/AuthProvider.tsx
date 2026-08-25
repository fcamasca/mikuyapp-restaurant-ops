import {
  createContext,
  useContext,
  useEffect,
  useMemo,
  useSyncExternalStore,
  type ReactNode,
} from 'react'
import {
  createAuthenticationController,
  type AuthenticationController,
  type AuthenticationState,
} from '../services/authSession'
import { getSupabaseClient } from '../services/supabaseClient'

interface AuthenticationContextValue {
  readonly state: AuthenticationState
  readonly signIn: AuthenticationController['signIn']
  readonly signOut: AuthenticationController['signOut']
}

const AuthenticationContext = createContext<AuthenticationContextValue | null>(null)

const configurationErrorState: AuthenticationState = {
  status: 'error',
  session: null,
  operation: 'idle',
  message: 'La conexión con Supabase no está configurada correctamente.',
}

function AuthenticationProviderContent({
  controller,
  children,
}: {
  readonly controller: AuthenticationController
  readonly children: ReactNode
}) {
  const state = useSyncExternalStore(controller.subscribe, controller.getSnapshot)

  useEffect(() => {
    void controller.initialize()
    return () => {
      controller.dispose()
    }
  }, [controller])

  const value = useMemo<AuthenticationContextValue>(
    () => ({ state, signIn: controller.signIn, signOut: controller.signOut }),
    [controller, state],
  )

  return (
    <AuthenticationContext.Provider value={value}>
      {children}
    </AuthenticationContext.Provider>
  )
}

export function AuthProvider({ children }: { readonly children: ReactNode }) {
  const result = useMemo(() => getSupabaseClient(), [])
  const controller = useMemo(
    () => result.ok ? createAuthenticationController(result.client) : null,
    [result],
  )

  if (!controller) {
    return (
      <AuthenticationContext.Provider
        value={{
          state: configurationErrorState,
          signIn: async () => ({ ok: false }),
          signOut: async () => ({ ok: false }),
        }}
      >
        {children}
      </AuthenticationContext.Provider>
    )
  }

  return (
    <AuthenticationProviderContent controller={controller}>
      {children}
    </AuthenticationProviderContent>
  )
}

export function useAuthentication(): AuthenticationContextValue {
  const context = useContext(AuthenticationContext)
  if (!context) {
    throw new Error('La autenticación no está disponible.')
  }
  return context
}
