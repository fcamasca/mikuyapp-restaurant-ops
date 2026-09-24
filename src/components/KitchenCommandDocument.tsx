import type { CommandDocument } from '../services/kitchenCommandService'

interface KitchenCommandDocumentProps {
  readonly document: CommandDocument
  readonly onClose: () => void
}

// E7-D12: documento de comanda 80 mm. Reutiliza las clases de impresión de caja (print-overlay /
// print-document); la página abre el diálogo estándar del navegador hacia la impresora del sistema operativo.
// Sólo se abre tras registrar la solicitud; para otra copia se usa Reimprimir (queda registrada).
export default function KitchenCommandDocument({ document, onClose }: KitchenCommandDocumentProps) {
  return (
    <div className="print-overlay fixed inset-0 z-50 flex items-center justify-center bg-black/50 p-4">
      <article aria-labelledby="kitchen-command-title" className="print-document ticket-document flex max-h-[calc(100vh-2rem)] w-full max-w-md flex-col overflow-hidden rounded-2xl bg-white shadow-2xl" role="dialog" aria-modal="true">
        <div className="ticket-scroll overflow-y-auto p-6">
          <header className="text-center">
            <h2 className="ticket-brand tracking-wide" id="kitchen-command-title">{document.title}</h2>
            {document.copyLabel && <p className="ticket-type mt-1 font-bold tracking-widest">{document.copyLabel}</p>}
            <p className="ticket-disclaimer mt-1 text-stone-600">Apoyo al flujo digital · la tablet es la referencia</p>
          </header>
          <div className="ticket-rule my-4 border-t border-dashed border-stone-400" />
          <div className="flex justify-between gap-4 font-medium">
            <span>Mesa {document.mesa}</span>
            <span>Pedido #{document.pedidoId}</span>
          </div>
          <p className="mt-1 text-stone-600">Enviado {new Date(document.enviadoEn).toLocaleString('es-PE', { timeZone: 'America/Lima' })} · {document.mozo}</p>
          <div className="ticket-rule my-4 border-t border-dashed border-stone-400" />
          <ul className="consumption-list divide-y divide-stone-200">
            {document.lines.map((line) => (
              <li className="consumption-item py-2" key={line.detalle_id}>
                <p className={`product-name text-base font-bold ${line.cancelado ? 'line-through' : ''}`}>{line.cantidad} × {line.producto_nombre}</p>
                {line.observacion && <p className="mt-1">Obs.: {line.observacion}</p>}
                {line.cancelado && <p className="mt-1 font-bold">CANCELADO</p>}
              </li>
            ))}
          </ul>
        </div>
        <div className="ticket-actions no-print flex shrink-0 gap-3 border-t border-stone-200 bg-white p-4">
          <p className="flex-1 self-center text-xs text-stone-600">Si la impresora no respondió, cierra y usa Reimprimir.</p>
          <button className="min-h-11 rounded-xl bg-stone-900 px-5 font-semibold text-white" onClick={onClose} type="button">Cerrar</button>
        </div>
      </article>
    </div>
  )
}
