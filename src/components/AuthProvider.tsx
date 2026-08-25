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
import {
  createProfileContextController,
  type ProfileContextController,
  type ProfileContextState,
} from '../services/profileContext'
import { getSupabaseClient } from '../services/supabaseClient'

interface AuthenticationContextValue {
  readonly state: AuthenticationState
  readonly profileContext: ProfileContextState
  readonly signIn: AuthenticationController['signIn']
  readonly signOut: AuthenticationController['signOut']
  readonly retryProfileContext: ProfileContextController['retry']
}

const AuthenticationContext = createContext<AuthenticationContextValue | null>(null)

const configurationErrorState: AuthenticationState = {
  status: 'error',
  session: null,
  operation: 'idle',
  message: 'La conexión con Supabase no está configurada correctamente.',
}

const emptyProfileContext: ProfileContextState = {
  status: 'idle',
  context: null,
  message: null,
}

function AuthenticationProviderContent({
  controller,
  profileController,
  children,
}: {
  readonly controller: AuthenticationController
  readonly profileController: ProfileContextController
  readonly children: ReactNode
}) {
  const state = useSyncExternalStore(controller.subscribe, controller.getSnapshot)
  const profileContext = useSyncExternalStore(
    profileController.subscribe,
    profileController.getSnapshot,
  )

  useEffect(() => {
    void controller.initialize()
    return () => {
      controller.dispose()
    }
  }, [controller])

  useEffect(() => {
    if (state.status === 'authenticated' && state.session) {
      void profileController.load(state.session)
      return () => {
        profileController.clear()
      }
    }

    profileController.clear()
    return undefined
  }, [profileController, state.session, state.status])

  const value = useMemo<AuthenticationContextValue>(
    () => ({
      state,
      profileContext,
      signIn: controller.signIn,
      signOut: controller.signOut,
      retryProfileContext: profileController.retry,
    }),
    [controller, profileContext, profileController, state],
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
  const profileController = useMemo(
    () => result.ok ? createProfileContextController(result.client) : null,
    [result],
  )

  if (!controller || !profileController) {
    return (
      <AuthenticationContext.Provider
        value={{
          state: configurationErrorState,
          profileContext: emptyProfileContext,
          signIn: async () => ({ ok: false }),
          signOut: async () => ({ ok: false }),
          retryProfileContext: async () => {},
        }}
      >
        {children}
      </AuthenticationContext.Provider>
    )
  }

  return (
    <AuthenticationProviderContent controller={controller} profileController={profileController}>
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
