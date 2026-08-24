import { useCallback, useEffect, useState } from 'react'
import { getDemoCatalog } from '../services/demoCatalogService'
import type { DemoCatalog, DemoCatalogResult } from '../types/demoCatalog'

type VerificationState =
  | { readonly status: 'loading' }
  | { readonly status: 'success'; readonly catalog: DemoCatalog }
  | { readonly status: 'empty' }
  | { readonly status: 'configuration-error' }
  | { readonly status: 'connection-error' }

interface VerificationPageProps {
  readonly loadCatalog?: () => Promise<DemoCatalogResult>
}

const priceFormatter = new Intl.NumberFormat('es-PE', {
  style: 'currency',
  currency: 'PEN',
})

function hasDisplayableData(catalog: DemoCatalog): boolean {
  return catalog.locals.length > 0
    && catalog.tables.length > 0
    && catalog.categories.length > 0
    && catalog.products.length > 0
}

function VerificationPage({ loadCatalog = getDemoCatalog }: VerificationPageProps) {
  const [state, setState] = useState<VerificationState>({ status: 'loading' })
  const [requestNumber, setRequestNumber] = useState(0)

  const retry = useCallback(() => {
    setState({ status: 'loading' })
    setRequestNumber((current) => current + 1)
  }, [])

  useEffect(() => {
    let isMounted = true

    async function load(): Promise<void> {
      const result = await loadCatalog()
      if (!isMounted) {
        return
      }

      if (!result.ok) {
        setState({ status: result.error.kind })
        return
      }

      setState(
        hasDisplayableData(result.data)
          ? { status: 'success', catalog: result.data }
          : { status: 'empty' },
      )
    }

    void load()

    return () => {
      isMounted = false
    }
  }, [loadCatalog, requestNumber])

  return (
    <main className="min-h-screen bg-stone-100 px-4 py-8 text-stone-900 sm:px-8 sm:py-12">
      <div className="mx-auto w-full max-w-6xl">
        <header className="mb-8 rounded-3xl bg-emerald-950 px-6 py-8 text-white shadow-sm sm:px-10 sm:py-10">
          <p className="text-sm font-semibold uppercase tracking-[0.18em] text-emerald-200">
            Hito H1 · Verificación técnica
          </p>
          <div className="mt-3 flex flex-col gap-3 sm:flex-row sm:items-end sm:justify-between">
            <div>
              <h1 className="text-4xl font-bold tracking-tight sm:text-5xl">MikuyApp</h1>
              <p className="mt-3 max-w-2xl text-base text-emerald-50 sm:text-lg">
                La aplicación React cargó correctamente.
              </p>
            </div>
            <span className="w-fit rounded-full bg-emerald-800 px-4 py-2 text-sm font-medium text-emerald-50">
              Aplicación activa
            </span>
          </div>
        </header>

        {state.status === 'loading' && (
          <section aria-live="polite" aria-busy="true" className="rounded-2xl border border-sky-200 bg-sky-50 p-6 shadow-sm">
            <p className="text-sm font-semibold uppercase tracking-wide text-sky-700">Conexión</p>
            <h2 className="mt-2 text-2xl font-semibold text-sky-950">Conectando con Supabase…</h2>
            <p className="mt-2 text-sky-800">Estamos consultando los datos demo activos.</p>
          </section>
        )}

        {state.status === 'configuration-error' && (
          <section role="alert" className="rounded-2xl border border-amber-300 bg-amber-50 p-6 shadow-sm">
            <p className="text-sm font-semibold uppercase tracking-wide text-amber-700">Configuración pendiente</p>
            <h2 className="mt-2 text-2xl font-semibold text-amber-950">Completa las variables públicas</h2>
            <p className="mt-3 text-amber-900">
              Configura <code className="font-semibold">VITE_SUPABASE_URL</code> y{' '}
              <code className="font-semibold">VITE_SUPABASE_PUBLISHABLE_KEY</code> en{' '}
              <code className="font-semibold">.env.local</code>, guarda el archivo y reinicia la aplicación.
            </p>
          </section>
        )}

        {state.status === 'connection-error' && (
          <section role="alert" className="rounded-2xl border border-rose-300 bg-rose-50 p-6 shadow-sm">
            <p className="text-sm font-semibold uppercase tracking-wide text-rose-700">Conexión no disponible</p>
            <h2 className="mt-2 text-2xl font-semibold text-rose-950">No pudimos consultar Supabase</h2>
            <p className="mt-3 text-rose-900">Verifica tu conexión e intenta nuevamente.</p>
            <button type="button" onClick={retry} className="mt-5 rounded-lg bg-rose-800 px-4 py-2 font-semibold text-white hover:bg-rose-900 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-rose-800">
              Reintentar
            </button>
          </section>
        )}

        {state.status === 'empty' && (
          <section role="status" className="rounded-2xl border border-stone-300 bg-white p-6 shadow-sm">
            <p className="text-sm font-semibold uppercase tracking-wide text-stone-500">Conexión correcta</p>
            <h2 className="mt-2 text-2xl font-semibold text-stone-900">Sin datos demo disponibles</h2>
            <p className="mt-3 text-stone-600">La conexión fue correcta, pero no hay datos demo activos para mostrar.</p>
          </section>
        )}

        {state.status === 'success' && <CatalogContent catalog={state.catalog} />}
      </div>
    </main>
  )
}

function CatalogContent({ catalog }: { readonly catalog: DemoCatalog }) {
  const local = catalog.locals[0]
  const categoryNames = new Map(catalog.categories.map((category) => [category.id, category.nombre]))

  return (
    <div className="space-y-8">
      <section aria-live="polite" className="rounded-2xl border border-emerald-200 bg-emerald-50 p-6 shadow-sm">
        <p className="text-sm font-semibold uppercase tracking-wide text-emerald-700">Conexión</p>
        <h2 className="mt-2 text-2xl font-semibold text-emerald-950">Conexión con Supabase correcta</h2>
        <p className="mt-3 text-emerald-900">Local conectado: <strong>{local.nombre}</strong> · {local.codigo}</p>
      </section>

      <section aria-labelledby="summary-title">
        <h2 id="summary-title" className="text-2xl font-bold">Resumen de datos activos</h2>
        <div className="mt-4 grid grid-cols-1 gap-4 sm:grid-cols-3">
          {[
            ['Mesas', catalog.tables.length],
            ['Categorías', catalog.categories.length],
            ['Productos', catalog.products.length],
          ].map(([label, count]) => (
            <article key={label} className="rounded-2xl border border-stone-200 bg-white p-5 shadow-sm">
              <p className="text-sm font-medium text-stone-500">{label}</p>
              <p className="mt-2 text-4xl font-bold text-emerald-800">{count}</p>
            </article>
          ))}
        </div>
      </section>

      <div className="grid grid-cols-1 gap-8 lg:grid-cols-2">
        <section aria-labelledby="tables-title" className="min-w-0 rounded-2xl border border-stone-200 bg-white p-6 shadow-sm">
          <h2 id="tables-title" className="text-xl font-bold">Mesas activas</h2>
          <ul className="mt-4 grid grid-cols-1 gap-3 sm:grid-cols-2">
            {catalog.tables.map((table) => (
              <li key={table.id} className="rounded-xl bg-stone-100 p-4">
                <div className="flex items-start justify-between gap-3">
                  <div className="min-w-0">
                    <p className="font-semibold">{table.nombre}</p>
                    <p className="text-sm text-stone-500">{table.codigo}</p>
                  </div>
                  <span className="shrink-0 rounded-full bg-emerald-100 px-3 py-1 text-xs font-semibold text-emerald-800">{table.estado}</span>
                </div>
              </li>
            ))}
          </ul>
        </section>

        <section aria-labelledby="categories-title" className="min-w-0 rounded-2xl border border-stone-200 bg-white p-6 shadow-sm">
          <h2 id="categories-title" className="text-xl font-bold">Categorías activas</h2>
          <ol className="mt-4 space-y-3">
            {catalog.categories.map((category) => (
              <li key={category.id} className="flex items-center gap-4 rounded-xl bg-stone-100 p-4">
                <span className="grid size-9 shrink-0 place-items-center rounded-full bg-amber-100 font-bold text-amber-900">{category.orden}</span>
                <span className="font-semibold">{category.nombre}</span>
              </li>
            ))}
          </ol>
        </section>
      </div>

      <section aria-labelledby="products-title" className="rounded-2xl border border-stone-200 bg-white p-6 shadow-sm">
        <h2 id="products-title" className="text-xl font-bold">Productos activos</h2>
        <ul className="mt-4 grid grid-cols-1 gap-4 sm:grid-cols-2 lg:grid-cols-3">
          {catalog.products.map((product) => (
            <li key={product.id} className="min-w-0 rounded-xl border border-stone-200 p-4">
              <p className="text-xs font-semibold uppercase tracking-wide text-stone-500">{categoryNames.get(product.categoria_id) ?? 'Categoría'}</p>
              <p className="mt-2 font-semibold text-stone-900">{product.nombre}</p>
              <p className="mt-3 text-lg font-bold text-emerald-800">{priceFormatter.format(product.precio)}</p>
            </li>
          ))}
        </ul>
      </section>
    </div>
  )
}

export default VerificationPage
