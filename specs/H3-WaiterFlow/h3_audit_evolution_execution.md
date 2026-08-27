# MikuyApp — Evidencia de evolución de auditoría posterior a H3

Fecha: 2026-08-27  
Alcance: H3-ER01 / H3-ED01 / H3-E01.  
Estado: **implementada y validada técnica/automáticamente**. Este documento no modifica ni reemplaza `acceptance.md`.

## Resultado

Se agregó auditoría de creación y modificación a `pedido` y `detalle_pedido`, derivada de la sesión PostgreSQL. `pedido.creado_por/creado_en` y la creación de cada detalle permanecen inmutables; las modificaciones comerciales actualizan la cabecera y los cambios de estado actualizan únicamente la auditoría individual del detalle. No se agregó responsable a `mesa`.

El tablero deriva el nombre desde `pedido.creado_por` mediante `obtener_creadores_pedidos_vigentes`, limitada a rol `MOZO`, mismo local y pedidos vigentes.

## Operaciones cubiertas

- `crear_o_recuperar_pedido_mesa`: inicializa creación y modificación con el creador original.
- `agregar_detalle_pedido`: autoría segura tanto al insertar como al consolidar.
- UPDATE directo autorizado de cantidad/observación: actualiza detalle y modificación comercial del pedido.
- DELETE autorizado de detalle abierto: actualiza la modificación comercial del pedido dentro de la misma transacción.
- `enviar_pedido_cocina`: actualiza auditoría de los detalles enviados sin sustituir `pedido.modificado_*`.
- `liberar_mesa_pedido_vacio`: no altera la autoría original del pedido.

## Migraciones

- `20260827000200_order_audit_trail.sql`: columnas, backfill, FK `RESTRICT`, triggers y función de creadores.
- `20260827000300_fix_order_creator_lookup.sql`: corrección mínima de `COALESCE` detectada por la primera ejecución técnica.

Ambas migraciones figuran aplicadas local y remotamente. No se editó una migración ya aplicada.

## Pruebas y evidencia

| Validación | Resultado |
|---|---|
| `supabase/tests/order_audit_trail.sql` remoto | Aprobado con `ROLLBACK` |
| Creación inicial de pedido | `modificado_por = creado_por`; timestamps iguales |
| Primer detalle y detalle posterior por otro mozo | Autoría individual correcta |
| Conservación de `pedido.creado_por` | Aprobada |
| Actualización de `pedido.modificado_por` | Aprobada |
| Cambio de estado de detalle | Auditoría individual actualizada; cabecera comercial intacta |
| Intento de suplantación | Rechazado por privilegios; frontend no envía UUID de auditoría |
| Nombre del creador en card | Servicio y render automatizados aprobados |
| Suite del mozo | 47/47 |
| Suite integral | 241/241 |
| Typecheck/build | Aprobados; 72 módulos transformados |
| `supabase db lint --linked --level error` | Sin errores |
| Migraciones local/remoto | Coinciden hasta `20260827000300` |
| Fixtures residuales | 0 |

## Defecto detectado y corregido

La primera ejecución remota detectó que `COALESCE` había sido calificado incorrectamente como función de `pg_catalog`. La transacción de prueba se revirtió. Se creó la migración incremental mínima `20260827000300`, se repitió la prueba completa y el resultado fue aprobado sin residuos.

## Límites conservados

No se implementó H4, historial completo de cambios, responsable en `mesa`, nuevos estados, permisos adicionales de roles ni cambios de caja, impresión o reportes. `acceptance.md` no fue modificado.
