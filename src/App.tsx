import { AuthProvider, useAuthentication } from './components/AuthProvider'
import LoginPage from './pages/LoginPage'

function AuthenticationScreen() {
  const { state, signOut } = useAuthentication()

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

  const isSigningOut = state.operation === 'signing-out'

  return (
    <main className="grid min-h-screen place-items-center bg-stone-100 px-4 text-stone-900">
      <section className="w-full max-w-md rounded-3xl border border-stone-200 bg-white p-7 shadow-sm">
        <p className="text-sm font-semibold uppercase tracking-[0.18em] text-emerald-700">MikuyApp</p>
        <h1 className="mt-3 text-2xl font-bold">Sesión iniciada</h1>
        <p className="mt-2 text-stone-600">La autenticación con Supabase está disponible.</p>
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
