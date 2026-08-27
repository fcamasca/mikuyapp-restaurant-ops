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

export type WaiterOrderResult<T> =
  | { readonly ok: true; readonly data: T }
  | { readonly ok: false; readonly error: { readonly message: string; readonly recoverable: true } }

interface TableRow extends Omit<WaiterTableBoardItem, 'pedido'> { readonly activo: boolean }
interface OrderRow { readonly id: number; readonly mesa_id: string; readonly estado: OrderStatusCode }
interface DetailRow { readonly pedido_id: number; readonly cantidad: number; readonly precio_unitario: number }
interface OpenOrderRow { readonly pedido_id: number; readonly fue_creado: boolean }
type WaiterOrderClient = Pick<SupabaseClient, 'from' | 'rpc'>

const tableCollator = new Intl.Collator('es', { numeric: true, sensitivity: 'base' })

function connectionError(message: string): WaiterOrderResult<never> {
  return { ok: false, error: { message, recoverable: true } }
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
  }
}
