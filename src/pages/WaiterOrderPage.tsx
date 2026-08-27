interface WaiterOrderPageProps {
  readonly orderId: number
  readonly onBack: () => void
}

export default function WaiterOrderPage({ orderId, onBack }: WaiterOrderPageProps) {
  return (
    <main className="grid min-h-screen place-items-center overflow-x-hidden bg-stone-100 px-3 py-6 text-stone-900 sm:px-6">
      <section className="w-full min-w-0 max-w-xl rounded-3xl border border-stone-200 bg-white p-5 shadow-sm sm:p-7">
        <p className="text-sm font-semibold uppercase tracking-[0.18em] text-emerald-700">Pedido seleccionado</p>
        <h1 className="mt-3 break-words text-2xl font-bold">Pedido #{orderId}</h1>
        <p className="mt-3 text-stone-600">La mesa y su pedido vigente están listos para continuar. La carta y la revisión se incorporan en T07 y T08.</p>
        <button className="mt-6 min-h-12 w-full rounded-xl bg-emerald-800 px-4 py-3 font-semibold text-white sm:w-auto" onClick={onBack} type="button">Volver a mesas</button>
      </section>
    </main>
  )
}
