import type { SupabaseClient } from '@supabase/supabase-js'

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
    const orderSource = pending.length > 0 ? pending : sorted
    return {
      key: pedidoId,
      pedidoId,
      pedidoEstado: sorted[0].pedido_estado,
      mesaCodigo: sorted[0].mesa_codigo,
      mesaNombre: sorted[0].mesa_nombre,
      details: sorted,
      oldestSentAt: orderSource[0].enviado_en,
    }
  }).sort((left, right) =>
    new Date(left.oldestSentAt).getTime() - new Date(right.oldestSentAt).getTime()
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

interface KitchenRealtimeOptions {
  readonly debounceMs?: number
  readonly setTimeoutFn?: typeof setTimeout
  readonly clearTimeoutFn?: typeof clearTimeout
}

type KitchenRealtimeClient = Pick<SupabaseClient, 'rpc' | 'channel' | 'removeChannel'>

const signalTables = ['detalle_pedido', 'pedido', 'mesa'] as const
const signalEvents = ['INSERT', 'UPDATE'] as const

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
      let refreshInFlight: Promise<void> | null = null
      let refreshAgain = false
      let refreshTimer: ReturnType<typeof setTimeout> | null = null

      const refresh = async (): Promise<void> => {
        if (stopped) return
        if (refreshInFlight) {
          refreshAgain = true
          return refreshInFlight
        }

        refreshInFlight = (async () => {
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
        })()

        try {
          await refreshInFlight
        } finally {
          refreshInFlight = null
          if (refreshAgain && !stopped) {
            refreshAgain = false
            void refresh()
          }
        }
      }

      const scheduleRefresh = (): void => {
        if (stopped) return
        if (refreshTimer !== null) cancelTimeout(refreshTimer)
        refreshTimer = scheduleTimeout(() => {
          refreshTimer = null
          void refresh()
        }, debounceMs)
      }

      await refresh()

      const channel = client.channel('kitchen-board-signals')
      for (const table of signalTables) {
        for (const event of signalEvents) {
          channel.on(
            'postgres_changes',
            { event, schema: 'public', table },
            scheduleRefresh,
          )
        }
      }

      channel.subscribe((status) => {
        if (stopped) return
        if (status === 'SUBSCRIBED') {
          void refresh()
          return
        }
        if (status === 'CHANNEL_ERROR' || status === 'TIMED_OUT' || status === 'CLOSED') {
          callbacks.onError('La conexión en tiempo real se interrumpió. Estamos recuperando los datos.')
          void refresh()
        }
      })

      return {
        resync: refresh,
        async stop(): Promise<void> {
          if (stopped) return
          stopped = true
          refreshAgain = false
          if (refreshTimer !== null) {
            cancelTimeout(refreshTimer)
            refreshTimer = null
          }
          await client.removeChannel(channel)
        },
      }
    },
  }
}
