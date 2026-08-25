import type { SupabaseClient } from '@supabase/supabase-js'
import type { ValidatedProfileContext } from './profileContext'

export interface CatalogCategory {
  readonly id: string
  readonly codigo: string
  readonly nombre: string
  readonly orden: number
  readonly activo: boolean
}

export interface CatalogProduct {
  readonly id: string
  readonly categoria_id: string
  readonly codigo: string
  readonly nombre: string
  readonly precio: number
  readonly activo: boolean
}

export interface CatalogGroup {
  readonly category: CatalogCategory
  readonly products: readonly CatalogProduct[]
}

export interface AdministrativeCatalog {
  readonly categories: readonly CatalogCategory[]
  readonly products: readonly CatalogProduct[]
  readonly groups: readonly CatalogGroup[]
}

export interface OperationalCatalog {
  readonly groups: readonly CatalogGroup[]
}

export interface CatalogError {
  readonly kind: 'connection-error' | 'authorization-error'
  readonly message: string
  readonly recoverable: boolean
}

export type CatalogResult<T> =
  | { readonly ok: true; readonly data: T }
  | { readonly ok: false; readonly error: CatalogError }

export interface CatalogService {
  readonly getAdministrativeCatalog: (
    context: ValidatedProfileContext,
  ) => Promise<CatalogResult<AdministrativeCatalog>>
  readonly getOperationalCatalog: (
    context: ValidatedProfileContext,
  ) => Promise<CatalogResult<OperationalCatalog>>
}

type CatalogClient = Pick<SupabaseClient, 'from'>

const categoryColumns = 'id,codigo,nombre,orden,activo'
const productColumns = 'id,categoria_id,codigo,nombre,precio,activo'
const connectionErrorMessage =
  'No pudimos cargar el catálogo. Revisa tu conexión e intenta nuevamente.'
const authorizationErrorMessage = 'No tienes autorización para consultar el catálogo administrativo.'

const nameCollator = new Intl.Collator('es', {
  numeric: true,
  sensitivity: 'base',
})

function connectionError(): CatalogError {
  return {
    kind: 'connection-error',
    message: connectionErrorMessage,
    recoverable: true,
  }
}

function compareNames(
  left: Pick<CatalogCategory | CatalogProduct, 'nombre' | 'codigo'>,
  right: Pick<CatalogCategory | CatalogProduct, 'nombre' | 'codigo'>,
): number {
  return nameCollator.compare(left.nombre, right.nombre)
    || nameCollator.compare(left.codigo, right.codigo)
}

function sortCategories(categories: readonly CatalogCategory[]): CatalogCategory[] {
  return [...categories].sort((left, right) => left.orden - right.orden || compareNames(left, right))
}

function sortProducts(products: readonly CatalogProduct[]): CatalogProduct[] {
  return [...products].sort(compareNames)
}

function groupProducts(
  categories: readonly CatalogCategory[],
  products: readonly CatalogProduct[],
  omitEmptyGroups: boolean,
): CatalogGroup[] {
  const productsByCategory = new Map<string, CatalogProduct[]>()

  for (const product of products) {
    const categoryProducts = productsByCategory.get(product.categoria_id) ?? []
    categoryProducts.push(product)
    productsByCategory.set(product.categoria_id, categoryProducts)
  }

  return categories.flatMap((category) => {
    const categoryProducts = productsByCategory.get(category.id) ?? []
    if (omitEmptyGroups && categoryProducts.length === 0) {
      return []
    }

    return [{ category, products: categoryProducts }]
  })
}

export function createCatalogService(client: CatalogClient): CatalogService {
  async function queryCatalog(
    context: ValidatedProfileContext,
    operational: boolean,
  ): Promise<CatalogResult<AdministrativeCatalog>> {
    try {
      let categoryQuery = client
        .from('categoria')
        .select(categoryColumns)
        .eq('local_id', context.local.id)

      let productQuery = client
        .from('producto')
        .select(productColumns)
        .eq('local_id', context.local.id)

      if (operational) {
        categoryQuery = categoryQuery.eq('activo', true)
        productQuery = productQuery.eq('activo', true)
      }

      const [categoriesResult, productsResult] = await Promise.all([
        categoryQuery
          .order('orden', { ascending: true })
          .order('nombre', { ascending: true })
          .returns<CatalogCategory[]>(),
        productQuery
          .order('nombre', { ascending: true })
          .order('codigo', { ascending: true })
          .returns<CatalogProduct[]>(),
      ])

      if (categoriesResult.error || productsResult.error) {
        return { ok: false, error: connectionError() }
      }

      const returnedCategories = categoriesResult.data ?? []
      const categories = sortCategories(
        operational
          ? returnedCategories.filter((category) => category.activo)
          : returnedCategories,
      )
      const allowedCategoryIds = new Set(categories.map((category) => category.id))
      const products = sortProducts(
        (productsResult.data ?? []).filter((product) =>
          allowedCategoryIds.has(product.categoria_id)
          && (!operational || product.activo),
        ),
      )

      return {
        ok: true,
        data: {
          categories,
          products,
          groups: groupProducts(categories, products, operational),
        },
      }
    } catch {
      return { ok: false, error: connectionError() }
    }
  }

  return {
    async getAdministrativeCatalog(context) {
      if (context.role.codigo !== 'ADMINISTRADOR') {
        return {
          ok: false,
          error: {
            kind: 'authorization-error',
            message: authorizationErrorMessage,
            recoverable: false,
          },
        }
      }

      return queryCatalog(context, false)
    },

    async getOperationalCatalog(context) {
      const result = await queryCatalog(context, true)
      if (!result.ok) {
        return result
      }

      return {
        ok: true,
        data: { groups: result.data.groups },
      }
    },
  }
}
