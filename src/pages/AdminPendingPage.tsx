import CashAdministrationPanel from "../components/CashAdministrationPanel";
import type { ValidatedProfileContext } from "../services/profileContext";

export default function AdminPendingPage({ context }: { readonly context: ValidatedProfileContext }) {
  return <main className="mx-auto max-w-6xl px-3 py-5 sm:px-6 sm:py-7">
    <p className="text-sm font-semibold uppercase tracking-[0.16em] text-emerald-700">Operación</p>
    <h1 className="mt-1 text-2xl font-bold sm:text-3xl">Pendientes por aprobar</h1>
    <p className="mt-2 text-sm text-stone-600">Solicitudes de descuento que requieren tu decisión. Los cierres con diferencia se consultan desde Inicio o Caja y nunca requieren aprobación.</p>
    <CashAdministrationPanel context={context} discountsOnly />
  </main>;
}
