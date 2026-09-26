// TEMPORAL — E7-T12/TH06 (diagnóstico de la sincronización Realtime en Preview cloud). Retirar tras cerrar TH06.
// Se activa sólo con ?rtdebug=1 en la URL (queda activo en la pestaña vía sessionStorage; ?rtdebug=0 lo apaga).
// No registra tokens, claves ni datos personales: sólo nombres de canal, estados, tabla/evento, id y estado de filas.
export interface RealtimeDebugEntry { readonly at: string; readonly scope: string; readonly message: string }

const maxEntries = 300
const entries: RealtimeDebugEntry[] = []
const listeners = new Set<() => void>()
let enabledCache: boolean | null = null

export function isRealtimeDebugEnabled(): boolean {
  if (enabledCache !== null) return enabledCache
  let enabled = false
  try {
    if (typeof window !== 'undefined') {
      const flag = new URLSearchParams(window.location.search).get('rtdebug')
      if (flag === '1') window.sessionStorage.setItem('mikuy:rtdebug', '1')
      if (flag === '0') window.sessionStorage.removeItem('mikuy:rtdebug')
      enabled = window.sessionStorage.getItem('mikuy:rtdebug') === '1'
    }
  } catch { enabled = false }
  enabledCache = enabled
  return enabled
}

export function rtLog(scope: string, message: string): void {
  if (!isRealtimeDebugEnabled()) return
  const now = new Date()
  const at = `${now.toLocaleTimeString('es-PE', { hour12: false })}.${String(now.getMilliseconds()).padStart(3, '0')}`
  entries.push({ at, scope, message })
  if (entries.length > maxEntries) entries.splice(0, entries.length - maxEntries)
  console.info(`[MikuyRT ${at}] ${scope}: ${message}`)
  listeners.forEach((listener) => listener())
}

export function rtLogSignal(channelName: string, table: string, event: string, payload: unknown): void {
  if (!isRealtimeDebugEnabled()) return
  const record = (payload as { new?: Record<string, unknown> } | null)?.new ?? {}
  const committed = (payload as { commit_timestamp?: string } | null)?.commit_timestamp ?? '?'
  rtLog(channelName, `SEÑAL ${table} ${event} id=${String(record.id ?? '?')} estado=${String(record.estado ?? '?')} commit=${committed}`)
}

/** Describe los canales existentes en el cliente Realtime con el mismo topic (reutilización por nombre). */
export function rtDescribeTopic(client: unknown, channelName: string): string {
  try {
    const channels = (client as { getChannels?: () => { topic: string; state: string }[] }).getChannels?.() ?? []
    const same = channels.filter((channel) => channel.topic === `realtime:${channelName}`)
    return `canales=${channels.length} mismo_topic=${same.map((channel) => channel.state).join(',') || 'ninguno'}`
  } catch { return 'canales=?' }
}

export function getRealtimeDebugEntries(): readonly RealtimeDebugEntry[] { return entries.slice() }
export function clearRealtimeDebugEntries(): void { entries.length = 0; listeners.forEach((listener) => listener()) }
export function subscribeRealtimeDebug(listener: () => void): () => void { listeners.add(listener); return () => { listeners.delete(listener) } }
export const realtimeDebugBuild: string = typeof __MIKUY_BUILD__ === 'string' ? __MIKUY_BUILD__ : 'desconocido'
