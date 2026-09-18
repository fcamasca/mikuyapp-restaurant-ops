# E1 — Entrega parcial de construcción: T10

Fecha: 2026-09-14. No constituye aceptación de E1.

E1-T10 queda **COMPLETADA técnicamente en frontend**. `/caja` conserva acceso exclusivo de CAJA y consume las lecturas/RPC autoritativas para caja física, sesión, movimientos, cierre, descuentos, pagos múltiples, propinas e historial. El shell de ADMINISTRADOR incorpora la lectura operacional, decisión de descuentos y anulación directa; no recibe capacidad de cobro.

La vista de Caja prioriza sesión → pedidos pendientes → cobro rápido. Muestra subtotal, descuento, total neto, pagado y saldo resueltos por PostgreSQL; la selección de productos sólo calcula un importe sugerido local y no persiste asignaciones. Cada pago puede emitir un recibo interno parcial y el pago final un ticket consolidado interno, ambos identificados como no fiscales.

Validación técnica:

- TP35: selección de líneas usada únicamente como calculadora de importe sugerido.
- TP45–TP47: captura y visualización separada de propina, preservando medio y saldo autoritativo.
- TP48: recibo parcial y ticket consolidado diferenciados, con historial de pagos y sin `pago_detalle`.
- TP59–TP60: estados sin caja/vacío/loading/error/reintento, exclusión de doble envío, `busy` y resincronización tras cada comando.
- 35/35 pruebas Node/React afectadas aprobadas.
- `npm run typecheck` aprobado.
- `npm run build` aprobado; sólo se emitió la advertencia no bloqueante preexistente de tamaño de chunk.

TP62–TP64 no fueron ejecutadas ni marcadas aprobadas: continúan como pruebas humanas posteriores. No se repitieron el replay ni la regresión SQL T03–T09 porque no cambiaron contratos PostgreSQL en esta intervención frontend. Tampoco se ejecutó la suite Node integral ni la regresión H1–H6/PM-001, reservadas para T13.

No se iniciaron T11–T14, no se modificaron migraciones financieras ni reglas T03–T09, y no se tocaron ambientes alojados, PM-002 ni `PLAN_MVP.md`.
# Delta homologado de interfaz multi-medio — 2026-09-18

Caja compone N medios dentro de un único acto TOTAL o PARCIAL, muestra objetivo, total preparado, faltante/exceso y propina por medio, y confirma una sola vez el cobro agrupado. La lectura presenta cobros con sus líneas, actor y saldos autoritativos; el recibo/ticket agrupa por `cobro`, no por fila `pago`. Realtime/resync invalida confirmaciones obsoletas y se conserva la protección de doble envío.

La lectura SQL agrupada aprobó actor, orden de medios, propinas y aislamiento local/rol. Las pruebas focalizadas de Caja y documentos aprobaron y la puerta integral posterior confirmó 311/311 pruebas Node/React. TP62–TP64 no se ejecutaron ni se marcan aprobadas.
