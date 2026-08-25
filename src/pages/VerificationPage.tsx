import type { RoleCode } from '../types/operations'

interface VerificationPageProps {
  readonly role: RoleCode
}

const roleNames: Record<RoleCode, string> = {
  ADMINISTRADOR: 'Administrador',
  MOZO: 'Mozo',
  COCINA: 'Cocina',
  CAJA: 'Caja',
}

const checks = [
  { label: 'Aplicación', value: 'Aplicación cargada', description: 'La interfaz React está disponible.' },
  { label: 'Sesión', value: 'Sesión autenticada', description: 'Supabase restauró una sesión válida.' },
  { label: 'Conexión', value: 'Conexión con Supabase disponible', description: 'El cliente público está inicializado y la sesión fue validada.' },
  { label: 'Configuración', value: 'Configuración pública disponible', description: 'Las variables públicas necesarias están configuradas.' },
] as const

function VerificationPage({ role }: VerificationPageProps) {
  return (
    <main className="min-h-screen overflow-x-hidden bg-stone-100 px-3 pb-8 pt-4 text-stone-900 sm:px-8 sm:pb-12">
      <div className="mx-auto w-full max-w-5xl">
        <header className="rounded-3xl bg-emerald-950 px-5 py-7 text-white shadow-sm sm:px-10 sm:py-10">
          <p className="text-sm font-semibold uppercase tracking-[0.18em] text-emerald-200">MikuyApp · Página técnica autenticada</p>
          <h1 className="mt-3 break-words text-3xl font-bold tracking-tight sm:text-5xl">Verificación técnica</h1>
          <p className="mt-3 max-w-2xl text-emerald-50">Estado mínimo de la aplicación y del acceso autenticado.</p>
        </header>

        <section aria-labelledby="technical-status-title" className="mt-6 rounded-3xl border border-stone-200 bg-white p-5 shadow-sm sm:p-8">
          <div className="flex min-w-0 flex-col gap-3 sm:flex-row sm:items-center sm:justify-between">
            <div className="min-w-0">
              <p className="text-sm font-semibold uppercase tracking-wide text-emerald-700">Acceso habilitado</p>
              <h2 className="mt-2 break-words text-2xl font-bold" id="technical-status-title">Verificaciones disponibles</h2>
            </div>
            <span className="w-fit rounded-full bg-emerald-100 px-4 py-2 text-sm font-semibold text-emerald-900">Rol: {roleNames[role]}</span>
          </div>

          <ul className="mt-6 grid min-w-0 gap-4 sm:grid-cols-2">
            {checks.map((check) => (
              <li className="min-w-0 break-words rounded-2xl border border-stone-200 p-4 sm:p-5" key={check.label}>
                <p className="text-sm font-medium text-stone-500">{check.label}</p>
                <p className="mt-2 font-semibold text-emerald-900">{check.value}</p>
                <p className="mt-2 text-sm text-stone-600">{check.description}</p>
              </li>
            ))}
          </ul>
        </section>
      </div>
    </main>
  )
}

export default VerificationPage
