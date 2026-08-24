import type {
  DemoCatalogCategory,
  DemoCatalogConnectionError,
  DemoCatalogLocal,
  DemoCatalogProduct,
  DemoCatalogQuerySource,
  DemoCatalogResult,
  DemoCatalogTable,
} from '../types/demoCatalog'
import { getSupabaseClient } from './supabaseClient'

const CONNECTION_ERROR_MESSAGE = 'No fue posible consultar los datos demo.'

function connectionError(source: DemoCatalogQuerySource): DemoCatalogConnectionError {
  return {
    kind: 'connection-error',
    source,
    message: CONNECTION_ERROR_MESSAGE,
  }
}

export async function getDemoCatalog(): Promise<DemoCatalogResult> {
  const clientResult = getSupabaseClient()
  if (!clientResult.ok) {
    return clientResult
  }

  const supabase = clientResult.client
  const [localsResult, tablesResult, categoriesResult, productsResult] = await Promise.all([
    supabase
      .from('local')
      .select('id,codigo,nombre')
      .eq('activo', true)
      .order('codigo')
      .returns<DemoCatalogLocal[]>(),
    supabase
      .from('mesa')
      .select('id,local_id,codigo,nombre,estado')
      .eq('activo', true)
      .order('codigo')
      .returns<DemoCatalogTable[]>(),
    supabase
      .from('categoria')
      .select('id,local_id,codigo,nombre,orden')
      .eq('activo', true)
      .order('orden')
      .order('codigo')
      .returns<DemoCatalogCategory[]>(),
    supabase
      .from('producto')
      .select('id,local_id,categoria_id,codigo,nombre,precio')
      .eq('activo', true)
      .order('categoria_id')
      .order('codigo')
      .returns<DemoCatalogProduct[]>(),
  ])

  const results = [
    ['local', localsResult],
    ['mesa', tablesResult],
    ['categoria', categoriesResult],
    ['producto', productsResult],
  ] as const

  for (const [source, result] of results) {
    if (result.error) {
      return { ok: false, error: connectionError(source) }
    }
  }

  return {
    ok: true,
    data: {
      locals: localsResult.data ?? [],
      tables: tablesResult.data ?? [],
      categories: categoriesResult.data ?? [],
      products: productsResult.data ?? [],
    },
  }
}
