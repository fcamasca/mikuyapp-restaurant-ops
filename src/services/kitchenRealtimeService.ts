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

export interface KitchenRealtimeCallbacks {
  readonly onSnapshot: (rows: readonly KitchenBoardRow[]) => void
  readonly onError: (message: string) => void
}

export interface KitchenRealtimeHandle {
  readonly resync: () => Promise<void>
  readonly stop: () => Promise<void>
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
            if (result.error) {
              callbacks.onError('No pudimos sincronizar el tablero de cocina. Revisa tu conexión.')
              return
            }
            callbacks.onSnapshot((result.data as KitchenBoardRow[] | null) ?? [])
          } catch {
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
