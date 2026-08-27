import { useEffect, useState } from 'react'
import { AuthProvider, useAuthentication } from './components/AuthProvider'
import AuthenticatedUserMenu from './components/AuthenticatedUserMenu'
import CategoryAdministrationPage from './pages/CategoryAdministrationPage'
import LoginPage from './pages/LoginPage'
import VerificationPage from './pages/VerificationPage'
import WaiterOrderPage from './pages/WaiterOrderPage'
import WaiterTablesPage from './pages/WaiterTablesPage'
import { getRoleDestination, getWaiterOrderId, resolveApplicationRoute, type ApplicationRoute } from './services/appRoutes'

function LoadingScreen({ context = false }: { readonly context?: boolean }) {
  return (
    <main className="grid min-h-screen place-items-center bg-stone-100 px-4 text-stone-900">
      <section aria-busy="true" aria-live="polite" className="rounded-2xl bg-white p-7 shadow-sm">
        <h1 className="text-xl font-semibold">
          {context ? 'Verificando tu acceso…' : 'Restaurando tu sesión…'}
        </h1>
        <p className="mt-2 text-stone-600">
          {context ? 'Estamos comprobando tu cuenta autorizada.' : 'Estamos comprobando la conexión con Supabase.'}
        </p>
      </section>
    </main>
  )
}

function ApplicationRouter() {
  const { state, profileContext, retryProfileContext, signOut } = useAuthentication()
  const [pathname, setPathname] = useState(() => window.location.pathname)
  const role = profileContext.context?.role.codigo ?? null
  const resolution = resolveApplicationRoute({
    pathname,
    authenticationStatus: state.status,
    contextStatus: profileContext.status,
    role,
  })

  useEffect(() => {
    function updatePathname(): void {
      setPathname(window.location.pathname)
    }

    window.addEventListener('popstate', updatePathname)
    return () => {
      window.removeEventListener('popstate', updatePathname)
    }
  }, [])

  useEffect(() => {
    if (resolution.status === 'redirect' && pathname !== resolution.pathname) {
      window.history.replaceState(null, '', resolution.pathname)
      setPathname(resolution.pathname)
    }
  }, [pathname, resolution])

  function navigate(nextPathname: ApplicationRoute): void {
    if (nextPathname !== pathname) {
      window.history.pushState(null, '', nextPathname)
      setPathname(nextPathname)
    }
  }

  if (resolution.status === 'loading' || resolution.status === 'redirect') {
    return <LoadingScreen context={state.status === 'authenticated'} />
  }

  if (resolution.status === 'allowed' && resolution.pathname === '/login') {
    return <LoginPage />
  }

  if (resolution.status === 'invalid-context' || resolution.status === 'recoverable-error') {
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

  if (resolution.status !== 'allowed' || !role) {
    return <LoadingScreen context />
  }

  if (resolution.pathname === '/admin/catalogo') {
    if (!profileContext.context) {
      return <LoadingScreen context />
    }

    return (
      <CategoryAdministrationPage
        context={profileContext.context}
        isSigningOut={isSigningOut}
        onNavigateToTechnical={() => navigate('/tecnica')}
        onSignOut={() => { void signOut() }}
      />
    )
  }

  if (resolution.pathname === '/mozo/mesas') {
    if (!profileContext.context) {
      return <LoadingScreen context />
    }

    return (
      <WaiterTablesPage
        context={profileContext.context}
        isSigningOut={isSigningOut}
        onOpenOrder={(orderId) => navigate(`/mozo/pedidos/${orderId}`)}
        onNavigateToTechnical={() => navigate('/tecnica')}
        onSignOut={() => { void signOut() }}
      />
    )
  }

  const waiterOrderId = getWaiterOrderId(resolution.pathname)
  if (waiterOrderId !== null) {
    if (!profileContext.context) return <LoadingScreen context />
    return <WaiterOrderPage context={profileContext.context} isSigningOut={isSigningOut} orderId={waiterOrderId} onBack={() => navigate('/mozo/mesas')} onSignOut={() => { void signOut() }} />
  }

  if (resolution.pathname === '/tecnica') {
    if (!profileContext.context) return <LoadingScreen context />
    return (
      <>
        <nav className="flex items-center justify-end gap-3 bg-stone-100 px-4 pt-4 sm:px-8">
          {role !== 'COCINA' && role !== 'CAJA' && (
            <button
              className="rounded-lg border border-stone-300 px-4 py-2 text-sm font-semibold text-stone-800"
              onClick={() => navigate(getRoleDestination(role))}
              type="button"
            >
              Volver
            </button>
          )}
          <AuthenticatedUserMenu context={profileContext.context} isSigningOut={isSigningOut} onSignOut={() => { void signOut() }} />
        </nav>
        <VerificationPage role={role} />
      </>
    )
  }

  const isForbidden = resolution.pathname === '/403'
  const title = isForbidden
    ? 'Acceso no autorizado'
    : 'Tablero de mesas'
  const description = isForbidden
    ? 'Tu cuenta no tiene permiso para acceder a esta sección.'
    : 'Esta sección está disponible y sus funciones se incorporarán en tareas posteriores.'

  return (
    <main className="grid min-h-screen place-items-center overflow-x-hidden bg-stone-100 px-3 py-6 text-stone-900 sm:px-4">
      <section className="w-full min-w-0 max-w-md rounded-3xl border border-stone-200 bg-white p-5 shadow-sm sm:p-7">
        <p className="text-sm font-semibold uppercase tracking-[0.18em] text-emerald-700">MikuyApp</p>
        <h1 className="mt-3 text-2xl font-bold">{title}</h1>
        <p className="mt-2 text-stone-600">{description}</p>
        {profileContext.context && <div className="mt-5"><AuthenticatedUserMenu context={profileContext.context} isSigningOut={isSigningOut} onSignOut={() => { void signOut() }} /></div>}
        {state.message && <p className="mt-4 text-sm text-rose-800" role="alert">{state.message}</p>}
        <div className="mt-6 flex flex-col gap-3 sm:flex-row sm:flex-wrap">
          <button
            className="min-h-12 rounded-xl border border-stone-300 px-4 py-3 font-semibold text-stone-800"
            onClick={() => navigate(isForbidden ? getRoleDestination(role) : '/tecnica')}
            type="button"
          >
            {isForbidden ? 'Volver a mi sección' : 'Verificación técnica'}
          </button>
        </div>
      </section>
    </main>
  )
}

function App() {
  return (
    <AuthProvider>
      <ApplicationRouter />
    </AuthProvider>
  )
}

export default App
