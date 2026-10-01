import type { SupabaseClient } from '@supabase/supabase-js'
import type { ValidatedProfileContext } from './profileContext'
import { subscriptionTopic } from './operationsRealtimeService.ts'

/** E9-R09/R11: texto exacto de la pantalla de local cerrado y del rechazo PT409 de PostgreSQL. */
export const LOCAL_CLOSED_MESSAGE = 'Local cerrado — el sistema no se encuentra aperturado'

export interface OperationalDay {
  readonly id: number
  readonly identificacion: string
  readonly fechaOperativa: string
  readonly numero: number
  readonly abiertaEn: string
  readonly abiertaPorNombre: string
  readonly servidorAhora: string | null
}

export interface OperationalDayOpenResult {
  readonly id: number
  readonly identificacion: string
  readonly estado: 'ABIERTA' | 'CERRADA'
  readonly yaExistia: boolean
}

export interface OperationalDayCloseResult {
  readonly id: number
  readonly identificacion: string
  readonly cerradaEn: string | null
  readonly yaEstabaCerrada: boolean
}

export interface OperationalDayBlocker {
  readonly tipo: 'PEDIDO' | 'SESION_CAJA'
  readonly pedidoId: number | null
  readonly mesaCodigo: string | null
  readonly estado: string
  readonly sesionCajaId: string | null
  readonly cajaCodigo: string | null
  readonly abiertaPorNombre: string | null
  readonly desde: string | null
}

export interface OperationalDayHistoryItem {
  readonly id: number
  readonly identificacion: string
  readonly estado: 'ABIERTA' | 'CERRADA'
  readonly abiertaPorNombre: string
  readonly abiertaEn: string
  readonly cerradaPorNombre: string | null
  readonly cerradaEn: string | null
}

export type OperationalDayResult<T> =
  | { readonly ok: true; readonly data: T }
  | { readonly ok: false; readonly error: { readonly kind: 'conflict' | 'local-closed' | 'operation-error'; readonly message: string } }

interface CurrentRow {
  readonly jornada_operativa_id: number
  readonly identificacion: string
  readonly fecha_operativa: string
  readonly numero: number
  readonly abierta_en: string
  readonly abierta_por_nombre: string
  readonly servidor_ahora: string | null
}

interface RpcErrorLike { readonly code?: string; readonly message?: string }

type OperationalDayClient = Pick<SupabaseClient, 'rpc'>

/** E9-D13: un PT409 de PostgreSQL con el mensaje de local cerrado obliga a resincronizar el estado del local. */
export function isLocalClosedError(error: RpcErrorLike | null | undefined): boolean {
  return error?.code === 'PT409' && error.message === LOCAL_CLOSED_MESSAGE
}

export function mapCurrentOperationalDay(rows: readonly CurrentRow[] | null | undefined): OperationalDay | null {
  const row = rows?.[0]
  if (!row) return null
  return {
    id: Number(row.jornada_operativa_id),
    identificacion: row.identificacion,
    fechaOperativa: row.fecha_operativa,
    numero: Number(row.numero),
    abiertaEn: row.abierta_en,
    abiertaPorNombre: row.abierta_por_nombre,
    servidorAhora: row.servidor_ahora ?? null,
  }
}

function failure(error: RpcErrorLike | null | undefined, fallback: string): OperationalDayResult<never> {
  if (isLocalClosedError(error)) return { ok: false, error: { kind: 'local-closed', message: LOCAL_CLOSED_MESSAGE } }
  if (error?.code === 'PT409') return { ok: false, error: { kind: 'conflict', message: error.message || fallback } }
  return { ok: false, error: { kind: 'operation-error', message: fallback } }
}

const isAdmin = (context: ValidatedProfileContext) => context.role.codigo === 'ADMINISTRADOR'
const unauthorized: OperationalDayResult<never> = { ok: false, error: { kind: 'operation-error', message: 'No tienes autorización para administrar la jornada.' } }

export function createOperationalDayService(client: OperationalDayClient) {
  return {
    /** E9-D10: estado del local para cualquier rol; `null` = local cerrado. */
    async getCurrent(): Promise<OperationalDayResult<OperationalDay | null>> {
      try {
        const result = await client.rpc('rpc_obtener_jornada_operativa_actual')
        if (result.error) return failure(result.error, 'No pudimos verificar el estado del local.')
        return { ok: true, data: mapCurrentOperationalDay(result.data as CurrentRow[] | null) }
      } catch {
        return failure(null, 'No pudimos verificar el estado del local.')
      }
    },

    /** E9-D07: el servidor decide local, fecha, número, actor y hora; el cliente sólo envía la clave de solicitud. */
    async open(context: ValidatedProfileContext, idempotencyKey: string): Promise<OperationalDayResult<OperationalDayOpenResult>> {
      if (!isAdmin(context)) return unauthorized
      try {
        const result = await client.rpc('rpc_abrir_jornada_operativa', { p_idempotency_key: idempotencyKey })
        const row = (result.data as { jornada_operativa_id: number; identificacion: string; estado: 'ABIERTA' | 'CERRADA'; ya_existia: boolean }[] | null)?.[0]
        if (result.error || !row) return failure(result.error, 'No pudimos abrir la jornada. Intenta nuevamente.')
        return { ok: true, data: { id: Number(row.jornada_operativa_id), identificacion: row.identificacion, estado: row.estado, yaExistia: row.ya_existia } }
      } catch {
        return failure(null, 'No pudimos abrir la jornada. Intenta nuevamente.')
      }
    },

    /** E9-D08: sólo cierra sin pendientes; un PT409 trae los conteos de PostgreSQL. */
    async close(context: ValidatedProfileContext, operationalDayId: number): Promise<OperationalDayResult<OperationalDayCloseResult>> {
      if (!isAdmin(context)) return unauthorized
      try {
        const result = await client.rpc('rpc_cerrar_jornada_operativa', { p_jornada_operativa_id: operationalDayId })
        const row = (result.data as { jornada_operativa_id: number; identificacion: string; cerrada_en: string | null; ya_estaba_cerrada: boolean }[] | null)?.[0]
        if (result.error || !row) return failure(result.error, 'No pudimos cerrar la jornada. Intenta nuevamente.')
        return { ok: true, data: { id: Number(row.jornada_operativa_id), identificacion: row.identificacion, cerradaEn: row.cerrada_en, yaEstabaCerrada: row.ya_estaba_cerrada } }
      } catch {
        return failure(null, 'No pudimos cerrar la jornada. Intenta nuevamente.')
      }
    },

    async getClosingBlockers(context: ValidatedProfileContext): Promise<OperationalDayResult<readonly OperationalDayBlocker[]>> {
      if (!isAdmin(context)) return unauthorized
      try {
        const result = await client.rpc('rpc_obtener_pendientes_cierre_jornada')
        if (result.error) return failure(result.error, 'No pudimos cargar los pendientes de cierre.')
        const rows = (result.data ?? []) as {
          tipo: 'PEDIDO' | 'SESION_CAJA'; pedido_id: number | null; mesa_codigo: string | null; estado: string
          sesion_caja_id: string | null; caja_codigo: string | null; abierta_por_nombre: string | null; desde: string | null
        }[]
        return { ok: true, data: rows.map((row) => ({
          tipo: row.tipo, pedidoId: row.pedido_id === null ? null : Number(row.pedido_id), mesaCodigo: row.mesa_codigo, estado: row.estado,
          sesionCajaId: row.sesion_caja_id, cajaCodigo: row.caja_codigo, abiertaPorNombre: row.abierta_por_nombre, desde: row.desde,
        })) }
      } catch {
        return failure(null, 'No pudimos cargar los pendientes de cierre.')
      }
    },

    async getHistory(context: ValidatedProfileContext, limit: number, offset: number): Promise<OperationalDayResult<readonly OperationalDayHistoryItem[]>> {
      if (!isAdmin(context)) return unauthorized
      try {
        const result = await client.rpc('rpc_obtener_historial_jornadas_operativas', { p_limite: limit, p_offset: offset })
        if (result.error) return failure(result.error, 'No pudimos cargar el historial de jornadas.')
        const rows = (result.data ?? []) as {
          jornada_operativa_id: number; identificacion: string; estado: 'ABIERTA' | 'CERRADA'; abierta_por_nombre: string
          abierta_en: string; cerrada_por_nombre: string | null; cerrada_en: string | null
        }[]
        return { ok: true, data: rows.map((row) => ({
          id: Number(row.jornada_operativa_id), identificacion: row.identificacion, estado: row.estado, abiertaPorNombre: row.abierta_por_nombre,
          abiertaEn: row.abierta_en, cerradaPorNombre: row.cerrada_por_nombre, cerradaEn: row.cerrada_en,
        })) }
      } catch {
        return failure(null, 'No pudimos cargar el historial de jornadas.')
      }
    },
  }
}

export interface OperationalDayRealtimeHandle {
  readonly resync: () => Promise<void>
  readonly stop: () => Promise<void>
}

interface OperationalDayRealtimeOptions {
  readonly channelName: string
  readonly debounceMs?: number
  readonly setTimeoutFn?: typeof setTimeout
  readonly clearTimeoutFn?: typeof clearTimeout
}

type OperationalDayRealtimeClient = Pick<SupabaseClient, 'channel' | 'removeChannel'>

/**
 * E9-D12: señal Realtime de apertura/cierre. Reutiliza el patrón vigente de operationsRealtimeService sin
 * modificarlo: topic propio por suscripción (subscriptionTopic, corrección E7-T12), INSERT/UPDATE como señal,
 * debounce y coalescencia, relectura en SUBSCRIBED y resincronización ante error. Los payloads no se usan como
 * dato; sin polling.
 */
export async function subscribeToOperationalDay(
  client: OperationalDayRealtimeClient,
  refreshSnapshot: () => Promise<void>,
  onConnectionError: () => void,
  options: OperationalDayRealtimeOptions,
): Promise<OperationalDayRealtimeHandle> {
  const debounceMs = options.debounceMs ?? 80
  const scheduleTimeout = options.setTimeoutFn ?? setTimeout
  const cancelTimeout = options.clearTimeoutFn ?? clearTimeout
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
    refreshInFlight = refreshSnapshot()
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

  const channel = client.channel(subscriptionTopic(options.channelName))
  for (const event of ['INSERT', 'UPDATE'] as const) {
    channel.on('postgres_changes', { event, schema: 'public', table: 'jornada_operativa' }, scheduleRefresh)
  }
  channel.subscribe((status) => {
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
      refreshAgain = false
      if (refreshTimer !== null) {
        cancelTimeout(refreshTimer)
        refreshTimer = null
      }
      await client.removeChannel(channel)
    },
  }
}
