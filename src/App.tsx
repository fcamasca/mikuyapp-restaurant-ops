import { AuthProvider, useAuthentication } from './components/AuthProvider'
import LoginPage from './pages/LoginPage'

function AuthenticationScreen() {
  const { state, profileContext, retryProfileContext, signOut } = useAuthentication()

  if (state.status === 'loading') {
    return (
      <main className="grid min-h-screen place-items-center bg-stone-100 px-4 text-stone-900">
        <section aria-busy="true" aria-live="polite" className="rounded-2xl bg-white p-7 shadow-sm">
          <h1 className="text-xl font-semibold">Restaurando tu sesión…</h1>
          <p className="mt-2 text-stone-600">Estamos comprobando la conexión con Supabase.</p>
        </section>
      </main>
    )
  }

  if (state.status !== 'authenticated') {
    return <LoginPage />
  }

  if (profileContext.status === 'idle' || profileContext.status === 'loading') {
    return (
      <main className="grid min-h-screen place-items-center bg-stone-100 px-4 text-stone-900">
        <section aria-busy="true" aria-live="polite" className="rounded-2xl bg-white p-7 shadow-sm">
          <h1 className="text-xl font-semibold">Verificando tu acceso…</h1>
          <p className="mt-2 text-stone-600">Estamos comprobando tu cuenta autorizada.</p>
        </section>
      </main>
    )
  }

  if (profileContext.status === 'invalid' || profileContext.status === 'error') {
    return (
      <main className="grid min-h-screen place-items-center bg-stone-100 px-4 text-stone-900">
        <section className="w-full max-w-md rounded-3xl border border-stone-200 bg-white p-7 shadow-sm">
          <p className="text-sm font-semibold uppercase tracking-[0.18em] text-emerald-700">MikuyApp</p>
          <h1 className="mt-3 text-2xl font-bold">
            {profileContext.status === 'invalid' ? 'Acceso no habilitado' : 'No pudimos verificar tu acceso'}
          </h1>
          <p className="mt-3 text-stone-600" role="alert">{profileContext.message}</p>
          <div className="mt-6 flex flex-wrap gap-3">
            {profileContext.status === 'error' && (
              <button
                className="rounded-xl bg-emerald-800 px-4 py-3 font-semibold text-white hover:bg-emerald-900"
                onClick={() => { void retryProfileContext() }}
                type="button"
              >
                Reintentar
              </button>
            )}
            <button
              className="rounded-xl border border-stone-300 px-4 py-3 font-semibold text-stone-800"
              onClick={() => { void signOut() }}
              type="button"
            >
              Cerrar sesión
            </button>
          </div>
        </section>
      </main>
    )
  }

  const isSigningOut = state.operation === 'signing-out'

  return (
    <main className="grid min-h-screen place-items-center bg-stone-100 px-4 text-stone-900">
      <section className="w-full max-w-md rounded-3xl border border-stone-200 bg-white p-7 shadow-sm">
        <p className="text-sm font-semibold uppercase tracking-[0.18em] text-emerald-700">MikuyApp</p>
        <h1 className="mt-3 text-2xl font-bold">Acceso verificado</h1>
        <p className="mt-2 text-stone-600">Tu sesión y cuenta autorizada están disponibles.</p>
        {state.message && <p className="mt-4 text-sm text-rose-800" role="alert">{state.message}</p>}
        <button
          aria-busy={isSigningOut}
          className="mt-6 rounded-xl bg-emerald-800 px-4 py-3 font-semibold text-white hover:bg-emerald-900 disabled:opacity-70"
          disabled={isSigningOut}
          onClick={() => { void signOut() }}
          type="button"
        >
          {isSigningOut ? 'Cerrando sesión…' : 'Cerrar sesión'}
        </button>
      </section>
    </main>
  )
}

function App() {
  return (
    <AuthProvider>
      <AuthenticationScreen />
    </AuthProvider>
  )
}

export default App
