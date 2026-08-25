import { useEffect, useMemo, useState } from 'react'
import {
  createCatalogService,
  type CatalogTable,
  type OperationalCatalog,
} from '../services/catalogService'
import type { ValidatedProfileContext } from '../services/profileContext'
import { getSupabaseClient } from '../services/supabaseClient'
import type { TableStatusCode } from '../types/operations'

interface WaiterTablesPageProps {
  readonly context: ValidatedProfileContext
  readonly isSigningOut: boolean
  readonly onSignOut: () => void
  readonly onNavigateToTechnical: () => void
}

const tableStatuses: Record<TableStatusCode, {
  readonly label: string
  readonly description: string
  readonly className: string
}> = {
  LIBRE: {
    label: 'Libre',
    description: 'Mesa disponible',
    className: 'border-emerald-200 bg-emerald-50 text-emerald-900',
  },
  OCUPADA: {
    label: 'Ocupada',
    description: 'Mesa en atención',
    className: 'border-amber-200 bg-amber-50 text-amber-900',
  },
  PEDIDO_LISTO: {
    label: 'Pedido listo',
    description: 'Pedido preparado para entregar',
    className: 'border-sky-200 bg-sky-50 text-sky-900',
  },
  PENDIENTE_PAGO: {
    label: 'Pendiente de pago',
    description: 'Mesa pendiente de cobro',
    className: 'border-violet-200 bg-violet-50 text-violet-900',
  },
}

const priceFormatter = new Intl.NumberFormat('es-PE', {
  style: 'currency',
  currency: 'PEN',
})

export default function WaiterTablesPage({
  context,
  isSigningOut,
  onSignOut,
  onNavigateToTechnical,
}: WaiterTablesPageProps) {
  const clientResult = useMemo(() => getSupabaseClient(), [])
  const service = useMemo(
    () => clientResult.ok ? createCatalogService(clientResult.client) : null,
    [clientResult],
  )
  const [tables, setTables] = useState<readonly CatalogTable[]>([])
  const [catalog, setCatalog] = useState<OperationalCatalog | null>(null)
  const [tablesLoading, setTablesLoading] = useState(true)
  const [catalogLoading, setCatalogLoading] = useState(true)
  const [tablesError, setTablesError] = useState<string | null>(null)
  const [catalogError, setCatalogError] = useState<string | null>(null)
  const [tablesAttempt, setTablesAttempt] = useState(0)
  const [catalogAttempt, setCatalogAttempt] = useState(0)

  useEffect(() => {
    let cancelled = false

    async function loadTables(): Promise<void> {
      setTablesLoading(true)
      setTablesError(null)

      if (!service) {
        setTablesLoading(false)
        setTablesError('No pudimos cargar las mesas. Intenta nuevamente.')
        return
      }

      const result = await service.getOperationalTables(context)
      if (cancelled) return

      setTablesLoading(false)
      if (!result.ok) {
        setTables([])
        setTablesError(result.error.message)
        return
      }

      setTables(result.data)
    }

    void loadTables()
    return () => { cancelled = true }
  }, [context, service, tablesAttempt])

  useEffect(() => {
    let cancelled = false

    async function loadCatalog(): Promise<void> {
      setCatalogLoading(true)
      setCatalogError(null)

      if (!service) {
        setCatalogLoading(false)
        setCatalogError('No pudimos cargar la carta. Intenta nuevamente.')
        return
      }

      const result = await service.getOperationalCatalog(context)
      if (cancelled) return

      setCatalogLoading(false)
      if (!result.ok) {
        setCatalog(null)
        setCatalogError(result.error.message)
        return
      }

      setCatalog(result.data)
    }

    void loadCatalog()
    return () => { cancelled = true }
  }, [catalogAttempt, context, service])

  return (
    <main className="min-h-screen overflow-x-hidden bg-stone-100 px-3 py-5 text-stone-900 sm:px-6 sm:py-8 lg:px-8">
      <div className="mx-auto max-w-6xl">
        <header className="flex min-w-0 flex-col items-start justify-between gap-4 sm:flex-row">
          <div className="min-w-0">
            <p className="text-sm font-semibold uppercase tracking-[0.18em] text-emerald-700">
              MikuyApp · Atención de mesas
            </p>
            <h1 className="mt-2 break-words text-2xl font-bold tracking-tight sm:text-3xl">Mesas y carta disponible</h1>
            <p className="mt-2 text-sm text-stone-600">
              Consulta las mesas activas y los productos disponibles de tu local.
            </p>
          </div>
          <nav className="flex w-full flex-wrap gap-3 sm:w-auto">
            <button
              className="min-h-11 flex-1 rounded-xl border border-stone-300 bg-white px-4 py-3 text-sm font-semibold sm:flex-none"
              onClick={onNavigateToTechnical}
              type="button"
            >
              Verificación técnica
            </button>
            <button
              aria-busy={isSigningOut}
              className="min-h-11 flex-1 rounded-xl bg-emerald-800 px-4 py-3 text-sm font-semibold text-white disabled:opacity-70 sm:flex-none"
              disabled={isSigningOut}
              onClick={onSignOut}
              type="button"
            >
              {isSigningOut ? 'Cerrando sesión…' : 'Cerrar sesión'}
            </button>
          </nav>
        </header>

        <section aria-labelledby="waiter-tables-title" className="mt-8 min-w-0 rounded-3xl border border-stone-200 bg-white p-4 shadow-sm sm:p-6">
          <h2 className="text-xl font-semibold" id="waiter-tables-title">Tablero de mesas</h2>
          <p className="mt-2 text-sm text-stone-600">Estados de las mesas activas de tu local.</p>

          <ul aria-label="Leyenda de estados de mesas" className="mt-5 grid min-w-0 gap-3 sm:grid-cols-2 lg:grid-cols-4">
            {Object.entries(tableStatuses).map(([code, status]) => (
              <li
                className={`min-w-0 break-words rounded-xl border px-3 py-2 text-sm ${status.className}`}
                key={code}
              >
                <span className="font-semibold">{status.label}:</span> {status.description}
              </li>
            ))}
          </ul>

          {tablesLoading ? (
            <p aria-busy="true" className="mt-6 text-sm text-stone-600">Cargando mesas…</p>
          ) : tablesError ? (
            <div className="mt-6 rounded-2xl border border-rose-200 bg-rose-50 p-4">
              <p className="text-sm text-rose-800" role="alert">{tablesError}</p>
              <button
                className="mt-3 min-h-11 w-full rounded-lg border border-rose-300 px-3 py-2 text-sm font-semibold text-rose-900 sm:w-auto"
                onClick={() => setTablesAttempt((attempt) => attempt + 1)}
                type="button"
              >
                Reintentar mesas
              </button>
            </div>
          ) : tables.length === 0 ? (
            <p className="mt-6 rounded-2xl border border-dashed border-stone-300 p-4 text-sm text-stone-600">
              No hay mesas disponibles
            </p>
          ) : (
            <ul className="mt-6 grid gap-4 sm:grid-cols-2 xl:grid-cols-3">
              {tables.map((table) => {
                const status = tableStatuses[table.estado]
                return (
                  <li className={`min-w-0 break-words rounded-2xl border p-4 ${status.className}`} key={table.id}>
                    <p className="text-xs font-semibold uppercase tracking-wide">{table.codigo}</p>
                    <h3 className="mt-2 text-lg font-semibold">{table.nombre}</h3>
                    <p className="mt-3 text-sm font-medium">Estado: {status.label}</p>
                  </li>
                )
              })}
            </ul>
          )}
        </section>

        <section aria-labelledby="waiter-catalog-title" className="mt-6 min-w-0 rounded-3xl border border-stone-200 bg-white p-4 shadow-sm sm:p-6">
          <h2 className="text-xl font-semibold" id="waiter-catalog-title">Carta disponible</h2>
          <p className="mt-2 text-sm text-stone-600">Productos disponibles agrupados por categoría.</p>

          {catalogLoading ? (
            <p aria-busy="true" className="mt-6 text-sm text-stone-600">Cargando carta…</p>
          ) : catalogError ? (
            <div className="mt-6 rounded-2xl border border-rose-200 bg-rose-50 p-4">
              <p className="text-sm text-rose-800" role="alert">{catalogError}</p>
              <button
                className="mt-3 min-h-11 w-full rounded-lg border border-rose-300 px-3 py-2 text-sm font-semibold text-rose-900 sm:w-auto"
                onClick={() => setCatalogAttempt((attempt) => attempt + 1)}
                type="button"
              >
                Reintentar carta
              </button>
            </div>
          ) : !catalog?.groups.length ? (
            <p className="mt-6 rounded-2xl border border-dashed border-stone-300 p-4 text-sm text-stone-600">
              No hay productos disponibles
            </p>
          ) : (
            <div className="mt-6 space-y-6">
              {catalog.groups.map((group) => (
                <article className="min-w-0 rounded-2xl border border-stone-200 p-4" key={group.category.id}>
                  <h3 className="text-lg font-semibold text-stone-900">{group.category.nombre}</h3>
                  <ul className="mt-4 divide-y divide-stone-200">
                    {group.products.map((product) => (
                      <li className="flex min-w-0 flex-wrap items-center justify-between gap-3 py-3" key={product.id}>
                        <span className="min-w-0 break-words font-medium text-stone-800">{product.nombre}</span>
                        <span className="shrink-0 font-semibold text-emerald-800">
                          {priceFormatter.format(product.precio)}
                        </span>
                      </li>
                    ))}
                  </ul>
                </article>
              ))}
            </div>
          )}
        </section>
      </div>
    </main>
  )
}
