import type { SupabaseClient } from '@supabase/supabase-js'
import { rtDescribeTopic, rtLog, rtLogSignal } from './realtimeDebug.ts'

export interface OperationsRealtimeHandle {
  readonly resync: () => Promise<void>
  readonly stop: () => Promise<void>
}

interface OperationsRealtimeOptions {
  readonly channelName: string
  readonly initialRefresh?: boolean
  readonly debounceMs?: number
  readonly setTimeoutFn?: typeof setTimeout
  readonly clearTimeoutFn?: typeof clearTimeout
}

type OperationsRealtimeClient = Pick<SupabaseClient, 'channel' | 'removeChannel'>

const signalTables = ['detalle_pedido', 'pedido', 'mesa'] as const
const signalEvents = ['INSERT', 'UPDATE'] as const

export async function subscribeToOperationsChanges(
  client: OperationsRealtimeClient,
  refreshSnapshot: () => Promise<void>,
  onConnectionError: () => void,
  options: OperationsRealtimeOptions,
): Promise<OperationsRealtimeHandle> {
  const debounceMs = options.debounceMs ?? 80
  const scheduleTimeout = options.setTimeoutFn ?? setTimeout
  const cancelTimeout = options.clearTimeoutFn ?? clearTimeout
  let stopped = false
  let refreshInFlight: Promise<void> | null = null
  let refreshAgain = false
  let refreshTimer: ReturnType<typeof setTimeout> | null = null

  const refresh = async (): Promise<void> => {
    if (stopped) { rtLog(options.channelName, 'refetch descartado: handle detenido'); return }
    if (refreshInFlight) {
      refreshAgain = true
      return refreshInFlight
    }
    rtLog(options.channelName, 'refetch iniciado')
    refreshInFlight = refreshSnapshot()
    try {
      await refreshInFlight
      rtLog(options.channelName, 'refetch terminado')
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

  if (options.initialRefresh !== false) await refresh()
  rtLog(options.channelName, `suscribiendo (${rtDescribeTopic(client, options.channelName)})`)
  const channel = client.channel(options.channelName)
  for (const table of signalTables) {
    for (const event of signalEvents) {
      channel.on('postgres_changes', { event, schema: 'public', table }, (signal: unknown) => {
        rtLogSignal(options.channelName, table, event, signal)
        scheduleRefresh()
      })
    }
  }
  channel.subscribe((status) => {
    rtLog(options.channelName, `estado ${status}${stopped ? ' (handle detenido, ignorado)' : ''}`)
    if (stopped) return
    if (status === 'SUBSCRIBED') {
      void refresh()
      return
    }
    if (status === 'CHANNEL_ERROR' || status === 'TIMED_OUT' || status === 'CLOSED') {
      onConnectionError()
      void refresh()
    }
  })

  return {
    resync: refresh,
    async stop(): Promise<void> {
      if (stopped) return
      stopped = true
      rtLog(options.channelName, `stop (${rtDescribeTopic(client, options.channelName)})`)
      refreshAgain = false
      if (refreshTimer !== null) {
        cancelTimeout(refreshTimer)
        refreshTimer = null
      }
      await client.removeChannel(channel)
    },
  }
}
