import type { SupabaseClient } from '@supabase/supabase-js'
import type { ValidatedProfileContext } from './profileContext'

export interface SalesSummary { readonly method: string; readonly paidOrders: number; readonly amount: number }
export interface SaleExport { readonly pedido_id: number; readonly mesa: string; readonly pagado_en: string; readonly medio: string; readonly importe: number | string }
export interface ProductExport { readonly codigo_categoria: string; readonly categoria: string; readonly codigo_producto: string; readonly producto: string; readonly precio: number | string; readonly activo: boolean }
export interface DailyCashSummary {
  readonly operationalDate: string; readonly totalSold: number
  readonly salesByMethod: Readonly<Record<string, number>>
  readonly totalTips: number; readonly tipsByMethod: Readonly<Record<string, number>>
  readonly discounts: number; readonly annulments: number; readonly payments: number
  readonly partialPayments: number; readonly completedOrders: number
}
export interface SessionCashReport {
  readonly sessionId: string; readonly cashbox: string; readonly status: string
  readonly openedBy: string; readonly closedBy: string | null
  readonly openedAt: string; readonly closedAt: string | null
  readonly initialAmount: number; readonly expectedCash: number
  readonly countedCash: number | null; readonly difference: number | null
  readonly entries: number; readonly exits: number; readonly discounts: number
  readonly annulments: number; readonly payments: number; readonly partialPayments: number
  readonly completedOrders: number; readonly salesByMethod: Readonly<Record<string, number>>
  readonly tipsByMethod: Readonly<Record<string, number>>
}
export type SalesResult<T> = { readonly ok: true; readonly data: T } | { readonly ok: false; readonly error: string }

const allowedRoles = new Set(['ADMINISTRADOR', 'CAJA'])
export function csv(rows: readonly Record<string, unknown>[]): string {
  if (!rows.length) return ''
  const keys = Object.keys(rows[0])
  const quote = (value: unknown) => `"${String(value ?? '').replaceAll('"', '""')}"`
  return `${[keys.map(quote).join(','), ...rows.map((row) => keys.map((key) => quote(row[key])).join(','))].join('\r\n')}\r\n`
}

export function createSalesService(client: Pick<SupabaseClient, 'rpc'>) {
  return {
    async getDailyCashSummary(context: ValidatedProfileContext): Promise<SalesResult<DailyCashSummary>> {
      if (!allowedRoles.has(context.role.codigo)) return { ok: false, error: 'No tienes autorización para consultar caja.' }
      try {
        const result = await client.rpc('rpc_obtener_resumen_diario_caja')
        if (result.error || !result.data?.[0]) return { ok: false, error: 'No pudimos cargar el resumen diario.' }
        const row = result.data[0] as Record<string, string | number>
        return { ok: true, data: mapDaily(row) }
      } catch { return { ok: false, error: 'No pudimos cargar el resumen diario.' } }
    },
    async getSessionReports(context: ValidatedProfileContext): Promise<SalesResult<readonly SessionCashReport[]>> {
      if (!allowedRoles.has(context.role.codigo)) return { ok: false, error: 'No tienes autorización para consultar caja.' }
      try {
        const result = await client.rpc('rpc_obtener_reportes_sesion_caja', { p_sesion_caja_id: null })
        return result.error ? { ok: false, error: 'No pudimos cargar las sesiones.' } : { ok: true, data: ((result.data ?? []) as Record<string, unknown>[]).map(mapSession) }
      } catch { return { ok: false, error: 'No pudimos cargar las sesiones.' } }
    },
    async getSummary(context: ValidatedProfileContext): Promise<SalesResult<readonly SalesSummary[]>> {
      if (!allowedRoles.has(context.role.codigo)) return { ok: false, error: 'No tienes autorización para consultar ventas.' }
      try { const result = await client.rpc('obtener_resumen_ventas_hoy'); if (result.error) return { ok: false, error: 'No pudimos cargar las ventas del día.' }; return { ok: true, data: ((result.data ?? []) as Array<{ medio: string; pedidos_pagados: number; importe: number | string }>).map((row) => ({ method: row.medio, paidOrders: Number(row.pedidos_pagados), amount: Number(row.importe) })) } } catch { return { ok: false, error: 'No pudimos cargar las ventas del día.' } }
    },
    async exportSales(context: ValidatedProfileContext): Promise<SalesResult<readonly SaleExport[]>> {
      if (context.role.codigo !== 'ADMINISTRADOR') return { ok: false, error: 'No tienes autorización para exportar ventas.' }
      try { const result = await client.rpc('exportar_ventas_hoy'); return result.error ? { ok: false, error: 'No pudimos exportar las ventas.' } : { ok: true, data: (result.data ?? []) as SaleExport[] } } catch { return { ok: false, error: 'No pudimos exportar las ventas.' } }
    },
    async exportProducts(context: ValidatedProfileContext): Promise<SalesResult<readonly ProductExport[]>> {
      if (context.role.codigo !== 'ADMINISTRADOR') return { ok: false, error: 'No tienes autorización para exportar productos.' }
      try { const result = await client.rpc('exportar_productos_local'); return result.error ? { ok: false, error: 'No pudimos exportar los productos.' } : { ok: true, data: (result.data ?? []) as ProductExport[] } } catch { return { ok: false, error: 'No pudimos exportar los productos.' } }
    },
  }
}

const amount = (row: Record<string, unknown>, key: string) => Number(row[key] ?? 0)
function mapDaily(row: Record<string, string | number>): DailyCashSummary {
  return {
    operationalDate: String(row.fecha_operativa), totalSold: Number(row.total_vendido),
    salesByMethod: { EFECTIVO: Number(row.venta_efectivo), YAPE: Number(row.venta_yape), PLIN: Number(row.venta_plin), TARJETA: Number(row.venta_tarjeta) },
    totalTips: Number(row.total_propinas), tipsByMethod: { EFECTIVO: Number(row.propina_efectivo), YAPE: Number(row.propina_yape), PLIN: Number(row.propina_plin), TARJETA: Number(row.propina_tarjeta) },
    discounts: Number(row.descuentos), annulments: Number(row.cantidad_anulaciones), payments: Number(row.cantidad_pagos), partialPayments: Number(row.pagos_parciales), completedOrders: Number(row.cantidad_pedidos_completados),
  }
}
function mapSession(row: Record<string, unknown>): SessionCashReport {
  return {
    sessionId: String(row.sesion_caja_id), cashbox: `${String(row.caja_codigo)} · ${String(row.caja_nombre)}`, status: String(row.estado),
    openedBy: String(row.abierta_por_nombre), closedBy: row.cerrada_por_nombre == null ? null : String(row.cerrada_por_nombre), openedAt: String(row.abierta_en), closedAt: row.cerrada_en == null ? null : String(row.cerrada_en),
    initialAmount: amount(row, 'monto_inicial'), expectedCash: amount(row, 'efectivo_esperado'), countedCash: row.efectivo_contado == null ? null : amount(row, 'efectivo_contado'), difference: row.diferencia == null ? null : amount(row, 'diferencia'), entries: amount(row, 'entradas'), exits: amount(row, 'salidas'), discounts: amount(row, 'descuentos'), annulments: amount(row, 'cantidad_anulaciones'), payments: amount(row, 'cantidad_pagos'), partialPayments: amount(row, 'pagos_parciales'), completedOrders: amount(row, 'cantidad_pedidos_completados'),
    salesByMethod: { EFECTIVO: amount(row, 'venta_efectivo'), YAPE: amount(row, 'venta_yape'), PLIN: amount(row, 'venta_plin'), TARJETA: amount(row, 'venta_tarjeta') }, tipsByMethod: { EFECTIVO: amount(row, 'propina_efectivo'), YAPE: amount(row, 'propina_yape'), PLIN: amount(row, 'propina_plin'), TARJETA: amount(row, 'propina_tarjeta') },
  }
}
