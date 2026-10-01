import { useCallback, useEffect, useMemo, useState } from "react";
import type { ValidatedProfileContext } from "../services/profileContext";
import { getSupabaseClient } from "../services/supabaseClient";
import { createOperationalDayService, type OperationalDayHistoryItem } from "../services/operationalDayService.ts";

export const OPERATIONAL_DAY_PAGE_SIZE = 20;
const dateTime = new Intl.DateTimeFormat("es-PE", { day: "2-digit", month: "2-digit", year: "numeric", hour: "2-digit", minute: "2-digit", timeZone: "America/Lima" });

/** E9-D14 / E9-R25: historial de jornadas del local, más reciente primero, sin totales ni métricas (E8). */
export default function AdminOperationalDaysPage({ context }: { readonly context: ValidatedProfileContext }) {
  const clientResult = useMemo(() => getSupabaseClient(), []);
  const service = useMemo(() => (clientResult.ok ? createOperationalDayService(clientResult.client) : null), [clientResult]);
  const [items, setItems] = useState<readonly OperationalDayHistoryItem[]>([]);
  const [hasMore, setHasMore] = useState(false);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  const load = useCallback(async (offset: number) => {
    if (!service) { setError("No pudimos conectar con el historial."); setLoading(false); return; }
    setLoading(true);
    const result = await service.getHistory(context, OPERATIONAL_DAY_PAGE_SIZE, offset);
    if (!result.ok) setError(result.error.message);
    else {
      setError(null);
      setItems((current) => (offset === 0 ? result.data : [...current, ...result.data]));
      setHasMore(result.data.length === OPERATIONAL_DAY_PAGE_SIZE);
    }
    setLoading(false);
  }, [context, service]);

  useEffect(() => { void load(0); }, [load]);

  return <main className="mx-auto max-w-5xl px-3 py-5 sm:px-6 sm:py-7">
    <p className="text-sm font-semibold uppercase tracking-[0.16em] text-emerald-700">Operación</p>
    <div className="mt-1 flex flex-wrap items-end justify-between gap-3">
      <h1 className="text-2xl font-bold sm:text-3xl">Jornadas</h1>
      <button className="min-h-11 rounded-xl border border-stone-300 bg-white px-4 text-sm font-semibold" disabled={loading} onClick={() => void load(0)} type="button">Actualizar</button>
    </div>
    <p className="mt-1 text-sm text-stone-600">Historial de aperturas y cierres de {context.local.nombre}.</p>
    {error && <div className="mt-4 rounded-xl border border-rose-200 bg-rose-50 p-4 text-rose-800" role="alert">{error} <button className="font-bold underline" onClick={() => void load(0)} type="button">Reintentar</button></div>}
    {!error && !loading && items.length === 0 && <p className="mt-5 rounded-2xl border border-stone-200 bg-white p-5 text-stone-600">Todavía no se registraron jornadas.</p>}
    {items.length > 0 && <div aria-label="Historial de jornadas" className="mt-5 rounded-2xl border border-stone-200 bg-white p-2 shadow-sm sm:p-3" role="table">
      <div className="hidden grid-cols-[2fr_1fr_2fr_2fr] gap-3 border-b border-stone-300 px-3 pb-2 text-xs font-bold uppercase tracking-wide text-stone-500 sm:grid" role="row">
        <span role="columnheader">Jornada</span><span role="columnheader">Estado</span><span role="columnheader">Apertura</span><span role="columnheader">Cierre</span>
      </div>
      {items.map((item) => <div className="grid grid-cols-1 gap-1 border-b border-stone-200 px-3 py-3 text-sm last:border-0 sm:grid-cols-[2fr_1fr_2fr_2fr] sm:items-center sm:gap-3" key={item.id} role="row">
        <b className="min-w-0 break-words" role="cell">{item.identificacion}</b>
        <span role="cell"><span className={`rounded-full px-2.5 py-1 text-xs font-bold ${item.estado === "ABIERTA" ? "bg-emerald-100 text-emerald-900" : "bg-stone-100 text-stone-700"}`}>{item.estado}</span></span>
        <span className="min-w-0" role="cell"><small className="block text-stone-500 sm:hidden">Apertura</small>{item.abiertaPorNombre} · {dateTime.format(new Date(item.abiertaEn))}</span>
        <span className="min-w-0" role="cell"><small className="block text-stone-500 sm:hidden">Cierre</small>{item.cerradaEn ? `${item.cerradaPorNombre ?? "—"} · ${dateTime.format(new Date(item.cerradaEn))}` : "—"}</span>
      </div>)}
    </div>}
    {loading && <p aria-busy="true" className="mt-4 text-sm text-stone-600">Cargando jornadas…</p>}
    {hasMore && !loading && <button className="mt-4 min-h-11 rounded-xl border border-stone-300 bg-white px-4 text-sm font-semibold" onClick={() => void load(items.length)} type="button">Cargar más</button>}
  </main>;
}
