# E1 — Entrega parcial de construcción: T05

Fecha: 2026-09-14. No constituye aceptación de E1.

## Estado y alcance

E1-T05 queda **COMPLETADA técnicamente en PostgreSQL local aislado**. Reutiliza T03, T04 y T08 sin modificar sus migraciones. T06, T07 y T09 no se iniciaron: no hay descuentos, anulaciones ni pagos parciales/N pagos.

No se modificaron `PLAN_MVP.md`, PM-002, ambientes alojados ni código cliente. No se creó `acceptance.md`; tampoco hubo commit, push o merge. Las estimaciones siguen en 53 h de construcción / 59 h totales.

## Migración y objetos

`20260914000100_e1_t05_movimientos_cierre.sql` agrega:

- `movimiento_caja`: eventos `ENTRADA`/`SALIDA`, importe positivo, motivo, sesión/caja/local, actor, hora servidor e idempotencia; UPDATE/DELETE bloqueados.
- `resumen_cierre_sesion_caja`: snapshot inmutable por medio, propinas, entradas, salidas, esperado, contado, diferencia, actor/tipo/motivo.
- `solicitud_cierre_caja`: resultado idempotente por sesión, actor y clave.
- RPC `rpc_registrar_movimiento_caja`, `rpc_cerrar_sesion_caja`, `rpc_cerrar_sesion_caja_supervisor` y `rpc_obtener_resumen_sesion_caja`.
- Funciones internas no ejecutables por cliente para agregación y cierre común.
- Eventos T05 en `auditoria_caja`: entrada, salida, cierre normal y cierre supervisor, manteniendo intacta la apertura T04.
- RLS, grants mínimos, FKs `RESTRICT`, checks, índices y triggers de inmutabilidad.

Movimiento, cierre y cobro comparten el orden `caja → sesion_caja`; el cobro continúa después con `pedido → mesa`. El cierre mantiene el lock de sesión mientras agrega pagos y movimientos, persiste snapshot, actualiza sesión y audita.

## Evidencia

Base final: `mikuyapp-e1-t05-validation-20260914/e1_t05_18307652d5864d988ae423d0cfb6400f`, contenedor sin red ni bind mounts.

- Evento `APERTURA` T04 previo: fingerprint exacto antes/después de migrar.
- T05 SQL: 15 grupos aprobados, cubriendo TP13–TP18 y TP09–TP10 aplicables.
- Fórmula observada: `100 + 50 + 5 + 20 − 5 = 170`. Pago Yape 30 y propina Yape 3 quedaron separados y no alteraron efectivo esperado.
- Cierre por Cajero B de sesión abierta por A: `abierta_por=A`, `cerrada_por=B`; un pedido `ENTREGADO` pendiente permaneció permitido e intacto.
- Diferencia −10 rechazada sin motivo y aceptada con motivo; cierre supervisor rechazado sin motivo y aceptado sólo para ADMINISTRADOR.
- Regresión directamente afectada `e1_t04_apertura_sesion.sql`: aprobada.

### Concurrencia real

Cada carrera usó dos conexiones psql. La primera mantuvo la transacción sin commit; el runner verificó que la segunda estaba bloqueada mediante `pg_blocking_pids` antes de liberar a la primera.

- Doble cierre: un snapshot/auditoría y perdedor `40001`.
- Cierre vs movimiento: cierre atómico, movimiento rechazado `40001`, cero movimiento tardío.
- Cierre vs cobro: cierre atómico, cobro rechazado `40001`, cero pagos para el pedido y pedido aún `ENTREGADO`.
- Cero conexiones de prueba residuales.

No se repitieron las 305 pruebas Node, `typecheck` ni `build`, porque T05 modifica exclusivamente SQL, fixtures SQL y documentación. Tampoco se repitieron suites no afectadas. La regresión T04 sí se ejecutó porque T05 amplía el constraint y las columnas de `auditoria_caja`.
