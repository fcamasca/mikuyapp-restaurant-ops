// TEMPORAL — E7-T12/TH06: panel de diagnóstico Realtime (visible sólo con ?rtdebug=1). Retirar tras cerrar TH06.
import { useState, useSyncExternalStore } from 'react'
import { clearRealtimeDebugEntries, getRealtimeDebugEntries, isRealtimeDebugEnabled, realtimeDebugBuild, subscribeRealtimeDebug } from '../services/realtimeDebug'

let snapshot = getRealtimeDebugEntries()
subscribeRealtimeDebug(() => { snapshot = getRealtimeDebugEntries() })

export default function RealtimeDebugPanel() {
  const entries = useSyncExternalStore(subscribeRealtimeDebug, () => snapshot)
  const [open, setOpen] = useState(true)
  const [copied, setCopied] = useState(false)
  if (!isRealtimeDebugEnabled()) return null
  const supabaseHost = (() => { try { return new URL(import.meta.env.VITE_SUPABASE_URL ?? '').host } catch { return '?' } })()
  const text = [`build=${realtimeDebugBuild} supabase=${supabaseHost} ua=${navigator.userAgent}`, ...entries.map((entry) => `${entry.at} ${entry.scope}: ${entry.message}`)].join('\n')
  async function copy() {
    try { await navigator.clipboard.writeText(text); setCopied(true) } catch { setCopied(false) }
  }
  return (
    <aside className="fixed inset-x-2 bottom-2 z-50 max-h-[45vh] overflow-hidden rounded-xl border border-amber-400 bg-stone-950/95 text-[11px] text-amber-100 shadow-lg">
      <div className="flex flex-wrap items-center gap-2 border-b border-amber-700 px-2 py-1">
        <strong>RT debug · build {realtimeDebugBuild.slice(0, 7)} · {supabaseHost.split('.')[0].slice(0, 4)}…</strong>
        <button className="rounded border border-amber-500 px-2" onClick={() => setOpen((value) => !value)} type="button">{open ? 'Ocultar' : 'Mostrar'}</button>
        <button className="rounded border border-amber-500 px-2" onClick={() => { void copy() }} type="button">{copied ? 'Copiado' : 'Copiar'}</button>
        <button className="rounded border border-amber-500 px-2" onClick={clearRealtimeDebugEntries} type="button">Limpiar</button>
      </div>
      {open && <pre className="max-h-[38vh] overflow-auto whitespace-pre-wrap px-2 py-1">{text}</pre>}
    </aside>
  )
}
