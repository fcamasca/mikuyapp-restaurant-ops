# E1 — Entrega parcial de construcción: T07

Fecha: 2026-09-14. No constituye aceptación de E1.

## Estado y alcance

E1-T07 queda **COMPLETADA técnicamente en PostgreSQL local aislado**. Reutiliza T03, T04, T08, T05 y T06 mediante una migración nueva. T09 no se inició; no se implementaron pagos parciales, reversos, devoluciones ni cancelación individual de productos.

No se modificaron `PLAN_MVP.md`, PM-002, ambientes alojados ni migraciones históricas. No se creó `acceptance.md`; tampoco hubo commit, push o merge. Las estimaciones permanecen en 53 h de construcción / 59 h totales.

## Modelo y contratos

`20260914000300_e1_t07_anulacion_administrativa.sql` crea `anulacion_pedido` como snapshot inmutable y autoritativo:

- pedido, local y mesa afectados;
- actor ADMINISTRADOR y fecha/hora servidor;
- motivo obligatorio;
- estado anterior/nuevo del pedido y de la mesa;
- una anulación por pedido e idempotencia por local/actor/clave;
- FKs `RESTRICT`, RLS local y ausencia de escritura directa para clientes.

`anular_pedido_supervisado(bigint,text,uuid)` valida ADMINISTRADOR activo del mismo local, bloquea pedido y mesa, rechaza cualquier pago confirmado y permite exclusivamente `ABIERTO`, `ENVIADO`, `RECIBIDO_COCINA`, `EN_PREPARACION`, `LISTO` y `ENTREGADO`. En una única transacción cambia el pedido a `ANULADO`, libera la mesa, conserva los detalles, registra `historial_estado`, snapshot y evento `ANULACION` en `auditoria_caja`. Un reintento con la misma clave devuelve el mismo resultado sin duplicar efectos.

`PAGADO` y `ANULADO` se rechazan. PostgreSQL no exige la futura advertencia UI para estados avanzados, conforme a la matriz aprobada.

## Evidencia

Base final: `mikuyapp-e1-t07-validation-20260914/e1_t07_4c84623bfff44190a327216ed86475d4`, contenedor sin red ni bind mounts.

- TP26–TP30: 8 grupos de comprobación aprobados.
- Los seis estados anulables se probaron individualmente; todos terminaron con pedido `ANULADO` y mesa `LIBRE`.
- `PAGADO`, `ANULADO`, pago confirmado, motivo vacío, rol distinto y otro local fueron rechazados sin residuos.
- Los detalles conservaron exactamente su fingerprint.
- Idempotencia: una fila, un historial y una auditoría.
- Regresiones aprobadas: `e1_t04_apertura_sesion`, `e1_t05_movimientos_cierre` y `e1_t06_descuento_pedido`.

### TP29 — concurrencia real

Dos conexiones psql independientes: la anulación retuvo los locks del pedido y la mesa; el cobro quedó bloqueado, comprobado mediante `pg_blocking_pids`. Tras confirmar la anulación, el cobro terminó con `40001`. Resultado final: pedido `ANULADO`, mesa `LIBRE`, cero pagos, un historial de estado, una auditoría financiera y cero conexiones residuales.

No se ejecutaron las 305 pruebas Node, `typecheck` ni `build` porque sólo cambiaron SQL, pruebas SQL y documentación. No se repitieron suites sin relación directa.
