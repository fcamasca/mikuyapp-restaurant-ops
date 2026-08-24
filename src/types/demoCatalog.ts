import type { SupabaseConfigurationError } from '../services/supabaseClient'

export interface DemoCatalogLocal {
  readonly id: string
  readonly codigo: string
  readonly nombre: string
}

export interface DemoCatalogTable {
  readonly id: string
  readonly local_id: string
  readonly codigo: string
  readonly nombre: string
  readonly estado: string
}

export interface DemoCatalogCategory {
  readonly id: string
  readonly local_id: string
  readonly codigo: string
  readonly nombre: string
  readonly orden: number
}

export interface DemoCatalogProduct {
  readonly id: string
  readonly local_id: string
  readonly categoria_id: string
  readonly codigo: string
  readonly nombre: string
  readonly precio: number
}

export interface DemoCatalog {
  readonly locals: readonly DemoCatalogLocal[]
  readonly tables: readonly DemoCatalogTable[]
  readonly categories: readonly DemoCatalogCategory[]
  readonly products: readonly DemoCatalogProduct[]
}

export type DemoCatalogQuerySource = 'local' | 'mesa' | 'categoria' | 'producto'

export interface DemoCatalogConnectionError {
  readonly kind: 'connection-error'
  readonly source: DemoCatalogQuerySource
  readonly message: string
}

export type DemoCatalogResult =
  | { readonly ok: true; readonly data: DemoCatalog }
  | { readonly ok: false; readonly error: SupabaseConfigurationError | DemoCatalogConnectionError }
