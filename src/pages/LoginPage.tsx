import { useState, type FormEvent } from 'react'
import { useAuthentication } from '../components/AuthProvider'

function LoginPage() {
  const { state, signIn } = useAuthentication()
  const [email, setEmail] = useState('')
  const [password, setPassword] = useState('')
  const isSigningIn = state.operation === 'signing-in'

  async function submit(event: FormEvent<HTMLFormElement>): Promise<void> {
    event.preventDefault()
    if (isSigningIn) {
      return
    }

    const result = await signIn(email.trim(), password)
    if (!result.ok) {
      setPassword('')
    }
  }

  return (
    <main className="grid min-h-screen place-items-center overflow-x-hidden bg-stone-100 px-3 py-6 text-stone-900 sm:px-4 sm:py-8">
      <section className="w-full min-w-0 max-w-md rounded-3xl border border-stone-200 bg-white p-5 shadow-sm sm:p-9">
        <p className="text-sm font-semibold uppercase tracking-[0.18em] text-emerald-700">
          MikuyApp
        </p>
        <h1 className="mt-3 text-2xl font-bold tracking-tight sm:text-3xl">Inicia sesión</h1>
        <p className="mt-2 text-stone-600">Ingresa con tu cuenta autorizada.</p>

        <form className="mt-7 space-y-5" onSubmit={submit}>
          <label className="block">
            <span className="text-sm font-semibold text-stone-800">Correo electrónico</span>
            <input
              autoComplete="email"
              className="mt-2 min-h-12 w-full min-w-0 rounded-xl border border-stone-300 px-4 py-3 text-base outline-none focus:border-emerald-700"
              disabled={isSigningIn}
              onChange={(event) => setEmail(event.target.value)}
              required
              type="email"
              value={email}
            />
          </label>

          <label className="block">
            <span className="text-sm font-semibold text-stone-800">Contraseña</span>
            <input
              autoComplete="current-password"
              className="mt-2 min-h-12 w-full min-w-0 rounded-xl border border-stone-300 px-4 py-3 text-base outline-none focus:border-emerald-700"
              disabled={isSigningIn}
              onChange={(event) => setPassword(event.target.value)}
              required
              type="password"
              value={password}
            />
          </label>

          {state.message && (
            <p className="rounded-xl bg-rose-50 px-4 py-3 text-sm text-rose-800" role="alert">
              {state.message}
            </p>
          )}

          <button
            aria-busy={isSigningIn}
            className="min-h-12 w-full rounded-xl bg-emerald-800 px-4 py-3 font-semibold text-white hover:bg-emerald-900 disabled:cursor-not-allowed disabled:opacity-70"
            disabled={isSigningIn}
            type="submit"
          >
            {isSigningIn ? 'Iniciando sesión…' : 'Iniciar sesión'}
          </button>
        </form>
      </section>
    </main>
  )
}

export default LoginPage
