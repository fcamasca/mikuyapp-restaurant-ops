# E1 — Entrega parcial de construcción: T06

Fecha: 2026-09-14. No constituye aceptación de E1.

## Estado y alcance

E1-T06 queda **COMPLETADA técnicamente en PostgreSQL local aislado**. Reutiliza T03, T04, T05 y T08 mediante una migración nueva. T07 y T09 no se iniciaron; no se implementaron anulaciones, pagos parciales ni N pagos.

No se modificaron `PLAN_MVP.md`, PM-002, ambientes alojados ni migraciones históricas. No se creó `acceptance.md`; tampoco hubo commit, push o merge. Las estimaciones permanecen en 53 h de construcción / 59 h totales.

## Modelo y contratos

`20260914000200_e1_t06_descuento_pedido.sql` crea `descuento_pedido` como única fuente autoritativa a nivel pedido:

- un snapshot por `pedido_id`, sin columnas nuevas en `pedido`;
- tipo `IMPORTE` o `PORCENTAJE` y valor positivo;
- estados `PENDIENTE`, `AUTORIZADO` o `RECHAZADO`;
- motivo, solicitante CAJA, decisor ADMINISTRADOR y timestamps servidor;
- idempotencia independiente de solicitud y decisión;
- `subtotal_base`, `importe_aplicado` y `total_neto` sólo para autorización;
- FKs `RESTRICT`, RLS local e inmutabilidad después de la decisión.

No se creó infraestructura genérica de autorizaciones. Las RPC son específicas:

- `rpc_solicitar_descuento_pedido(bigint,numeric,numeric,text,uuid)` exige exactamente importe o porcentaje, pedido `ENTREGADO`, motivo y ausencia de pagos.
- `rpc_decidir_descuento_pedido(bigint,text,text,uuid)` permite sólo a ADMINISTRADOR autorizar/rechazar y recalcula el snapshot bajo lock del pedido.
- `fn_resolver_total_pedido(bigint)` devuelve subtotal de detalles, descuento autorizado o cero y total neto. No es ejecutable por clientes.

El pago total provisional fue reemplazado mediante `CREATE OR REPLACE` para consumir `fn_resolver_total_pedido`; mantiene cobro total y no habilita parciales.

## Evidencia

Base final: `mikuyapp-e1-t06-validation-20260914/e1_t06_44377125ba904470858589ac9bb0aab9`, contenedor sin red ni bind mounts.

- TP19–TP25: 8 grupos de comprobación aprobados.
- Importe: subtotal 100, descuento 20, neto 80.
- Porcentaje: 12.5% de 99.99, descuento redondeado 12.50, neto 87.49.
- Rechazo: no altera el total; resolver devuelve descuento cero.
- Pago previo: bloquea la solicitud.
- Idempotencia: una fila y un evento por solicitud/decisión.
- Regresiones aprobadas: `e1_t08_pago_sesion`, `e1_t05_movimientos_cierre`, `h5_t04_transactional_payment` y `h6_t02_sales_exports`.

### TP24 — concurrencia real

Dos conexiones psql independientes: ADMINISTRADOR autorizó y retuvo el lock del pedido; el cobro quedó bloqueado, confirmado mediante `pg_blocking_pids`. Tras el commit, el cobro leyó el descuento autorizado y persistió exactamente un pago de 80. Resultado final: descuento `AUTORIZADO` 100/20/80, pedido `PAGADO`, una fila de pago y cero conexiones residuales.

No se ejecutaron las 305 pruebas Node, `typecheck` ni `build` porque sólo cambiaron SQL, pruebas SQL y documentación. No se repitieron suites sin relación directa.

## Pendiente obligatorio de T09

T06 conserva deliberadamente el orden provisional `caja → sesion_caja → pedido → mesa` de la RPC T08. T09 debe adoptar el orden definitivo aprobado `sesion_caja → pedido → mesa` junto con N pagos/parciales. No se anticipó esa corrección en T06.
