# E1 — Entrega parcial de construcción: T08

Fecha: 2026-09-14. No constituye aceptación de E1.

## Estado y alcance

E1-T08 queda **COMPLETADA técnicamente en PostgreSQL local aislado**. T03 y T04 no se rehicieron. T05, T06, T07 y T09 no se iniciaron. No se implementaron descuentos, pagos parciales ni la operación de N pagos; el flujo H5 conserva temporalmente el cobro total.

No se modificaron `PLAN_MVP.md`, PM-002, migraciones históricas, ambientes alojados ni código cliente. No se creó `acceptance.md` ni se realizó commit, push o merge. Las estimaciones permanecen sin cambios.

## Implementación

La migración `20260913000300_e1_t08_pago_sesion.sql`:

- incorpora a `pago` `sesion_caja_id`, `propina` e `idempotency_key`;
- conserva pagos legacy con sesión/clave nulas y propina cero, sin fabricar sesiones;
- elimina la unicidad legacy por pedido y agrega índices para consulta por pedido/sesión e idempotencia por sesión, actor y clave;
- exige que todo pago nuevo tenga sesión y clave, y que la propina sea no negativa y tenga hasta dos decimales;
- agrega `rpc_registrar_pago_total_pedido`, con autoridad PostgreSQL, sesión ABIERTA del local, actor autenticado `CAJA`, propina separada e idempotencia;
- adapta la firma H5 `registrar_pago_pedido(bigint,text)` para resolver una única sesión abierta autorizada y mantener el cobro total actual;
- conserva el aislamiento histórico de H5: un pedido de otro local se rechaza con `42501` antes de resolver la sesión local.

RLS existente sobre `pago` permanece activa. Las RPC son `SECURITY DEFINER`, fijan `search_path=pg_catalog`, pertenecen a `postgres`, revocan ejecución a `PUBLIC`/`anon`/`service_role` y la conceden sólo a `authenticated`.

## Evidencia incremental

Base final inspeccionable: `mikuyapp-e1-t08-validation-20260913/e1_t08_29caba40110d415e97b997807718185b`, contenedor sin red ni bind mounts.

- Baseline: 30 migraciones anteriores a T08, seed y fixture T03.
- Preservación legacy: **1/1 pagos**, mismo conteo y fingerprint exacto de todos sus campos originales; sesión/clave nulas, propina cero; **0 sesiones retroactivas**.
- Prueba SQL T08: **27/27 comprobaciones** de columnas, constraints, índices, grants, seguridad, asociación a sesión, actor, propina, idempotencia, aislamiento y compatibilidad legacy.
- Pago nuevo: sesión ABIERTA explícita, actor `CAJA` del mismo local, propina separada y clave persistida. El reintento con la misma clave devolvió el mismo pago; reutilizarla con otra solicitud fue rechazado.
- Regresiones directamente afectadas: `h5_t02_reopen_delivered_order`, `h5_t04_transactional_payment` y `h6_t02_sales_exports`, todas aprobadas.
- Concurrencia real: dos conexiones psql y claves distintas sobre el mismo pedido; **1 cobro confirmado, 1 rechazo `40001`, 1 fila de pago asociada y 0 conexiones residuales**.

Las verificaciones ya aprobadas no se repitieron cuando sólo cambió un fixture. Tras ajustar el adaptador H5 se repitieron las tres regresiones que podía invalidar. No se ejecutaron las 305 pruebas Node, replay integral adicional, `typecheck` ni `build`: T08 modifica exclusivamente SQL y fixtures SQL, sin contrato TypeScript/build afectado.

## Límite y siguiente paso

La ausencia de unicidad por `pedido_id` sólo prepara el esquema. La RPC T08 mantiene terminalidad de cobro total y evita un segundo cobro. N pagos, parciales, total neto/descuentos y sus carreras siguen reservados a T09. Conforme al orden aprobado, la siguiente tarea es T05, que ya puede calcular pagos y propinas EFECTIVO por `sesion_caja_id`; no se inició en esta intervención.
