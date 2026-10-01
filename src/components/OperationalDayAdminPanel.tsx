import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import type { ValidatedProfileContext } from "../services/profileContext";
import { getSupabaseClient } from "../services/supabaseClient";
import {
  createOperationalDayService,
  subscribeToOperationalDay,
  type OperationalDay,
  type OperationalDayBlocker,
} from "../services/operationalDayService.ts";

const time = new Intl.DateTimeFormat("es-PE", { hour: "2-digit", minute: "2-digit", timeZone: "America/Lima" });
const day = new Intl.DateTimeFormat("es-PE", { day: "2-digit", month: "2-digit", timeZone: "America/Lima" });
const limaDate = new Intl.DateTimeFormat("en-CA", { timeZone: "America/Lima" });

/** E9-D14: "abierta por X a las hh:mm" y, si la jornada cruzó la medianoche, "desde el dd/mm". */
export function describeOpenDay(jornada: OperationalDay, now: Date = new Date()): string {
  const opened = new Date(jornada.abiertaEn);
  const reference = jornada.servidorAhora ? new Date(jornada.servidorAhora) : now;
  const since = limaDate.format(opened) !== limaDate.format(reference) ? ` desde el ${day.format(opened)}` : "";
  return `abierta por ${jornada.abiertaPorNombre} a las ${time.format(opened)}${since}`;
}

type Confirming = "OPEN" | "CLOSE" | null;

/**
 * E9-D14: administración de la jornada operativa en Inicio. Sin métricas ni totales; el servidor decide
 * todo (local, fecha, número, actor, hora y condiciones de cierre).
 */
export default function OperationalDayAdminPanel({ context, onCash, onOrders }: {
  readonly context: ValidatedProfileContext;
  readonly onCash: () => void;
  readonly onOrders: () => void;
}) {
  const clientResult = useMemo(() => getSupabaseClient(), []);
  const service = useMemo(() => (clientResult.ok ? createOperationalDayService(clientResult.client) : null), [clientResult]);
  const [jornada, setJornada] = useState<OperationalDay | null>(null);
  const [loaded, setLoaded] = useState(false);
  const [busy, setBusy] = useState(false);
  const [confirming, setConfirming] = useState<Confirming>(null);
  const [error, setError] = useState<string | null>(null);
  const [notice, setNotice] = useState<string | null>(null);
  const [blockers, setBlockers] = useState<readonly OperationalDayBlocker[] | null>(null);
  const pending = useRef(false);
  const openKey = useRef<string | null>(null);

  const load = useCallback(async (isCurrent: () => boolean = () => true) => {
    if (!service) { setError("No pudimos conectar con el estado del local."); setLoaded(true); return; }
    const result = await service.getCurrent();
    if (!isCurrent()) return;
    if (!result.ok) setError(result.error.message);
    else { setJornada(result.data); setError(null); }
    setLoaded(true);
  }, [service]);

  useEffect(() => {
    let disposed = false;
    let handle: Awaited<ReturnType<typeof subscribeToOperationalDay>> | null = null;
    void load(() => !disposed);
    if (clientResult.ok) {
      void subscribeToOperationalDay(clientResult.client, () => load(() => !disposed), () => {}, { channelName: "admin-operational-day" })
        .then((started) => { if (disposed) void started.stop(); else handle = started; });
    }
    return () => { disposed = true; if (handle) void handle.stop(); };
  }, [clientResult, load]);

  async function run(action: () => Promise<void>): Promise<void> {
    if (pending.current) return;
    pending.current = true;
    setBusy(true);
    setError(null);
    setNotice(null);
    try { await action(); } finally { pending.current = false; setBusy(false); }
  }

  const openDay = () => run(async () => {
    if (!service) return;
    openKey.current ??= crypto.randomUUID();
    const result = await service.open(context, openKey.current);
    if (!result.ok) { setError(result.error.message); return; }
    openKey.current = null;
    setConfirming(null);
    setBlockers(null);
    setNotice(result.data.yaExistia ? `La jornada ya estaba abierta: ${result.data.identificacion}.` : `${result.data.identificacion} abierta.`);
    await load();
  });

  const closeDay = () => run(async () => {
    if (!service || !jornada) return;
    const result = await service.close(context, jornada.id);
    if (!result.ok) {
      setError(result.error.message);
      if (result.error.kind === "conflict") {
        const pendingItems = await service.getClosingBlockers(context);
        setBlockers(pendingItems.ok ? pendingItems.data : null);
      }
      setConfirming(null);
      await load();
      return;
    }
    setConfirming(null);
    setBlockers(null);
    setNotice(result.data.yaEstabaCerrada ? `La jornada ya estaba cerrada: ${result.data.identificacion}.` : `${result.data.identificacion} cerrada.`);
    await load();
  });

  const primary = "min-h-11 rounded-xl bg-emerald-800 px-4 text-sm font-bold text-white disabled:opacity-60";
  const secondary = "min-h-11 rounded-xl border border-stone-300 bg-white px-4 text-sm font-semibold disabled:opacity-60";

  return <section aria-labelledby="operational-day-title" className="mt-5 rounded-2xl border border-stone-200 bg-white p-4 shadow-sm sm:p-5">
    <div className="flex flex-wrap items-center justify-between gap-3">
      <div className="min-w-0">
        <h2 className="text-xl font-bold" id="operational-day-title">Jornada operativa</h2>
        {!loaded ? <p aria-busy="true" className="mt-1 text-sm text-stone-600">Verificando el estado del local…</p>
          : jornada ? <p className="mt-1 text-sm text-stone-600"><b className="text-stone-950">{jornada.identificacion}</b> · {describeOpenDay(jornada)}</p>
            : <p className="mt-1 text-sm font-semibold text-stone-700">Local cerrado</p>}
      </div>
      {loaded && <span className={`rounded-full px-3 py-1 text-xs font-bold ${jornada ? "bg-emerald-100 text-emerald-900" : "bg-stone-100 text-stone-700"}`}>{jornada ? "ABIERTA" : "CERRADO"}</span>}
    </div>

    {loaded && confirming === null && <div className="mt-4 flex flex-wrap gap-3">
      {jornada
        ? <button className={secondary} disabled={busy} onClick={() => setConfirming("CLOSE")} type="button">Cerrar jornada</button>
        : <button className={primary} disabled={busy} onClick={() => setConfirming("OPEN")} type="button">Abrir jornada</button>}
    </div>}

    {confirming === "OPEN" && <div className="mt-4 rounded-xl border border-emerald-200 bg-emerald-50 p-3" role="group" aria-label="Confirmar apertura">
      <p className="text-sm font-semibold text-emerald-950">¿Abrir la jornada operativa del local? Mozo, Cocina y Caja podrán operar.</p>
      <div className="mt-3 flex flex-wrap gap-3">
        <button aria-busy={busy} className={primary} disabled={busy} onClick={() => void openDay()} type="button">{busy ? "Abriendo…" : "Confirmar apertura"}</button>
        <button className={secondary} disabled={busy} onClick={() => setConfirming(null)} type="button">Cancelar</button>
      </div>
    </div>}

    {confirming === "CLOSE" && <div className="mt-4 rounded-xl border border-amber-200 bg-amber-50 p-3" role="group" aria-label="Confirmar cierre">
      <p className="text-sm font-semibold text-amber-950">¿Cerrar {jornada?.identificacion}? Se verificará que no queden pedidos ni cajas abiertas.</p>
      <div className="mt-3 flex flex-wrap gap-3">
        <button aria-busy={busy} className={primary} disabled={busy} onClick={() => void closeDay()} type="button">{busy ? "Cerrando…" : "Confirmar cierre"}</button>
        <button className={secondary} disabled={busy} onClick={() => setConfirming(null)} type="button">Cancelar</button>
      </div>
    </div>}

    {notice && <p className="mt-3 rounded-xl bg-emerald-50 p-3 text-sm font-semibold text-emerald-900" role="status">{notice}</p>}
    {error && <div className="mt-3 rounded-xl border border-rose-200 bg-rose-50 p-3 text-sm text-rose-800" role="alert">{error} <button className="font-bold underline" onClick={() => void load()} type="button">Reintentar</button></div>}

    {blockers && blockers.length > 0 && <div className="mt-4 rounded-xl border border-stone-200 bg-stone-50 p-3 sm:p-4">
      <h3 className="font-bold">Pendientes para cerrar la jornada</h3>
      <p className="mt-1 text-sm text-stone-600">Cobra o anula los pedidos, cierra la caja y vuelve a cerrar la jornada.</p>
      <ul className="mt-3 divide-y divide-stone-200 text-sm">
        {blockers.map((item) => <li className="flex min-w-0 flex-wrap justify-between gap-2 py-2" key={`${item.tipo}-${item.pedidoId ?? item.sesionCajaId}`}>
          {item.tipo === "PEDIDO"
            ? <span className="min-w-0"><b>Mesa {item.mesaCodigo}</b> · Pedido #{item.pedidoId} · {item.estado.replaceAll("_", " ")}</span>
            : <span className="min-w-0"><b>Caja {item.cajaCodigo}</b> · abierta por {item.abiertaPorNombre}{item.desde ? ` a las ${time.format(new Date(item.desde))}` : ""}</span>}
        </li>)}
      </ul>
      <div className="mt-3 flex flex-wrap gap-3">
        <button className={secondary} onClick={onOrders} type="button">Ver pedidos</button>
        <button className={secondary} onClick={onCash} type="button">Ver caja</button>
      </div>
    </div>}
  </section>;
}
