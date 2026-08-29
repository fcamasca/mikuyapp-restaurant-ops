import type { SupabaseClient } from '@supabase/supabase-js'
import type { ValidatedProfileContext } from './profileContext'
import type { PaymentMethodCode } from '../types/operations'

export interface CashierLine {
  readonly detailId: number
  readonly productId: string
  readonly productName: string
  readonly quantity: number
  readonly unitPrice: number
  readonly lineAmount: number
}

export interface CashierPendingOrder {
  readonly orderId: number
  readonly orderStatus: 'ENTREGADO'
  readonly createdAt: string
  readonly tableId: string
  readonly tableCode: string
  readonly tableName: string
  readonly tableStatus: 'PENDIENTE_PAGO'
  readonly lines: readonly CashierLine[]
  readonly total: number
}

export interface PersistedPayment {
  readonly paymentId: number
  readonly orderId: number
  readonly orderStatus: 'PAGADO'
  readonly tableId: string
  readonly tableStatus: 'LIBRE'
  readonly amount: number
  readonly method: PaymentMethodCode
  readonly paidAt: string
}

export type CashierResult<T> =
  | { readonly ok: true; readonly data: T }
  | { readonly ok: false; readonly error: { readonly kind: 'unauthorized' | 'conflict' | 'operation-error'; readonly message: string } }

interface PendingRow {
  pedido_id: number
  pedido_estado: string
  pedido_creado_en: string
  mesa_id: string
  mesa_codigo: string
  mesa_nombre: string
  mesa_estado: string
  detalle_id: number
  producto_id: string
  producto_nombre: string
  cantidad: number
  precio_unitario: number | string
  importe_linea: number | string
  total_pedido: number | string
}

interface PaymentRow {
  pago_id: number
  pedido_id: number
  pedido_estado: string
  mesa_id: string
  mesa_estado: string
  importe: number | string
  medio: PaymentMethodCode
  pagado_en: string
}

const methods = new Set<PaymentMethodCode>(['EFECTIVO', 'YAPE', 'PLIN', 'TARJETA'])

export function groupCashierOrders(rows: readonly PendingRow[]): readonly CashierPendingOrder[] {
  const orders = new Map<number, CashierPendingOrder>()
  for (const row of rows) {
    const line: CashierLine = {
      detailId: row.detalle_id,
      productId: row.producto_id,
      productName: row.producto_nombre,
      quantity: row.cantidad,
      unitPrice: Number(row.precio_unitario),
      lineAmount: Number(row.importe_linea),
    }
    const current = orders.get(row.pedido_id)
    if (current) {
      orders.set(row.pedido_id, { ...current, lines: [...current.lines, line] })
    } else {
      orders.set(row.pedido_id, {
        orderId: row.pedido_id,
        orderStatus: 'ENTREGADO',
        createdAt: row.pedido_creado_en,
        tableId: row.mesa_id,
        tableCode: row.mesa_codigo,
        tableName: row.mesa_nombre,
        tableStatus: 'PENDIENTE_PAGO',
        lines: [line],
        total: Number(row.total_pedido),
      })
    }
  }
  return [...orders.values()].sort((a, b) => a.createdAt.localeCompare(b.createdAt) || a.orderId - b.orderId)
}

export function createCashierService(client: Pick<SupabaseClient, 'rpc'>) {
  return {
    async getPendingOrders(context: ValidatedProfileContext): Promise<CashierResult<readonly CashierPendingOrder[]>> {
      if (context.role.codigo !== 'CAJA') return { ok: false, error: { kind: 'unauthorized', message: 'No tienes autorización para consultar caja.' } }
      try {
        const result = await client.rpc('obtener_pedidos_pendientes_pago_caja')
        if (result.error) return { ok: false, error: { kind: 'operation-error', message: 'No pudimos cargar los pedidos pendientes. Intenta nuevamente.' } }
        return { ok: true, data: groupCashierOrders((result.data ?? []) as PendingRow[]) }
      } catch {
        return { ok: false, error: { kind: 'operation-error', message: 'No pudimos cargar los pedidos pendientes. Intenta nuevamente.' } }
      }
    },

    async registerPayment(context: ValidatedProfileContext, orderId: number, method: PaymentMethodCode): Promise<CashierResult<PersistedPayment>> {
      if (context.role.codigo !== 'CAJA') return { ok: false, error: { kind: 'unauthorized', message: 'No tienes autorización para registrar pagos.' } }
      if (!methods.has(method)) return { ok: false, error: { kind: 'operation-error', message: 'Selecciona un medio de pago válido.' } }
      try {
        const result = await client.rpc('registrar_pago_pedido', { p_pedido_id: orderId, p_medio: method })
        const row = (result.data as PaymentRow[] | null)?.[0]
        if (result.error) {
          const conflict = result.error.code === '40001' || result.error.code === '23505'
          return { ok: false, error: { kind: conflict ? 'conflict' : 'operation-error', message: conflict ? 'Este pedido ya fue procesado. Actualizamos la lista de caja.' : 'No pudimos registrar el pago. No se realizó ningún cobro.' } }
        }
        if (!row || row.pedido_estado !== 'PAGADO' || row.mesa_estado !== 'LIBRE') {
          return { ok: false, error: { kind: 'operation-error', message: 'No pudimos confirmar el resultado persistido del pago.' } }
        }
        return { ok: true, data: { paymentId: row.pago_id, orderId: row.pedido_id, orderStatus: 'PAGADO', tableId: row.mesa_id, tableStatus: 'LIBRE', amount: Number(row.importe), method: row.medio, paidAt: row.pagado_en } }
      } catch {
        return { ok: false, error: { kind: 'operation-error', message: 'No pudimos registrar el pago. No se realizó ningún cobro.' } }
      }
    },
  }
}
