import type { SupabaseClient } from '@supabase/supabase-js'
import type { ValidatedProfileContext } from './profileContext'

export interface SalesSummary { readonly method: string; readonly paidOrders: number; readonly amount: number }
export interface SaleExport { readonly pedido_id: number; readonly mesa: string; readonly pagado_en: string; readonly medio: string; readonly importe: number | string }
export interface ProductExport { readonly codigo_categoria: string; readonly categoria: string; readonly codigo_producto: string; readonly producto: string; readonly precio: number | string; readonly activo: boolean }
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
