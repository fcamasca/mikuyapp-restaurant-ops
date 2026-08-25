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
  readonly kind:
    | 'connection-error'
    | 'authorization-error'
    | 'validation-error'
    | 'duplicate-category-code'
    | 'category-has-products'
  readonly message: string
  readonly recoverable: boolean
}

export interface CategoryInput {
  readonly codigo: string
  readonly nombre: string
  readonly orden: number
  readonly activo: boolean
}

export interface CategoryMutation {
  readonly status: 'completed' | 'cancelled'
  readonly catalog: AdministrativeCatalog | null
  readonly message: string
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
  readonly createCategory: (
    context: ValidatedProfileContext,
    input: CategoryInput,
  ) => Promise<CatalogResult<CategoryMutation>>
  readonly updateCategory: (
    context: ValidatedProfileContext,
    categoryId: string,
    input: CategoryInput,
  ) => Promise<CatalogResult<CategoryMutation>>
  readonly setCategoryActive: (
    context: ValidatedProfileContext,
    categoryId: string,
    active: boolean,
  ) => Promise<CatalogResult<CategoryMutation>>
  readonly deleteCategory: (
    context: ValidatedProfileContext,
    categoryId: string,
    confirmed: boolean,
  ) => Promise<CatalogResult<CategoryMutation>>
}

type CatalogClient = Pick<SupabaseClient, 'from'>

const categoryColumns = 'id,codigo,nombre,orden,activo'
const productColumns = 'id,categoria_id,codigo,nombre,precio,activo'
const connectionErrorMessage =
  'No pudimos cargar el catálogo. Revisa tu conexión e intenta nuevamente.'
const authorizationErrorMessage = 'No tienes autorización para consultar el catálogo administrativo.'
const categoryAuthorizationMessage = 'La operación no está permitida para tu cuenta.'
const categoryMutationErrorMessage =
  'No pudimos completar la operación de categoría. Intenta nuevamente.'

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

function categoryAuthorizationError(): CatalogError {
  return {
    kind: 'authorization-error',
    message: categoryAuthorizationMessage,
    recoverable: false,
  }
}

function validateCategoryInput(input: CategoryInput): CatalogResult<CategoryInput> {
  const codigo = input.codigo.trim()
  const nombre = input.nombre.trim()

  if (!codigo) {
    return {
      ok: false,
      error: {
        kind: 'validation-error',
        message: 'Ingresa el código de la categoría.',
        recoverable: true,
      },
    }
  }

  if (!nombre) {
    return {
      ok: false,
      error: {
        kind: 'validation-error',
        message: 'Ingresa el nombre de la categoría.',
        recoverable: true,
      },
    }
  }

  if (!Number.isInteger(input.orden) || input.orden < 0) {
    return {
      ok: false,
      error: {
        kind: 'validation-error',
        message: 'El orden debe ser un número entero mayor o igual que cero.',
        recoverable: true,
      },
    }
  }

  return {
    ok: true,
    data: {
      codigo,
      nombre,
      orden: input.orden,
      activo: input.activo,
    },
  }
}

function categoryMutationError(error: { readonly code?: string }): CatalogError {
  if (error.code === '23505') {
    return {
      kind: 'duplicate-category-code',
      message: 'Ya existe una categoría con ese código.',
      recoverable: true,
    }
  }

  if (error.code === '23503') {
    return {
      kind: 'category-has-products',
      message: 'No se puede eliminar la categoría porque tiene productos relacionados; puedes desactivarla.',
      recoverable: true,
    }
  }

  if (error.code === '42501' || error.code === 'PGRST301') {
    return categoryAuthorizationError()
  }

  return {
    kind: 'connection-error',
    message: categoryMutationErrorMessage,
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

  async function completeCategoryMutation(
    context: ValidatedProfileContext,
    operation: PromiseLike<{
      readonly error: { readonly code?: string } | null
    }>,
    successMessage: string,
  ): Promise<CatalogResult<CategoryMutation>> {
    try {
      const result = await operation
      if (result.error) {
        return { ok: false, error: categoryMutationError(result.error) }
      }

      const catalog = await queryCatalog(context, false)
      if (!catalog.ok) {
        return catalog
      }

      return {
        ok: true,
        data: {
          status: 'completed',
          catalog: catalog.data,
          message: successMessage,
        },
      }
    } catch {
      return {
        ok: false,
        error: {
          kind: 'connection-error',
          message: categoryMutationErrorMessage,
          recoverable: true,
        },
      }
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

    async createCategory(context, input) {
      if (context.role.codigo !== 'ADMINISTRADOR') {
        return { ok: false, error: categoryAuthorizationError() }
      }

      const validated = validateCategoryInput(input)
      if (!validated.ok) {
        return validated
      }

      return completeCategoryMutation(
        context,
        client.from('categoria').insert({
          local_id: context.local.id,
          codigo: validated.data.codigo,
          nombre: validated.data.nombre,
          orden: validated.data.orden,
          activo: validated.data.activo,
        }),
        'La categoría se creó correctamente.',
      )
    },

    async updateCategory(context, categoryId, input) {
      if (context.role.codigo !== 'ADMINISTRADOR') {
        return { ok: false, error: categoryAuthorizationError() }
      }

      const validated = validateCategoryInput(input)
      if (!validated.ok) {
        return validated
      }

      return completeCategoryMutation(
        context,
        client
          .from('categoria')
          .update({
            codigo: validated.data.codigo,
            nombre: validated.data.nombre,
            orden: validated.data.orden,
            activo: validated.data.activo,
          })
          .eq('id', categoryId)
          .eq('local_id', context.local.id),
        'La categoría se actualizó correctamente.',
      )
    },

    async setCategoryActive(context, categoryId, active) {
      if (context.role.codigo !== 'ADMINISTRADOR') {
        return { ok: false, error: categoryAuthorizationError() }
      }

      return completeCategoryMutation(
        context,
        client
          .from('categoria')
          .update({ activo: active })
          .eq('id', categoryId)
          .eq('local_id', context.local.id),
        active
          ? 'La categoría se activó correctamente.'
          : 'La categoría se desactivó correctamente.',
      )
    },

    async deleteCategory(context, categoryId, confirmed) {
      if (!confirmed) {
        return {
          ok: true,
          data: {
            status: 'cancelled',
            catalog: null,
            message: 'La eliminación de la categoría fue cancelada.',
          },
        }
      }

      if (context.role.codigo !== 'ADMINISTRADOR') {
        return { ok: false, error: categoryAuthorizationError() }
      }

      return completeCategoryMutation(
        context,
        client
          .from('categoria')
          .delete()
          .eq('id', categoryId)
          .eq('local_id', context.local.id),
        'La categoría se eliminó correctamente.',
      )
    },
  }
}
