import { useEffect, useMemo, useRef, useState, type FormEvent } from 'react'
import {
  createCatalogService,
  type AdministrativeCatalog,
  type CatalogCategory,
  type CatalogProduct,
  type CatalogResult,
  type CatalogTable,
  type CategoryMutation,
  type ProductMutation,
  type TableMutation,
} from '../services/catalogService'
import type { ValidatedProfileContext } from '../services/profileContext'
import { getSupabaseClient } from '../services/supabaseClient'

interface CategoryAdministrationPageProps {
  readonly context: ValidatedProfileContext
  readonly isSigningOut: boolean
  readonly onSignOut: () => void
  readonly onNavigateToTechnical: () => void
}

interface CategoryFormState {
  readonly codigo: string
  readonly nombre: string
  readonly orden: string
  readonly activo: boolean
}

interface ProductFormState {
  readonly categoria_id: string
  readonly codigo: string
  readonly nombre: string
  readonly precio: string
  readonly activo: boolean
}

interface TableFormState {
  readonly codigo: string
  readonly nombre: string
  readonly activo: boolean
}

const emptyCategoryForm: CategoryFormState = {
  codigo: '',
  nombre: '',
  orden: '0',
  activo: true,
}

const emptyProductForm: ProductFormState = {
  categoria_id: '',
  codigo: '',
  nombre: '',
  precio: '0',
  activo: true,
}

const emptyTableForm: TableFormState = {
  codigo: '',
  nombre: '',
  activo: true,
}

const priceFormatter = new Intl.NumberFormat('es-PE', {
  style: 'currency',
  currency: 'PEN',
})

const inputClassName =
  'mt-2 w-full rounded-xl border border-stone-300 bg-white px-4 py-3 text-stone-900 outline-none transition focus:border-emerald-700 focus:ring-2 focus:ring-emerald-100 disabled:cursor-not-allowed disabled:bg-stone-100'

export default function CategoryAdministrationPage({
  context,
  isSigningOut,
  onSignOut,
  onNavigateToTechnical,
}: CategoryAdministrationPageProps) {
  const clientResult = useMemo(() => getSupabaseClient(), [])
  const service = useMemo(
    () => clientResult.ok ? createCatalogService(clientResult.client) : null,
    [clientResult],
  )
  const [catalog, setCatalog] = useState<AdministrativeCatalog | null>(null)
  const [form, setForm] = useState<CategoryFormState>(emptyCategoryForm)
  const [productForm, setProductForm] = useState<ProductFormState>(emptyProductForm)
  const [tableForm, setTableForm] = useState<TableFormState>(emptyTableForm)
  const [editingCategoryId, setEditingCategoryId] = useState<string | null>(null)
  const [editingProductId, setEditingProductId] = useState<string | null>(null)
  const [editingTableId, setEditingTableId] = useState<string | null>(null)
  const [tables, setTables] = useState<readonly CatalogTable[] | null>(null)
  const [loading, setLoading] = useState(true)
  const [saving, setSaving] = useState(false)
  const [message, setMessage] = useState<string | null>(null)
  const [error, setError] = useState<string | null>(null)
  const [productMessage, setProductMessage] = useState<string | null>(null)
  const [productError, setProductError] = useState<string | null>(null)
  const [tableMessage, setTableMessage] = useState<string | null>(null)
  const [tableError, setTableError] = useState<string | null>(null)
  const mutationPending = useRef(false)

  useEffect(() => {
    let cancelled = false

    async function loadCatalog(): Promise<void> {
      if (!service) {
        setLoading(false)
        setError('No pudimos establecer la conexión con el catálogo.')
        return
      }

      setLoading(true)
      const [result, tableResult] = await Promise.all([
        service.getAdministrativeCatalog(context),
        service.getAdministrativeTables(context),
      ])
      if (cancelled) {
        return
      }

      setLoading(false)
      if (!result.ok) {
        setError(result.error.message)
        return
      }

      setCatalog(result.data)
      setError(null)

      if (!tableResult.ok) {
        setTableError(tableResult.error.message)
        return
      }

      setTables(tableResult.data)
      setTableError(null)
    }

    void loadCatalog()
    return () => {
      cancelled = true
    }
  }, [context, service])

  function resetForm(): void {
    setForm(emptyCategoryForm)
    setEditingCategoryId(null)
  }

  function editCategory(category: CatalogCategory): void {
    setEditingCategoryId(category.id)
    setForm({
      codigo: category.codigo,
      nombre: category.nombre,
      orden: String(category.orden),
      activo: category.activo,
    })
    setError(null)
    setMessage(null)
  }

  function resetProductForm(): void {
    setProductForm(emptyProductForm)
    setEditingProductId(null)
  }

  function editProduct(product: CatalogProduct): void {
    setEditingProductId(product.id)
    setProductForm({
      categoria_id: product.categoria_id,
      codigo: product.codigo,
      nombre: product.nombre,
      precio: String(product.precio),
      activo: product.activo,
    })
    setProductError(null)
    setProductMessage(null)
  }

  function resetTableForm(): void {
    setTableForm(emptyTableForm)
    setEditingTableId(null)
  }

  function editTable(table: CatalogTable): void {
    setEditingTableId(table.id)
    setTableForm({
      codigo: table.codigo,
      nombre: table.nombre,
      activo: table.activo,
    })
    setTableError(null)
    setTableMessage(null)
  }

  async function runCategoryMutation(
    operation: () => Promise<CatalogResult<CategoryMutation>>,
    resetAfterSuccess: boolean,
  ): Promise<void> {
    if (mutationPending.current) {
      return
    }

    mutationPending.current = true
    setSaving(true)
    setError(null)
    setMessage(null)

    try {
      const result = await operation()
      if (!result.ok) {
        setError(result.error.message)
        return
      }

      if (result.data.status === 'cancelled') {
        setMessage(result.data.message)
        return
      }

      if (result.data.catalog) {
        setCatalog(result.data.catalog)
      }
      setMessage(result.data.message)

      if (resetAfterSuccess) {
        resetForm()
      }
    } catch {
      setError('No pudimos completar la operación. Intenta nuevamente.')
    } finally {
      mutationPending.current = false
      setSaving(false)
    }
  }

  function submitCategory(event: FormEvent<HTMLFormElement>): void {
    event.preventDefault()
    if (!service || saving || mutationPending.current) {
      return
    }

    if (!form.orden.trim()) {
      setError('Ingresa el orden de la categoría.')
      setMessage(null)
      return
    }

    const input = {
      codigo: form.codigo,
      nombre: form.nombre,
      orden: Number(form.orden),
      activo: form.activo,
    }

    void runCategoryMutation(
      () => editingCategoryId
        ? service.updateCategory(context, editingCategoryId, input)
        : service.createCategory(context, input),
      true,
    )
  }

  function toggleCategory(category: CatalogCategory): void {
    if (!service || saving || mutationPending.current) {
      return
    }

    void runCategoryMutation(
      () => service.setCategoryActive(context, category.id, !category.activo),
      false,
    )
  }

  function deleteCategory(category: CatalogCategory): void {
    if (!service || saving || mutationPending.current) {
      return
    }

    const confirmed = window.confirm(
      `¿Eliminar definitivamente la categoría «${category.nombre}» (${category.codigo})? Esta acción no se puede deshacer.`,
    )

    void runCategoryMutation(
      () => service.deleteCategory(context, category.id, confirmed),
      confirmed && editingCategoryId === category.id,
    )
  }

  async function runProductMutation(
    operation: () => Promise<CatalogResult<ProductMutation>>,
    resetAfterSuccess: boolean,
  ): Promise<void> {
    if (mutationPending.current) {
      return
    }

    mutationPending.current = true
    setSaving(true)
    setProductError(null)
    setProductMessage(null)

    try {
      const result = await operation()
      if (!result.ok) {
        setProductError(result.error.message)
        return
      }

      if (result.data.status === 'cancelled') {
        setProductMessage(result.data.message)
        return
      }

      if (result.data.catalog) {
        setCatalog(result.data.catalog)
      }
      setProductMessage(result.data.message)

      if (resetAfterSuccess) {
        resetProductForm()
      }
    } catch {
      setProductError('No pudimos completar la operación del producto. Intenta nuevamente.')
    } finally {
      mutationPending.current = false
      setSaving(false)
    }
  }

  function submitProduct(event: FormEvent<HTMLFormElement>): void {
    event.preventDefault()
    if (!service || saving || mutationPending.current) {
      return
    }

    if (!productForm.precio.trim()) {
      setProductError('Ingresa el precio del producto.')
      setProductMessage(null)
      return
    }

    const input = {
      categoria_id: productForm.categoria_id,
      codigo: productForm.codigo,
      nombre: productForm.nombre,
      precio: Number(productForm.precio),
      activo: productForm.activo,
    }
    const categories = catalog?.categories ?? []

    void runProductMutation(
      () => editingProductId
        ? service.updateProduct(context, editingProductId, input, categories)
        : service.createProduct(context, input, categories),
      true,
    )
  }

  function toggleProduct(product: CatalogProduct): void {
    if (!service || saving || mutationPending.current) {
      return
    }

    void runProductMutation(
      () => service.setProductActive(context, product.id, !product.activo),
      false,
    )
  }

  function deleteProduct(product: CatalogProduct): void {
    if (!service || saving || mutationPending.current) {
      return
    }

    const confirmed = window.confirm(
      `¿Eliminar definitivamente el producto «${product.nombre}» (${product.codigo})? Esta acción no se puede deshacer.`,
    )

    void runProductMutation(
      () => service.deleteProduct(context, product.id, confirmed),
      confirmed && editingProductId === product.id,
    )
  }

  async function runTableMutation(
    operation: () => Promise<CatalogResult<TableMutation>>,
    resetAfterSuccess: boolean,
  ): Promise<void> {
    if (mutationPending.current) {
      return
    }

    mutationPending.current = true
    setSaving(true)
    setTableError(null)
    setTableMessage(null)

    try {
      const result = await operation()
      if (!result.ok) {
        setTableError(result.error.message)
        return
      }

      if (result.data.status === 'cancelled') {
        setTableMessage(result.data.message)
        return
      }

      if (result.data.tables) {
        setTables(result.data.tables)
      }
      setTableMessage(result.data.message)

      if (resetAfterSuccess) {
        resetTableForm()
      }
    } catch {
      setTableError('No pudimos completar la operación de mesa. Intenta nuevamente.')
    } finally {
      mutationPending.current = false
      setSaving(false)
    }
  }

  function submitTable(event: FormEvent<HTMLFormElement>): void {
    event.preventDefault()
    if (!service || saving || mutationPending.current) {
      return
    }

    const input = {
      codigo: tableForm.codigo,
      nombre: tableForm.nombre,
      activo: tableForm.activo,
    }
    const editingTable = tables?.find((table) => table.id === editingTableId)

    if (editingTableId && !editingTable) {
      setTableError('No encontramos la mesa que deseas editar. Intenta nuevamente.')
      return
    }

    void runTableMutation(
      () => editingTable
        ? service.updateTable(context, editingTable, input)
        : service.createTable(context, input),
      true,
    )
  }

  function toggleTable(table: CatalogTable): void {
    if (!service || saving || mutationPending.current) {
      return
    }

    void runTableMutation(
      () => service.setTableActive(context, table, !table.activo),
      false,
    )
  }

  function deleteTable(table: CatalogTable): void {
    if (!service || saving || mutationPending.current) {
      return
    }

    const confirmed = window.confirm(
      `¿Eliminar definitivamente la mesa «${table.nombre}» (${table.codigo})? Esta acción no se puede deshacer.`,
    )

    void runTableMutation(
      () => service.deleteTable(context, table, confirmed),
      confirmed && editingTableId === table.id,
    )
  }

  return (
    <main className="min-h-screen bg-stone-100 px-4 py-8 text-stone-900 sm:px-8">
      <div className="mx-auto max-w-6xl">
        <header className="flex flex-col gap-5 rounded-3xl border border-stone-200 bg-white p-6 shadow-sm sm:flex-row sm:items-center sm:justify-between">
          <div>
            <p className="text-sm font-semibold uppercase tracking-[0.18em] text-emerald-700">
              MikuyApp · Administración
            </p>
            <h1 className="mt-2 text-3xl font-bold tracking-tight">Catálogo administrativo</h1>
            <p className="mt-2 text-sm text-stone-600">
              Gestiona las categorías, los productos y las mesas de tu local.
            </p>
          </div>

          <div className="flex flex-wrap gap-3">
            <button
              className="rounded-xl border border-stone-300 px-4 py-2.5 text-sm font-semibold text-stone-800 hover:bg-stone-50"
              onClick={onNavigateToTechnical}
              type="button"
            >
              Verificación técnica
            </button>
            <button
              aria-busy={isSigningOut}
              className="rounded-xl bg-emerald-800 px-4 py-2.5 text-sm font-semibold text-white hover:bg-emerald-900 disabled:opacity-70"
              disabled={isSigningOut}
              onClick={onSignOut}
              type="button"
            >
              {isSigningOut ? 'Cerrando sesión…' : 'Cerrar sesión'}
            </button>
          </div>
        </header>

        <section className="mt-6 grid gap-6 lg:grid-cols-[minmax(0,22rem)_minmax(0,1fr)]">
          <article className="self-start rounded-3xl border border-stone-200 bg-white p-6 shadow-sm">
            <h2 className="text-xl font-semibold">
              {editingCategoryId ? 'Editar categoría' : 'Nueva categoría'}
            </h2>
            <p className="mt-2 text-sm text-stone-600">
              {editingCategoryId
                ? 'Actualiza los datos y guarda los cambios.'
                : 'Completa los datos para agregar una categoría.'}
            </p>

            <form className="mt-6 space-y-5" onSubmit={submitCategory}>
              <label className="block text-sm font-medium text-stone-800" htmlFor="category-code">
                Código
                <input
                  autoComplete="off"
                  className={inputClassName}
                  disabled={saving}
                  id="category-code"
                  onChange={(event) => setForm((current) => ({
                    ...current,
                    codigo: event.target.value,
                  }))}
                  required
                  type="text"
                  value={form.codigo}
                />
              </label>

              <label className="block text-sm font-medium text-stone-800" htmlFor="category-name">
                Nombre
                <input
                  autoComplete="off"
                  className={inputClassName}
                  disabled={saving}
                  id="category-name"
                  onChange={(event) => setForm((current) => ({
                    ...current,
                    nombre: event.target.value,
                  }))}
                  required
                  type="text"
                  value={form.nombre}
                />
              </label>

              <label className="block text-sm font-medium text-stone-800" htmlFor="category-order">
                Orden
                <input
                  className={inputClassName}
                  disabled={saving}
                  id="category-order"
                  min="0"
                  onChange={(event) => setForm((current) => ({
                    ...current,
                    orden: event.target.value,
                  }))}
                  required
                  step="1"
                  type="number"
                  value={form.orden}
                />
              </label>

              <label className="flex items-center gap-3 text-sm font-medium text-stone-800">
                <input
                  checked={form.activo}
                  className="size-4 rounded border-stone-300 accent-emerald-700"
                  disabled={saving}
                  onChange={(event) => setForm((current) => ({
                    ...current,
                    activo: event.target.checked,
                  }))}
                  type="checkbox"
                />
                Categoría activa
              </label>

              <div className="flex flex-wrap gap-3">
                <button
                  aria-busy={saving}
                  className="rounded-xl bg-emerald-800 px-5 py-3 text-sm font-semibold text-white hover:bg-emerald-900 disabled:opacity-70"
                  disabled={saving || !service}
                  type="submit"
                >
                  {saving
                    ? 'Guardando…'
                    : editingCategoryId
                      ? 'Guardar cambios'
                      : 'Crear categoría'}
                </button>

                {editingCategoryId && (
                  <button
                    className="rounded-xl border border-stone-300 px-4 py-3 text-sm font-semibold text-stone-800 hover:bg-stone-50"
                    disabled={saving}
                    onClick={resetForm}
                    type="button"
                  >
                    Cancelar edición
                  </button>
                )}
              </div>
            </form>
          </article>

          <article className="rounded-3xl border border-stone-200 bg-white p-6 shadow-sm">
            <div className="flex flex-wrap items-center justify-between gap-3">
              <div>
                <h2 className="text-xl font-semibold">Categorías</h2>
                <p className="mt-1 text-sm text-stone-600">
                  Activas e inactivas, ordenadas para tu catálogo.
                </p>
              </div>
              {catalog && (
                <span className="rounded-full bg-stone-100 px-3 py-1 text-sm font-medium text-stone-700">
                  {catalog.categories.length}
                </span>
              )}
            </div>

            {error && (
              <p className="mt-5 rounded-xl bg-rose-50 px-4 py-3 text-sm text-rose-800" role="alert">
                {error}
              </p>
            )}

            {message && (
              <p className="mt-5 rounded-xl bg-emerald-50 px-4 py-3 text-sm text-emerald-800" role="status">
                {message}
              </p>
            )}

            {loading ? (
              <p aria-busy="true" className="mt-8 text-sm text-stone-600">
                Cargando categorías…
              </p>
            ) : !catalog?.categories.length ? (
              <p className="mt-8 rounded-2xl border border-dashed border-stone-300 p-5 text-sm text-stone-600">
                Todavía no hay categorías registradas para tu local.
              </p>
            ) : (
              <ul className="mt-6 space-y-4">
                {catalog.categories.map((category) => (
                  <li
                    className="rounded-2xl border border-stone-200 p-4"
                    key={category.id}
                  >
                    <div className="flex flex-wrap items-start justify-between gap-3">
                      <div>
                        <div className="flex flex-wrap items-center gap-2">
                          <h3 className="font-semibold text-stone-900">{category.nombre}</h3>
                          <span
                            className={category.activo
                              ? 'rounded-full bg-emerald-100 px-2.5 py-1 text-xs font-semibold text-emerald-800'
                              : 'rounded-full bg-stone-200 px-2.5 py-1 text-xs font-semibold text-stone-700'}
                          >
                            {category.activo ? 'Activa' : 'Inactiva'}
                          </span>
                        </div>
                        <p className="mt-2 text-sm text-stone-600">
                          Código: {category.codigo} · Orden: {category.orden}
                        </p>
                      </div>
                    </div>

                    <div className="mt-4 flex flex-wrap gap-2">
                      <button
                        className="rounded-lg border border-stone-300 px-3 py-2 text-sm font-medium text-stone-800 hover:bg-stone-50 disabled:opacity-60"
                        disabled={saving}
                        onClick={() => editCategory(category)}
                        type="button"
                      >
                        Editar
                      </button>
                      <button
                        className="rounded-lg border border-stone-300 px-3 py-2 text-sm font-medium text-stone-800 hover:bg-stone-50 disabled:opacity-60"
                        disabled={saving}
                        onClick={() => toggleCategory(category)}
                        type="button"
                      >
                        {category.activo ? 'Desactivar' : 'Activar'}
                      </button>
                      <button
                        className="rounded-lg border border-rose-200 px-3 py-2 text-sm font-medium text-rose-800 hover:bg-rose-50 disabled:opacity-60"
                        disabled={saving}
                        onClick={() => deleteCategory(category)}
                        type="button"
                      >
                        Eliminar
                      </button>
                    </div>
                  </li>
                ))}
              </ul>
            )}
          </article>
        </section>

        <section className="mt-6 grid gap-6 lg:grid-cols-[minmax(0,22rem)_minmax(0,1fr)]">
          <article className="self-start rounded-3xl border border-stone-200 bg-white p-6 shadow-sm">
            <h2 className="text-xl font-semibold">
              {editingProductId ? 'Editar producto' : 'Nuevo producto'}
            </h2>
            <p className="mt-2 text-sm text-stone-600">
              {editingProductId
                ? 'Actualiza los datos y guarda los cambios.'
                : 'Completa los datos para agregar un producto.'}
            </p>

            <form className="mt-6 space-y-5" onSubmit={submitProduct}>
              <label className="block text-sm font-medium text-stone-800" htmlFor="product-category">
                Categoría
                <select
                  className={inputClassName}
                  disabled={saving || !catalog?.categories.length}
                  id="product-category"
                  onChange={(event) => setProductForm((current) => ({
                    ...current,
                    categoria_id: event.target.value,
                  }))}
                  required
                  value={productForm.categoria_id}
                >
                  <option value="">Selecciona una categoría</option>
                  {catalog?.categories.map((category) => (
                    <option key={category.id} value={category.id}>
                      {category.nombre} — {category.activo ? 'Activa' : 'Inactiva'}
                    </option>
                  ))}
                </select>
              </label>

              <label className="block text-sm font-medium text-stone-800" htmlFor="product-code">
                Código
                <input
                  autoComplete="off"
                  className={inputClassName}
                  disabled={saving}
                  id="product-code"
                  onChange={(event) => setProductForm((current) => ({
                    ...current,
                    codigo: event.target.value,
                  }))}
                  required
                  type="text"
                  value={productForm.codigo}
                />
              </label>

              <label className="block text-sm font-medium text-stone-800" htmlFor="product-name">
                Nombre
                <input
                  autoComplete="off"
                  className={inputClassName}
                  disabled={saving}
                  id="product-name"
                  onChange={(event) => setProductForm((current) => ({
                    ...current,
                    nombre: event.target.value,
                  }))}
                  required
                  type="text"
                  value={productForm.nombre}
                />
              </label>

              <label className="block text-sm font-medium text-stone-800" htmlFor="product-price">
                Precio
                <input
                  className={inputClassName}
                  disabled={saving}
                  id="product-price"
                  min="0"
                  onChange={(event) => setProductForm((current) => ({
                    ...current,
                    precio: event.target.value,
                  }))}
                  required
                  step="0.01"
                  type="number"
                  value={productForm.precio}
                />
              </label>

              <label className="flex items-center gap-3 text-sm font-medium text-stone-800">
                <input
                  checked={productForm.activo}
                  className="size-4 rounded border-stone-300 accent-emerald-700"
                  disabled={saving}
                  onChange={(event) => setProductForm((current) => ({
                    ...current,
                    activo: event.target.checked,
                  }))}
                  type="checkbox"
                />
                Producto activo
              </label>

              <div className="flex flex-wrap gap-3">
                <button
                  aria-busy={saving}
                  className="rounded-xl bg-emerald-800 px-5 py-3 text-sm font-semibold text-white hover:bg-emerald-900 disabled:opacity-70"
                  disabled={saving || !service || !catalog?.categories.length}
                  type="submit"
                >
                  {saving
                    ? 'Guardando…'
                    : editingProductId
                      ? 'Guardar producto'
                      : 'Crear producto'}
                </button>

                {editingProductId && (
                  <button
                    className="rounded-xl border border-stone-300 px-4 py-3 text-sm font-semibold text-stone-800 hover:bg-stone-50"
                    disabled={saving}
                    onClick={resetProductForm}
                    type="button"
                  >
                    Cancelar edición
                  </button>
                )}
              </div>
            </form>
          </article>

          <article className="rounded-3xl border border-stone-200 bg-white p-6 shadow-sm">
            <div className="flex flex-wrap items-center justify-between gap-3">
              <div>
                <h2 className="text-xl font-semibold">Productos</h2>
                <p className="mt-1 text-sm text-stone-600">
                  Activos e inactivos, con su categoría y precio.
                </p>
              </div>
              {catalog && (
                <span className="rounded-full bg-stone-100 px-3 py-1 text-sm font-medium text-stone-700">
                  {catalog.products.length}
                </span>
              )}
            </div>

            {productError && (
              <p className="mt-5 rounded-xl bg-rose-50 px-4 py-3 text-sm text-rose-800" role="alert">
                {productError}
              </p>
            )}

            {productMessage && (
              <p className="mt-5 rounded-xl bg-emerald-50 px-4 py-3 text-sm text-emerald-800" role="status">
                {productMessage}
              </p>
            )}

            {loading ? (
              <p aria-busy="true" className="mt-8 text-sm text-stone-600">
                Cargando productos…
              </p>
            ) : !catalog?.products.length ? (
              <p className="mt-8 rounded-2xl border border-dashed border-stone-300 p-5 text-sm text-stone-600">
                Todavía no hay productos registrados para tu local.
              </p>
            ) : (
              <ul className="mt-6 space-y-4">
                {catalog.products.map((product) => {
                  const category = catalog.categories.find((item) => item.id === product.categoria_id)

                  return (
                    <li className="rounded-2xl border border-stone-200 p-4" key={product.id}>
                      <div className="flex flex-wrap items-start justify-between gap-3">
                        <div>
                          <div className="flex flex-wrap items-center gap-2">
                            <h3 className="font-semibold text-stone-900">{product.nombre}</h3>
                            <span
                              className={product.activo
                                ? 'rounded-full bg-emerald-100 px-2.5 py-1 text-xs font-semibold text-emerald-800'
                                : 'rounded-full bg-stone-200 px-2.5 py-1 text-xs font-semibold text-stone-700'}
                            >
                              {product.activo ? 'Activo' : 'Inactivo'}
                            </span>
                          </div>
                          <p className="mt-2 text-sm text-stone-600">
                            Código: {product.codigo} · Categoría: {category?.nombre ?? 'No disponible'}
                            {category && !category.activo ? ' (Inactiva)' : ''}
                          </p>
                        </div>
                        <span className="rounded-lg bg-stone-100 px-3 py-1.5 text-sm font-semibold text-stone-800">
                          {priceFormatter.format(product.precio)}
                        </span>
                      </div>

                      <div className="mt-4 flex flex-wrap gap-2">
                        <button
                          className="rounded-lg border border-stone-300 px-3 py-2 text-sm font-medium text-stone-800 hover:bg-stone-50 disabled:opacity-60"
                          disabled={saving}
                          onClick={() => editProduct(product)}
                          type="button"
                        >
                          Editar
                        </button>
                        <button
                          className="rounded-lg border border-stone-300 px-3 py-2 text-sm font-medium text-stone-800 hover:bg-stone-50 disabled:opacity-60"
                          disabled={saving}
                          onClick={() => toggleProduct(product)}
                          type="button"
                        >
                          {product.activo ? 'Desactivar' : 'Reactivar'}
                        </button>
                        <button
                          className="rounded-lg border border-rose-200 px-3 py-2 text-sm font-medium text-rose-800 hover:bg-rose-50 disabled:opacity-60"
                          disabled={saving}
                          onClick={() => deleteProduct(product)}
                          type="button"
                        >
                          Eliminar
                        </button>
                      </div>
                    </li>
                  )
                })}
              </ul>
            )}
          </article>
        </section>

        <section className="mt-6 grid gap-6 lg:grid-cols-[minmax(0,22rem)_minmax(0,1fr)]">
          <article className="self-start rounded-3xl border border-stone-200 bg-white p-6 shadow-sm">
            <h2 className="text-xl font-semibold">
              {editingTableId ? 'Editar mesa' : 'Nueva mesa'}
            </h2>
            <p className="mt-2 text-sm text-stone-600">
              {editingTableId
                ? 'Actualiza el código, el nombre y la disponibilidad.'
                : 'Las mesas nuevas se registran automáticamente en estado libre.'}
            </p>

            <form className="mt-6 space-y-5" onSubmit={submitTable}>
              <label className="block text-sm font-medium text-stone-800" htmlFor="table-code">
                Código
                <input
                  autoComplete="off"
                  className={inputClassName}
                  disabled={saving}
                  id="table-code"
                  onChange={(event) => setTableForm((current) => ({
                    ...current,
                    codigo: event.target.value,
                  }))}
                  required
                  type="text"
                  value={tableForm.codigo}
                />
              </label>

              <label className="block text-sm font-medium text-stone-800" htmlFor="table-name">
                Nombre
                <input
                  autoComplete="off"
                  className={inputClassName}
                  disabled={saving}
                  id="table-name"
                  onChange={(event) => setTableForm((current) => ({
                    ...current,
                    nombre: event.target.value,
                  }))}
                  required
                  type="text"
                  value={tableForm.nombre}
                />
              </label>

              <label className="flex items-center gap-3 text-sm font-medium text-stone-800">
                <input
                  checked={tableForm.activo}
                  className="size-4 rounded border-stone-300 accent-emerald-700"
                  disabled={saving || Boolean(
                    editingTableId
                    && tables?.find((table) => table.id === editingTableId)?.estado !== 'LIBRE',
                  )}
                  onChange={(event) => setTableForm((current) => ({
                    ...current,
                    activo: event.target.checked,
                  }))}
                  type="checkbox"
                />
                Mesa activa
              </label>

              <div className="flex flex-wrap gap-3">
                <button
                  aria-busy={saving}
                  className="rounded-xl bg-emerald-800 px-5 py-3 text-sm font-semibold text-white hover:bg-emerald-900 disabled:opacity-70"
                  disabled={saving || !service}
                  type="submit"
                >
                  {saving
                    ? 'Guardando…'
                    : editingTableId
                      ? 'Guardar mesa'
                      : 'Crear mesa'}
                </button>

                {editingTableId && (
                  <button
                    className="rounded-xl border border-stone-300 px-4 py-3 text-sm font-semibold text-stone-800 hover:bg-stone-50"
                    disabled={saving}
                    onClick={resetTableForm}
                    type="button"
                  >
                    Cancelar edición
                  </button>
                )}
              </div>
            </form>
          </article>

          <article className="rounded-3xl border border-stone-200 bg-white p-6 shadow-sm">
            <div className="flex flex-wrap items-center justify-between gap-3">
              <div>
                <h2 className="text-xl font-semibold">Mesas</h2>
                <p className="mt-1 text-sm text-stone-600">
                  Activas e inactivas, con su estado operativo actual.
                </p>
              </div>
              {tables && (
                <span className="rounded-full bg-stone-100 px-3 py-1 text-sm font-medium text-stone-700">
                  {tables.length}
                </span>
              )}
            </div>

            {tableError && (
              <p className="mt-5 rounded-xl bg-rose-50 px-4 py-3 text-sm text-rose-800" role="alert">
                {tableError}
              </p>
            )}

            {tableMessage && (
              <p className="mt-5 rounded-xl bg-emerald-50 px-4 py-3 text-sm text-emerald-800" role="status">
                {tableMessage}
              </p>
            )}

            {loading ? (
              <p aria-busy="true" className="mt-8 text-sm text-stone-600">
                Cargando mesas…
              </p>
            ) : !tables?.length ? (
              <p className="mt-8 rounded-2xl border border-dashed border-stone-300 p-5 text-sm text-stone-600">
                Todavía no hay mesas registradas para tu local.
              </p>
            ) : (
              <ul className="mt-6 space-y-4">
                {tables.map((table) => (
                  <li className="rounded-2xl border border-stone-200 p-4" key={table.id}>
                    <div className="flex flex-wrap items-start justify-between gap-3">
                      <div>
                        <div className="flex flex-wrap items-center gap-2">
                          <h3 className="font-semibold text-stone-900">{table.nombre}</h3>
                          <span
                            className={table.activo
                              ? 'rounded-full bg-emerald-100 px-2.5 py-1 text-xs font-semibold text-emerald-800'
                              : 'rounded-full bg-stone-200 px-2.5 py-1 text-xs font-semibold text-stone-700'}
                          >
                            {table.activo ? 'Activa' : 'Inactiva'}
                          </span>
                        </div>
                        <p className="mt-2 text-sm text-stone-600">Código: {table.codigo}</p>
                      </div>
                      <span className="rounded-lg bg-stone-100 px-3 py-1.5 text-sm font-semibold text-stone-800">
                        {table.estado.replaceAll('_', ' ')}
                      </span>
                    </div>

                    <div className="mt-4 flex flex-wrap gap-2">
                      <button
                        className="rounded-lg border border-stone-300 px-3 py-2 text-sm font-medium text-stone-800 hover:bg-stone-50 disabled:opacity-60"
                        disabled={saving}
                        onClick={() => editTable(table)}
                        type="button"
                      >
                        Editar
                      </button>
                      <button
                        className="rounded-lg border border-stone-300 px-3 py-2 text-sm font-medium text-stone-800 hover:bg-stone-50 disabled:opacity-60"
                        disabled={saving || (table.activo && table.estado !== 'LIBRE')}
                        onClick={() => toggleTable(table)}
                        title={table.activo && table.estado !== 'LIBRE'
                          ? 'Solo puedes desactivar mesas libres.'
                          : undefined}
                        type="button"
                      >
                        {table.activo ? 'Desactivar' : 'Reactivar'}
                      </button>
                      <button
                        className="rounded-lg border border-rose-200 px-3 py-2 text-sm font-medium text-rose-800 hover:bg-rose-50 disabled:opacity-60"
                        disabled={saving}
                        onClick={() => deleteTable(table)}
                        type="button"
                      >
                        Eliminar
                      </button>
                    </div>
                  </li>
                ))}
              </ul>
            )}
          </article>
        </section>
      </div>
    </main>
  )
}
