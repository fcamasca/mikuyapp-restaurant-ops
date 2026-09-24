import type { SupabaseClient } from '@supabase/supabase-js'
import { subscribeToOperationsChanges } from './operationsRealtimeService.ts'

export type KitchenDetailStatus =
  | 'ENVIADO'
  | 'RECIBIDO_COCINA'
  | 'EN_PREPARACION'
  | 'LISTO'

export interface KitchenBoardRow {
  readonly pedido_id: number
  readonly pedido_estado: string
  readonly mesa_id: string
  readonly mesa_codigo: string
  readonly mesa_nombre: string
  readonly mesa_estado: string
  readonly detalle_id: number
  readonly producto_id: string
  readonly producto_codigo: string
  readonly producto_nombre: string
  readonly cantidad: number
  readonly observacion: string | null
  readonly estado: KitchenDetailStatus
  readonly enviado_en: string
  readonly modificado_en: string
}

/** E7-D08/D12: comanda documental incluida en el snapshot de cocina. */
export interface KitchenCommandLine {
  readonly detalle_id: number
  readonly producto_codigo: string
  readonly producto_nombre: string
  readonly cantidad: number
  readonly observacion: string | null
}

export interface KitchenCommand {
  readonly comanda_id: number
  readonly pedido_id: number
  readonly numero: number
  readonly mesa_codigo: string
  readonly mesa_nombre: string
  readonly enviado_en: string
  readonly creado_en: string
  readonly creado_por_nombre: string
  readonly lineas: readonly KitchenCommandLine[]
  readonly impresiones: number
  readonly primera_impresion_en: string | null
  readonly ultima_impresion_en: string | null
}

/** E7-D08/D10: cancelación por el mozo de un producto de cocina (sólo lectura). */
export interface KitchenCancellation {
  readonly pedido_id: number
  readonly detalle_id: number
  readonly producto_nombre: string
  readonly cantidad: number
  readonly observacion: string | null
  readonly estado_anterior: string
  readonly motivo: string
  readonly cancelado_en: string
}

export interface KitchenBoardSnapshot {
  readonly detalles: readonly KitchenBoardRow[]
  readonly comandas: readonly KitchenCommand[]
  readonly cancelaciones: readonly KitchenCancellation[]
}

/** Valida la forma del snapshot autoritativo de rpc_obtener_tablero_cocina. */
export function parseKitchenSnapshot(data: unknown): KitchenBoardSnapshot | null {
  if (!data || typeof data !== 'object' || Array.isArray(data)) return null
  const value = data as Record<string, unknown>
  if (!Array.isArray(value.detalles) || !Array.isArray(value.comandas) || !Array.isArray(value.cancelaciones)) return null
  return {
    detalles: value.detalles as KitchenBoardRow[],
    comandas: value.comandas as KitchenCommand[],
    cancelaciones: value.cancelaciones as KitchenCancellation[],
  }
}

/** Agrupa cancelaciones por pedido para mostrarlas junto a su grupo del tablero. */
export function groupKitchenCancellations(
  cancellations: readonly KitchenCancellation[],
): ReadonlyMap<number, readonly KitchenCancellation[]> {
  const byOrder = new Map<number, KitchenCancellation[]>()
  for (const item of cancellations) {
    const current = byOrder.get(item.pedido_id) ?? []
    current.push(item)
    byOrder.set(item.pedido_id, current)
  }
  return byOrder
}

/** Cantidad de detalles ENVIADO del grupo que procesaría la recepción completa. */
export function countPendingReception(details: readonly Pick<KitchenBoardRow, 'estado'>[]): number {
  return details.filter((detail) => detail.estado === 'ENVIADO').length
}

export interface KitchenOrderGroup {
  readonly key: number
  readonly pedidoId: number
  readonly pedidoEstado: string
  readonly mesaCodigo: string
  readonly mesaNombre: string
  readonly details: readonly KitchenBoardRow[]
  readonly oldestSentAt: string
  readonly allReady: boolean
}

export interface PendingKitchenTransition {
  readonly expectedStatus: KitchenDetailStatus
  readonly token: symbol
}

export function settleKitchenTransitionsFromSnapshot(
  pending: Map<number, PendingKitchenTransition>,
  snapshot: readonly KitchenBoardRow[],
): readonly number[] {
  const currentStatuses = new Map(snapshot.map((detail) => [detail.detalle_id, detail.estado] as const))
  const settled: number[] = []
  for (const [detailId, operation] of pending) {
    const persistedStatus = currentStatuses.get(detailId)
    if (persistedStatus === undefined || persistedStatus !== operation.expectedStatus) {
      pending.delete(detailId)
      settled.push(detailId)
    }
  }
  return settled
}

export function groupKitchenBoard(rows: readonly KitchenBoardRow[]): readonly KitchenOrderGroup[] {
  const groups = new Map<number, KitchenBoardRow[]>()
  for (const row of rows) {
    const current = groups.get(row.pedido_id) ?? []
    current.push(row)
    groups.set(row.pedido_id, current)
  }

  return [...groups.entries()].map(([pedidoId, details]) => {
    const sorted = [...details].sort((left, right) =>
      new Date(left.enviado_en).getTime() - new Date(right.enviado_en).getTime()
      || left.detalle_id - right.detalle_id)
    const pending = sorted.filter((detail) => detail.estado !== 'LISTO')
    const ready = sorted.filter((detail) => detail.estado === 'LISTO')
    const orderSource = pending.length > 0 ? pending : ready
    return {
      key: pedidoId,
      pedidoId,
      pedidoEstado: sorted[0].pedido_estado,
      mesaCodigo: sorted[0].mesa_codigo,
      mesaNombre: sorted[0].mesa_nombre,
      details: [...pending, ...ready],
      oldestSentAt: orderSource[0].enviado_en,
      allReady: pending.length === 0,
    }
  }).sort((left, right) =>
    Number(left.allReady) - Number(right.allReady)
    || new Date(left.oldestSentAt).getTime() - new Date(right.oldestSentAt).getTime()
    || left.pedidoId - right.pedidoId)
}

export function formatKitchenAge(sentAt: string, now = Date.now()): string {
  const elapsedMinutes = Math.max(0, Math.floor((now - new Date(sentAt).getTime()) / 60_000))
  if (elapsedMinutes < 1) return 'Enviado hace menos de 1 min'
  if (elapsedMinutes < 60) return `Enviado hace ${elapsedMinutes} min`
  const hours = Math.floor(elapsedMinutes / 60)
  const minutes = elapsedMinutes % 60
  return `Enviado hace ${hours} h${minutes > 0 ? ` ${minutes} min` : ''}`
}

export interface KitchenRealtimeCallbacks {
  readonly onSnapshot: (rows: readonly KitchenBoardRow[], snapshot: KitchenBoardSnapshot) => void
  readonly onError: (message: string) => void
}

export interface KitchenRealtimeHandle {
  readonly resync: () => Promise<void>
  readonly stop: () => Promise<void>
}

export type KitchenReceiveResult =
  | { readonly ok: true; readonly received: number }
  | {
    readonly ok: false
    readonly error: {
      readonly kind: 'operation-error' | 'concurrent-conflict'
      readonly message: string
    }
  }

export type KitchenTransitionResult =
  | { readonly ok: true }
  | {
    readonly ok: false
    readonly error: {
      readonly kind: 'operation-error' | 'concurrent-conflict'
      readonly message: string
    }
  }

interface KitchenDetailMutationLifecycle {
  readonly operation: () => Promise<KitchenTransitionResult>
  readonly onResult: (result: KitchenTransitionResult) => void
  readonly releasePending: () => void
  readonly resync: () => Promise<void>
}

export async function runKitchenDetailMutation({
  operation,
  onResult,
  releasePending,
  resync,
}: KitchenDetailMutationLifecycle): Promise<void> {
  try {
    const result = await operation()
    onResult(result)
  } finally {
    releasePending()
  }
  await resync()
}

interface KitchenRealtimeOptions {
  readonly debounceMs?: number
  readonly setTimeoutFn?: typeof setTimeout
  readonly clearTimeoutFn?: typeof clearTimeout
}

type KitchenRealtimeClient = Pick<SupabaseClient, 'rpc' | 'channel' | 'removeChannel'>

export function createKitchenRealtimeService(
  client: KitchenRealtimeClient,
  options: KitchenRealtimeOptions = {},
) {
  const debounceMs = options.debounceMs ?? 80
  const scheduleTimeout = options.setTimeoutFn ?? setTimeout
  const cancelTimeout = options.clearTimeoutFn ?? clearTimeout

  return {
    async transitionDetail(
      detailId: number,
      expectedStatus: KitchenDetailStatus,
      newStatus: KitchenDetailStatus,
    ): Promise<KitchenTransitionResult> {
      const validTransition =
        (expectedStatus === 'ENVIADO' && newStatus === 'RECIBIDO_COCINA')
        || (expectedStatus === 'RECIBIDO_COCINA' && newStatus === 'EN_PREPARACION')
        || (expectedStatus === 'EN_PREPARACION' && newStatus === 'LISTO')
      if (!validTransition) {
        return {
          ok: false,
          error: { kind: 'operation-error', message: 'Esta acción ya no está disponible.' },
        }
      }

      try {
        const result = await client.rpc('actualizar_estado_detalle_cocina', {
          p_detalle_id: detailId,
          p_estado_esperado: expectedStatus,
          p_estado_nuevo: newStatus,
        })
        // PT409 es el código vigente para este conflicto (E1-T18); 40001 se
        // conserva temporalmente por compatibilidad.
        if (result.error?.code === 'PT409' || result.error?.code === '40001') {
          return {
            ok: false,
            error: {
              kind: 'concurrent-conflict',
              // E7-D10: el mozo pudo cancelar el producto mientras cocina actuaba.
              message: /cancelad/i.test(result.error.message ?? '')
                ? 'El mozo canceló este producto. Se cargó la versión más reciente.'
                : 'Este producto fue actualizado desde otro dispositivo. Se cargó la versión más reciente.',
            },
          }
        }
        if (result.error) {
          return {
            ok: false,
            error: {
              kind: 'operation-error',
              message: 'No pudimos actualizar este producto. Intenta nuevamente.',
            },
          }
        }
        return { ok: true }
      } catch {
        return {
          ok: false,
          error: {
            kind: 'operation-error',
            message: 'No pudimos actualizar este producto. Revisa tu conexión.',
          },
        }
      }
    },

    /** E7-D09: recepción completa del pedido (sólo ENVIADO con cocina); 0 recibidos es éxito sin cambios. */
    async receiveOrder(orderId: number): Promise<KitchenReceiveResult> {
      try {
        const result = await client.rpc('rpc_recibir_pedido_cocina', { p_pedido_id: orderId })
        if (result.error?.code === 'PT409') {
          return {
            ok: false,
            error: { kind: 'concurrent-conflict', message: 'Este pedido ya no está en cocina. Se cargó la versión más reciente.' },
          }
        }
        if (result.error) {
          return { ok: false, error: { kind: 'operation-error', message: 'No pudimos recibir el pedido. Intenta nuevamente.' } }
        }
        const row = (result.data as Array<{ detalles_recibidos: number }> | null)?.[0]
        return { ok: true, received: Number(row?.detalles_recibidos ?? 0) }
      } catch {
        return { ok: false, error: { kind: 'operation-error', message: 'No pudimos recibir el pedido. Revisa tu conexión.' } }
      }
    },

    async start(callbacks: KitchenRealtimeCallbacks): Promise<KitchenRealtimeHandle> {
      let stopped = false

      const refresh = async (): Promise<void> => {
        if (stopped) return
        try {
          // E7-D08: una sola lectura autoritativa por refresco (detalles con cocina, comandas y cancelaciones).
          const result = await client.rpc('rpc_obtener_tablero_cocina')
          if (stopped) return
          const snapshot = result.error ? null : parseKitchenSnapshot(result.data)
          if (!snapshot) {
            callbacks.onError('No pudimos sincronizar el tablero de cocina. Revisa tu conexión.')
            return
          }
          callbacks.onSnapshot(snapshot.detalles, snapshot)
        } catch {
          if (stopped) return
          callbacks.onError('No pudimos sincronizar el tablero de cocina. Revisa tu conexión.')
        }
      }
      const signals = await subscribeToOperationsChanges(client, refresh, () => {
        callbacks.onError('La conexión en tiempo real se interrumpió. Estamos recuperando los datos.')
      }, {
        channelName: 'kitchen-board-signals', debounceMs, setTimeoutFn: scheduleTimeout, clearTimeoutFn: cancelTimeout,
      })

      return {
        resync: signals.resync,
        async stop(): Promise<void> {
          if (stopped) return
          stopped = true
          await signals.stop()
        },
      }
    },
  }
}
