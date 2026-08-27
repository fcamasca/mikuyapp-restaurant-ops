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
  readonly onSnapshot: (rows: readonly KitchenBoardRow[]) => void
  readonly onError: (message: string) => void
}

export interface KitchenRealtimeHandle {
  readonly resync: () => Promise<void>
  readonly stop: () => Promise<void>
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
        if (result.error?.code === '40001') {
          return {
            ok: false,
            error: {
              kind: 'concurrent-conflict',
              message: 'Este producto fue actualizado desde otro dispositivo. Se cargó la versión más reciente.',
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

    async start(callbacks: KitchenRealtimeCallbacks): Promise<KitchenRealtimeHandle> {
      let stopped = false

      const refresh = async (): Promise<void> => {
        if (stopped) return
        try {
          const result = await client.rpc('obtener_tablero_cocina')
          if (stopped) return
          if (result.error) {
            callbacks.onError('No pudimos sincronizar el tablero de cocina. Revisa tu conexión.')
            return
          }
          callbacks.onSnapshot((result.data as KitchenBoardRow[] | null) ?? [])
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
