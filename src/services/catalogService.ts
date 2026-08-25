import type { SupabaseClient } from '@supabase/supabase-js'
import type { ValidatedProfileContext } from './profileContext'
import type { TableStatusCode } from '../types/operations'

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

export interface CatalogTable {
  readonly id: string
  readonly codigo: string
  readonly nombre: string
  readonly estado: TableStatusCode
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
    | 'duplicate-product-code'
    | 'product-has-history'
    | 'invalid-product-category'
    | 'duplicate-table-code'
    | 'table-has-orders'
    | 'table-not-free'
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

export interface ProductInput {
  readonly categoria_id: string
  readonly codigo: string
  readonly nombre: string
  readonly precio: number
  readonly activo: boolean
}

export interface ProductMutation {
  readonly status: 'completed' | 'cancelled'
  readonly catalog: AdministrativeCatalog | null
  readonly message: string
}

export interface TableInput {
  readonly codigo: string
  readonly nombre: string
  readonly activo: boolean
}

export interface TableMutation {
  readonly status: 'completed' | 'cancelled'
  readonly tables: readonly CatalogTable[] | null
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
  readonly getAdministrativeTables: (
    context: ValidatedProfileContext,
  ) => Promise<CatalogResult<readonly CatalogTable[]>>
  readonly getOperationalTables: (
    context: ValidatedProfileContext,
  ) => Promise<CatalogResult<readonly CatalogTable[]>>
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
  readonly createProduct: (
    context: ValidatedProfileContext,
    input: ProductInput,
    availableCategories: readonly CatalogCategory[],
  ) => Promise<CatalogResult<ProductMutation>>
  readonly updateProduct: (
    context: ValidatedProfileContext,
    productId: string,
    input: ProductInput,
    availableCategories: readonly CatalogCategory[],
  ) => Promise<CatalogResult<ProductMutation>>
  readonly setProductActive: (
    context: ValidatedProfileContext,
    productId: string,
    active: boolean,
  ) => Promise<CatalogResult<ProductMutation>>
  readonly deleteProduct: (
    context: ValidatedProfileContext,
    productId: string,
    confirmed: boolean,
  ) => Promise<CatalogResult<ProductMutation>>
  readonly createTable: (
    context: ValidatedProfileContext,
    input: TableInput,
  ) => Promise<CatalogResult<TableMutation>>
  readonly updateTable: (
    context: ValidatedProfileContext,
    table: CatalogTable,
    input: TableInput,
  ) => Promise<CatalogResult<TableMutation>>
  readonly setTableActive: (
    context: ValidatedProfileContext,
    table: CatalogTable,
    active: boolean,
  ) => Promise<CatalogResult<TableMutation>>
  readonly deleteTable: (
    context: ValidatedProfileContext,
    table: CatalogTable,
    confirmed: boolean,
  ) => Promise<CatalogResult<TableMutation>>
}

type CatalogClient = Pick<SupabaseClient, 'from'>

const categoryColumns = 'id,codigo,nombre,orden,activo'
const productColumns = 'id,categoria_id,codigo,nombre,precio,activo'
const tableColumns = 'id,codigo,nombre,estado,activo'
const connectionErrorMessage =
  'No pudimos cargar el catálogo. Revisa tu conexión e intenta nuevamente.'
const authorizationErrorMessage = 'No tienes autorización para consultar el catálogo administrativo.'
const categoryAuthorizationMessage = 'La operación no está permitida para tu cuenta.'
const categoryMutationErrorMessage =
  'No pudimos completar la operación de categoría. Intenta nuevamente.'
const productMutationErrorMessage =
  'No pudimos completar la operación de producto. Intenta nuevamente.'
const tableMutationErrorMessage =
  'No pudimos completar la operación de mesa. Intenta nuevamente.'

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

function validateProductInput(
  input: ProductInput,
  availableCategories: readonly CatalogCategory[],
): CatalogResult<ProductInput> {
  const codigo = input.codigo.trim()
  const nombre = input.nombre.trim()
  const categoryId = input.categoria_id.trim()

  if (!codigo) {
    return {
      ok: false,
      error: {
        kind: 'validation-error',
        message: 'Ingresa el código del producto.',
        recoverable: true,
      },
    }
  }

  if (!nombre) {
    return {
      ok: false,
      error: {
        kind: 'validation-error',
        message: 'Ingresa el nombre del producto.',
        recoverable: true,
      },
    }
  }

  if (typeof input.precio !== 'number' || !Number.isFinite(input.precio) || input.precio < 0) {
    return {
      ok: false,
      error: {
        kind: 'validation-error',
        message: 'El precio debe ser un número mayor o igual que cero.',
        recoverable: true,
      },
    }
  }

  if (!categoryId) {
    return {
      ok: false,
      error: {
        kind: 'validation-error',
        message: 'Selecciona una categoría para el producto.',
        recoverable: true,
      },
    }
  }

  if (!availableCategories.some((category) => category.id === categoryId)) {
    return {
      ok: false,
      error: {
        kind: 'invalid-product-category',
        message: 'La categoría seleccionada no está disponible para tu local.',
        recoverable: true,
      },
    }
  }

  return {
    ok: true,
    data: {
      categoria_id: categoryId,
      codigo,
      nombre,
      precio: input.precio,
      activo: input.activo,
    },
  }
}

function productMutationError(
  error: { readonly code?: string },
  deleting: boolean,
): CatalogError {
  if (error.code === '23505') {
    return {
      kind: 'duplicate-product-code',
      message: 'Ya existe un producto con ese código.',
      recoverable: true,
    }
  }

  if (error.code === '23503') {
    return deleting
      ? {
        kind: 'product-has-history',
        message: 'No se puede eliminar el producto porque tiene pedidos relacionados; puedes desactivarlo.',
        recoverable: true,
      }
      : {
        kind: 'invalid-product-category',
        message: 'La categoría seleccionada no existe o no pertenece a tu local.',
        recoverable: true,
      }
  }

  if (error.code === '23514') {
    return {
      kind: 'validation-error',
      message: 'El precio debe ser un número mayor o igual que cero.',
      recoverable: true,
    }
  }

  if (error.code === '42501' || error.code === 'PGRST301') {
    return categoryAuthorizationError()
  }

  return {
    kind: 'connection-error',
    message: productMutationErrorMessage,
    recoverable: true,
  }
}

function tableNotFreeError(): CatalogError {
  return {
    kind: 'table-not-free',
    message: 'Solo puedes desactivar mesas libres.',
    recoverable: true,
  }
}

function validateTableInput(input: TableInput): CatalogResult<TableInput> {
  const codigo = input.codigo.trim()
  const nombre = input.nombre.trim()

  if (!codigo) {
    return {
      ok: false,
      error: {
        kind: 'validation-error',
        message: 'Ingresa el código de la mesa.',
        recoverable: true,
      },
    }
  }

  if (!nombre) {
    return {
      ok: false,
      error: {
        kind: 'validation-error',
        message: 'Ingresa el nombre de la mesa.',
        recoverable: true,
      },
    }
  }

  return {
    ok: true,
    data: { codigo, nombre, activo: input.activo },
  }
}

function tableMutationError(
  error: { readonly code?: string },
  table: CatalogTable | null,
  deactivating: boolean,
): CatalogError {
  if (error.code === '23505') {
    return {
      kind: 'duplicate-table-code',
      message: 'Ya existe una mesa con ese código.',
      recoverable: true,
    }
  }

  if (error.code === '23503') {
    return {
      kind: 'table-has-orders',
      message: table?.estado === 'LIBRE'
        ? 'No se puede eliminar la mesa porque tiene pedidos relacionados; puedes desactivarla.'
        : 'No se puede eliminar la mesa porque tiene pedidos relacionados.',
      recoverable: true,
    }
  }

  if (error.code === '42501' || error.code === 'PGRST301') {
    return deactivating ? tableNotFreeError() : categoryAuthorizationError()
  }

  return {
    kind: 'connection-error',
    message: tableMutationErrorMessage,
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

  async function queryAdministrativeTables(
    context: ValidatedProfileContext,
  ): Promise<CatalogResult<readonly CatalogTable[]>> {
    if (context.role.codigo !== 'ADMINISTRADOR') {
      return { ok: false, error: categoryAuthorizationError() }
    }

    try {
      const result = await client
        .from('mesa')
        .select(tableColumns)
        .eq('local_id', context.local.id)
        .order('codigo', { ascending: true })
        .order('nombre', { ascending: true })
        .returns<CatalogTable[]>()

      if (result.error) {
        return {
          ok: false,
          error: {
            kind: 'connection-error',
            message: 'No pudimos cargar las mesas. Revisa tu conexión e intenta nuevamente.',
            recoverable: true,
          },
        }
      }

      return { ok: true, data: result.data ?? [] }
    } catch {
      return {
        ok: false,
        error: {
          kind: 'connection-error',
          message: 'No pudimos cargar las mesas. Revisa tu conexión e intenta nuevamente.',
          recoverable: true,
        },
      }
    }
  }

  async function queryOperationalTables(
    context: ValidatedProfileContext,
  ): Promise<CatalogResult<readonly CatalogTable[]>> {
    if (context.role.codigo !== 'MOZO') {
      return { ok: false, error: categoryAuthorizationError() }
    }

    try {
      const result = await client
        .from('mesa')
        .select(tableColumns)
        .eq('local_id', context.local.id)
        .eq('activo', true)
        .order('codigo', { ascending: true })
        .order('nombre', { ascending: true })
        .returns<CatalogTable[]>()

      if (result.error) {
        return {
          ok: false,
          error: {
            kind: 'connection-error',
            message: 'No pudimos cargar las mesas. Revisa tu conexión e intenta nuevamente.',
            recoverable: true,
          },
        }
      }

      return {
        ok: true,
        data: (result.data ?? [])
          .filter((table) => table.activo)
          .sort((left, right) =>
            nameCollator.compare(left.codigo, right.codigo)
            || nameCollator.compare(left.nombre, right.nombre),
          ),
      }
    } catch {
      return {
        ok: false,
        error: {
          kind: 'connection-error',
          message: 'No pudimos cargar las mesas. Revisa tu conexión e intenta nuevamente.',
          recoverable: true,
        },
      }
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

  async function completeProductMutation(
    context: ValidatedProfileContext,
    operation: PromiseLike<{
      readonly error: { readonly code?: string } | null
    }>,
    successMessage: string,
    deleting = false,
  ): Promise<CatalogResult<ProductMutation>> {
    try {
      const result = await operation
      if (result.error) {
        return { ok: false, error: productMutationError(result.error, deleting) }
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
          message: productMutationErrorMessage,
          recoverable: true,
        },
      }
    }
  }

  async function completeTableMutation(
    context: ValidatedProfileContext,
    operation: PromiseLike<{
      readonly error: { readonly code?: string } | null
    }>,
    successMessage: string,
    table: CatalogTable | null,
    deactivating = false,
    createdCode: string | null = null,
  ): Promise<CatalogResult<TableMutation>> {
    try {
      const result = await operation
      if (result.error) {
        return { ok: false, error: tableMutationError(result.error, table, deactivating) }
      }

      const tables = await queryAdministrativeTables(context)
      if (!tables.ok) {
        return tables
      }

      if (createdCode) {
        const createdTable = tables.data.find((item) => item.codigo === createdCode)
        if (!createdTable || createdTable.estado !== 'LIBRE') {
          return {
            ok: false,
            error: {
              kind: 'table-not-free',
              message: 'No pudimos confirmar que la nueva mesa esté libre.',
              recoverable: true,
            },
          }
        }
      }

      return {
        ok: true,
        data: {
          status: 'completed',
          tables: tables.data,
          message: successMessage,
        },
      }
    } catch {
      return {
        ok: false,
        error: {
          kind: 'connection-error',
          message: tableMutationErrorMessage,
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

    getAdministrativeTables: queryAdministrativeTables,
    getOperationalTables: queryOperationalTables,

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

    async createProduct(context, input, availableCategories) {
      if (context.role.codigo !== 'ADMINISTRADOR') {
        return { ok: false, error: categoryAuthorizationError() }
      }

      const validated = validateProductInput(input, availableCategories)
      if (!validated.ok) {
        return validated
      }

      return completeProductMutation(
        context,
        client.from('producto').insert({
          local_id: context.local.id,
          categoria_id: validated.data.categoria_id,
          codigo: validated.data.codigo,
          nombre: validated.data.nombre,
          precio: validated.data.precio,
          activo: validated.data.activo,
        }),
        'El producto se creó correctamente.',
      )
    },

    async updateProduct(context, productId, input, availableCategories) {
      if (context.role.codigo !== 'ADMINISTRADOR') {
        return { ok: false, error: categoryAuthorizationError() }
      }

      const validated = validateProductInput(input, availableCategories)
      if (!validated.ok) {
        return validated
      }

      return completeProductMutation(
        context,
        client
          .from('producto')
          .update({
            categoria_id: validated.data.categoria_id,
            codigo: validated.data.codigo,
            nombre: validated.data.nombre,
            precio: validated.data.precio,
            activo: validated.data.activo,
          })
          .eq('id', productId)
          .eq('local_id', context.local.id),
        'El producto se actualizó correctamente.',
      )
    },

    async setProductActive(context, productId, active) {
      if (context.role.codigo !== 'ADMINISTRADOR') {
        return { ok: false, error: categoryAuthorizationError() }
      }

      return completeProductMutation(
        context,
        client
          .from('producto')
          .update({ activo: active })
          .eq('id', productId)
          .eq('local_id', context.local.id),
        active
          ? 'El producto se activó correctamente.'
          : 'El producto se desactivó correctamente.',
      )
    },

    async deleteProduct(context, productId, confirmed) {
      if (!confirmed) {
        return {
          ok: true,
          data: {
            status: 'cancelled',
            catalog: null,
            message: 'La eliminación del producto fue cancelada.',
          },
        }
      }

      if (context.role.codigo !== 'ADMINISTRADOR') {
        return { ok: false, error: categoryAuthorizationError() }
      }

      return completeProductMutation(
        context,
        client
          .from('producto')
          .delete()
          .eq('id', productId)
          .eq('local_id', context.local.id),
        'El producto se eliminó correctamente.',
        true,
      )
    },

    async createTable(context, input) {
      if (context.role.codigo !== 'ADMINISTRADOR') {
        return { ok: false, error: categoryAuthorizationError() }
      }

      const validated = validateTableInput(input)
      if (!validated.ok) {
        return validated
      }

      return completeTableMutation(
        context,
        client.from('mesa').insert({
          local_id: context.local.id,
          codigo: validated.data.codigo,
          nombre: validated.data.nombre,
          activo: validated.data.activo,
        }),
        'La mesa se creó correctamente en estado libre.',
        null,
        false,
        validated.data.codigo,
      )
    },

    async updateTable(context, table, input) {
      if (context.role.codigo !== 'ADMINISTRADOR') {
        return { ok: false, error: categoryAuthorizationError() }
      }

      const validated = validateTableInput(input)
      if (!validated.ok) {
        return validated
      }

      if (!validated.data.activo && table.estado !== 'LIBRE') {
        return { ok: false, error: tableNotFreeError() }
      }

      return completeTableMutation(
        context,
        client
          .from('mesa')
          .update({
            codigo: validated.data.codigo,
            nombre: validated.data.nombre,
            activo: validated.data.activo,
          })
          .eq('id', table.id)
          .eq('local_id', context.local.id),
        'La mesa se actualizó correctamente.',
        table,
        !validated.data.activo,
      )
    },

    async setTableActive(context, table, active) {
      if (context.role.codigo !== 'ADMINISTRADOR') {
        return { ok: false, error: categoryAuthorizationError() }
      }

      if (!active && table.estado !== 'LIBRE') {
        return { ok: false, error: tableNotFreeError() }
      }

      return completeTableMutation(
        context,
        client
          .from('mesa')
          .update({ activo: active })
          .eq('id', table.id)
          .eq('local_id', context.local.id),
        active
          ? 'La mesa se activó correctamente.'
          : 'La mesa se desactivó correctamente.',
        table,
        !active,
      )
    },

    async deleteTable(context, table, confirmed) {
      if (!confirmed) {
        return {
          ok: true,
          data: {
            status: 'cancelled',
            tables: null,
            message: 'La eliminación de la mesa fue cancelada.',
          },
        }
      }

      if (context.role.codigo !== 'ADMINISTRADOR') {
        return { ok: false, error: categoryAuthorizationError() }
      }

      return completeTableMutation(
        context,
        client
          .from('mesa')
          .delete()
          .eq('id', table.id)
          .eq('local_id', context.local.id),
        'La mesa se eliminó correctamente.',
        table,
      )
    },
  }
}
