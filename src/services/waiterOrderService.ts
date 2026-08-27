import type { SupabaseClient } from '@supabase/supabase-js'
import type { ValidatedProfileContext } from './profileContext'
import type { OrderStatusCode, TableStatusCode } from '../types/operations'

const currentOrderStatuses: readonly OrderStatusCode[] = [
  'ABIERTO', 'ENVIADO', 'RECIBIDO_COCINA', 'EN_PREPARACION', 'LISTO', 'ENTREGADO',
]

export type WaiterTableFilter = 'TODAS' | TableStatusCode
export type WaiterTableOrder = 'ASC' | 'DESC'

export interface CurrentOrderSummary {
  readonly id: number
  readonly estado: OrderStatusCode
  readonly total: number
}

export interface WaiterTableBoardItem {
  readonly id: string
  readonly codigo: string
  readonly nombre: string
  readonly estado: TableStatusCode
  readonly pedido: CurrentOrderSummary | null
}

export type OrderDetailStatus = 'ABIERTO' | 'ENVIADO' | 'RECIBIDO_COCINA' | 'EN_PREPARACION' | 'LISTO'

export interface WaiterOrderDetail {
  readonly id: number
  readonly pedido_id: number
  readonly producto_id: string
  readonly cantidad: number
  readonly precio_unitario: number
  readonly observacion: string | null
  readonly estado: OrderDetailStatus
}

export interface WaiterOrderReview {
  readonly id: number
  readonly estado: OrderStatusCode
  readonly mesa: { readonly id: string; readonly codigo: string; readonly nombre: string }
}

export type WaiterOrderResult<T> =
  | { readonly ok: true; readonly data: T }
  | { readonly ok: false; readonly error: { readonly kind: 'operation-error' | 'concurrent-conflict'; readonly message: string; readonly recoverable: true } }

interface TableRow extends Omit<WaiterTableBoardItem, 'pedido'> { readonly activo: boolean }
interface OrderRow { readonly id: number; readonly mesa_id: string; readonly estado: OrderStatusCode }
interface DetailRow { readonly pedido_id: number; readonly cantidad: number; readonly precio_unitario: number }
interface OpenOrderRow { readonly pedido_id: number; readonly fue_creado: boolean }
interface AddedDetailRow extends WaiterOrderDetail { readonly detalle_id: number }
interface ReviewOrderRow { readonly id: number; readonly mesa_id: string; readonly estado: OrderStatusCode }
interface ReviewTableRow { readonly id: string; readonly codigo: string; readonly nombre: string }
interface SentOrderRow { readonly pedido_id: number; readonly detalles_enviados: number }
interface ReleasedTableRow { readonly pedido_id: number; readonly mesa_id: string; readonly pedido_estado: 'ANULADO'; readonly mesa_estado: 'LIBRE' }
type WaiterOrderClient = Pick<SupabaseClient, 'from' | 'rpc'>

const tableCollator = new Intl.Collator('es', { numeric: true, sensitivity: 'base' })

function connectionError(message: string): WaiterOrderResult<never> {
  return { ok: false, error: { kind: 'operation-error', message, recoverable: true } }
}

function concurrentConflict(): WaiterOrderResult<never> {
  return {
    ok: false,
    error: {
      kind: 'concurrent-conflict',
      message: 'Este producto fue actualizado desde otro dispositivo. Se cargó la versión más reciente.',
      recoverable: true,
    },
  }
}

export function combineOrderObservation(selected: readonly string[], freeText: string): string | null {
  const parts = [...selected, freeText.trim()].filter(Boolean)
  return parts.length > 0 ? parts.join(', ') : null
}

export function filterAndSortWaiterTables(
  tables: readonly WaiterTableBoardItem[],
  filter: WaiterTableFilter,
  order: WaiterTableOrder,
): readonly WaiterTableBoardItem[] {
  const filtered = filter === 'TODAS' ? tables : tables.filter((table) => table.estado === filter)
  return [...filtered].sort((left, right) => {
    const comparison = tableCollator.compare(left.codigo, right.codigo)
      || tableCollator.compare(left.nombre, right.nombre)
    return order === 'ASC' ? comparison : -comparison
  })
}

export function createWaiterOrderService(client: WaiterOrderClient) {
  return {
    async getTableBoard(context: ValidatedProfileContext): Promise<WaiterOrderResult<readonly WaiterTableBoardItem[]>> {
      if (context.role.codigo !== 'MOZO') return connectionError('No tienes autorización para consultar el tablero de mesas.')

      try {
        const [tablesResult, ordersResult] = await Promise.all([
          client.from('mesa').select('id,codigo,nombre,estado,activo')
            .eq('local_id', context.local.id).eq('activo', true).returns<TableRow[]>(),
          client.from('pedido').select('id,mesa_id,estado')
            .eq('local_id', context.local.id).in('estado', currentOrderStatuses).returns<OrderRow[]>(),
        ])
        if (tablesResult.error || ordersResult.error) {
          return connectionError('No pudimos cargar las mesas. Revisa tu conexión e intenta nuevamente.')
        }

        const activeTables = (tablesResult.data ?? []).filter((table) => table.activo)
        const orders = ordersResult.data ?? []
        const orderIds = orders.map((order) => order.id)
        let details: readonly DetailRow[] = []
        if (orderIds.length > 0) {
          const detailResult = await client.from('detalle_pedido')
            .select('pedido_id,cantidad,precio_unitario').in('pedido_id', orderIds).returns<DetailRow[]>()
          if (detailResult.error) return connectionError('No pudimos calcular los totales. Intenta nuevamente.')
          details = detailResult.data ?? []
        }

        const totals = new Map<number, number>()
        for (const detail of details) {
          totals.set(detail.pedido_id, (totals.get(detail.pedido_id) ?? 0)
            + Number(detail.cantidad) * Number(detail.precio_unitario))
        }
        const ordersByTable = new Map(orders.map((order) => [order.mesa_id, order]))
        const board = activeTables.map((table): WaiterTableBoardItem => {
          const currentOrder = ordersByTable.get(table.id)
          return {
            id: table.id, codigo: table.codigo, nombre: table.nombre, estado: table.estado,
            pedido: currentOrder
              ? { id: currentOrder.id, estado: currentOrder.estado, total: totals.get(currentOrder.id) ?? 0 }
              : null,
          }
        })
        return { ok: true, data: filterAndSortWaiterTables(board, 'TODAS', 'ASC') }
      } catch {
        return connectionError('No pudimos cargar las mesas. Revisa tu conexión e intenta nuevamente.')
      }
    },

    async createOrRecoverOrder(context: ValidatedProfileContext, tableId: string): Promise<WaiterOrderResult<{ pedidoId: number; fueCreado: boolean }>> {
      if (context.role.codigo !== 'MOZO') return connectionError('No tienes autorización para tomar pedidos.')
      try {
        const result = await client.rpc('crear_o_recuperar_pedido_mesa', { p_mesa_id: tableId })
        const row = (result.data as OpenOrderRow[] | null)?.[0]
        if (result.error || !row) return connectionError('No pudimos abrir el pedido de la mesa. Intenta nuevamente.')
        return { ok: true, data: { pedidoId: row.pedido_id, fueCreado: row.fue_creado } }
      } catch {
        return connectionError('No pudimos abrir el pedido de la mesa. Intenta nuevamente.')
      }
    },

    async getOrderDetails(context: ValidatedProfileContext, orderId: number): Promise<WaiterOrderResult<readonly WaiterOrderDetail[]>> {
      if (context.role.codigo !== 'MOZO') return connectionError('No tienes autorización para consultar este pedido.')
      try {
        const result = await client.from('detalle_pedido')
          .select('id,pedido_id,producto_id,cantidad,precio_unitario,observacion,estado')
          .eq('pedido_id', orderId).returns<WaiterOrderDetail[]>()
        if (result.error) return connectionError('No pudimos cargar los productos del pedido. Intenta nuevamente.')
        return { ok: true, data: result.data ?? [] }
      } catch {
        return connectionError('No pudimos cargar los productos del pedido. Intenta nuevamente.')
      }
    },

    async getOrderReview(context: ValidatedProfileContext, orderId: number): Promise<WaiterOrderResult<WaiterOrderReview>> {
      if (context.role.codigo !== 'MOZO') return connectionError('No tienes autorización para consultar este pedido.')
      try {
        const orderResult = await client.from('pedido').select('id,mesa_id,estado')
          .eq('id', orderId).eq('local_id', context.local.id).in('estado', currentOrderStatuses).returns<ReviewOrderRow[]>()
        const order = orderResult.data?.[0]
        if (orderResult.error || !order) return connectionError('No pudimos cargar el pedido vigente. Intenta nuevamente.')
        const tableResult = await client.from('mesa').select('id,codigo,nombre')
          .eq('id', order.mesa_id).eq('local_id', context.local.id).eq('activo', true).returns<ReviewTableRow[]>()
        const table = tableResult.data?.[0]
        if (tableResult.error || !table) return connectionError('No pudimos identificar la mesa del pedido.')
        return { ok: true, data: { id: order.id, estado: order.estado, mesa: table } }
      } catch {
        return connectionError('No pudimos cargar el pedido vigente. Intenta nuevamente.')
      }
    },

    async addOrderDetail(context: ValidatedProfileContext, orderId: number, productId: string): Promise<WaiterOrderResult<WaiterOrderDetail>> {
      if (context.role.codigo !== 'MOZO') return connectionError('No tienes autorización para agregar productos.')
      try {
        const result = await client.rpc('agregar_detalle_pedido', {
          p_pedido_id: orderId,
          p_producto_id: productId,
          p_cantidad: 1,
          p_observacion: null,
        })
        const row = (result.data as AddedDetailRow[] | null)?.[0]
        if (result.error || !row) return connectionError('No pudimos agregar el producto. Intenta nuevamente.')
        return { ok: true, data: { ...row, id: row.detalle_id } }
      } catch {
        return connectionError('No pudimos agregar el producto. Intenta nuevamente.')
      }
    },

    async updateOpenDetail(context: ValidatedProfileContext, detailId: number, input: { readonly cantidad?: number; readonly observacion?: string | null }, expected?: { readonly cantidad?: number; readonly observacion?: string | null }): Promise<WaiterOrderResult<null>> {
      if (context.role.codigo !== 'MOZO') return connectionError('No tienes autorización para modificar productos.')
      if (input.cantidad !== undefined && (!Number.isInteger(input.cantidad) || input.cantidad < 1)) {
        return connectionError('La cantidad debe ser un entero mayor o igual a 1.')
      }
      const changes: { cantidad?: number; observacion?: string | null } = {}
      if (input.cantidad !== undefined) changes.cantidad = input.cantidad
      if (input.observacion !== undefined) changes.observacion = input.observacion?.trim() || null
      if (Object.keys(changes).length === 0) return { ok: true, data: null }
      try {
        let mutation = client.from('detalle_pedido').update(changes).eq('id', detailId).eq('estado', 'ABIERTO')
        if (expected?.cantidad !== undefined) mutation = mutation.eq('cantidad', expected.cantidad)
        if (expected && 'observacion' in expected) {
          mutation = expected.observacion === null
            ? mutation.is('observacion', null)
            : mutation.eq('observacion', expected.observacion)
        }
        const result = await mutation.select('id').returns<{ id: number }[]>()
        if (result.error) return connectionError('No pudimos guardar el cambio. Los datos anteriores se mantienen.')
        if (!result.data?.length) return concurrentConflict()
        return { ok: true, data: null }
      } catch {
        return connectionError('No pudimos guardar el cambio. Los datos anteriores se mantienen.')
      }
    },

    async removeOpenDetail(context: ValidatedProfileContext, detailId: number): Promise<WaiterOrderResult<null>> {
      if (context.role.codigo !== 'MOZO') return connectionError('No tienes autorización para retirar productos.')
      try {
        const result = await client.from('detalle_pedido').delete().eq('id', detailId).eq('estado', 'ABIERTO').select('id').returns<{ id: number }[]>()
        if (result.error) return connectionError('No pudimos retirar el producto. Intenta nuevamente.')
        if (!result.data?.length) return concurrentConflict()
        return { ok: true, data: null }
      } catch {
        return connectionError('No pudimos retirar el producto. Intenta nuevamente.')
      }
    },

    async sendOrderToKitchen(context: ValidatedProfileContext, orderId: number): Promise<WaiterOrderResult<{ detallesEnviados: number }>> {
      if (context.role.codigo !== 'MOZO') return connectionError('No tienes autorización para enviar pedidos.')
      try {
        const result = await client.rpc('enviar_pedido_cocina', { p_pedido_id: orderId })
        const row = (result.data as SentOrderRow[] | null)?.[0]
        if (result.error || !row) return connectionError('No pudimos enviar el pedido a cocina. Los productos permanecen por enviar.')
        return { ok: true, data: { detallesEnviados: row.detalles_enviados } }
      } catch {
        return connectionError('No pudimos enviar el pedido a cocina. Los productos permanecen por enviar.')
      }
    },

    async releaseEmptyOrderTable(context: ValidatedProfileContext, orderId: number): Promise<WaiterOrderResult<{ mesaId: string }>> {
      if (context.role.codigo !== 'MOZO') return connectionError('No tienes autorización para liberar mesas.')
      try {
        const result = await client.rpc('liberar_mesa_pedido_vacio', { p_pedido_id: orderId })
        const row = (result.data as ReleasedTableRow[] | null)?.[0]
        if (result.error || !row) {
          return connectionError('No pudimos liberar la mesa. Verifica que el pedido siga vacío e intenta nuevamente.')
        }
        return { ok: true, data: { mesaId: row.mesa_id } }
      } catch {
        return connectionError('No pudimos liberar la mesa. Verifica que el pedido siga vacío e intenta nuevamente.')
      }
    },
  }
}
