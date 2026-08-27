# H4-T09 — Evidencia de validación automatizada y técnica

**Fecha:** 2026-08-27  
**Estado:** COMPLETADA.

Este documento consolida exclusivamente la ejecución técnica de H4-T09. No incluye validación humana H4-TH, no inicia H4-T10 y no constituye aceptación de H4.

## Pruebas automatizadas

### Ejecuciones aprobadas

| Comando | Resultado |
|---|---|
| `node --experimental-strip-types --test tests/*.test.mjs` | **261/261 aprobadas** |
| Suite focalizada de rutas, catálogo, contexto, mozo, cocina y Realtime | **111/111 aprobadas** |
| `node --test tests/responsiveInterface.test.mjs` | Aprobada dentro de las ejecuciones realizadas |
| `npm run typecheck` | Aprobado |
| `npm run build` | Aprobado; 75 módulos transformados |
| `git diff --check` | Aprobado |

### Cobertura H4-TA

| IDs | Estado | Evidencia |
|---|---|---|
| H4-TA01, H4-TA03, H4-TA04, H4-TA06, H4-TA10, H4-TA18–H4-TA23 | Aprobados | `appRoutes`, `kitchenBoard`, `kitchenRealtimeService`, `waiterRealtime` y responsive. |
| H4-TA02, H4-TA05, H4-TA07–H4-TA17 | Aprobados | SQL H4 T01–T04 ejecutados contra Supabase remoto; concurrencia T03 demostrada en dos sesiones. |

Los eventos Realtime se usan únicamente como señales. Las pruebas verificaron reemplazo por snapshot, debounce de eventos repetidos/fuera de orden, segunda carga al quedar `SUBSCRIBED`, resincro tras error/reconexión, cleanup y ausencia de polling o append directo de payloads.

## Validaciones técnicas aprobadas

| Verificación | Resultado |
|---|---|
| `supabase db lint --linked --level error` | **No schema errors found** |
| `supabase migration list --linked` | Local y remoto coinciden desde `20260823235106` hasta `20260827000900` |
| Inspección estática de migraciones H4 | `SECURITY DEFINER`, `search_path`, `auth.uid()`, contexto autenticado, locks, revocaciones y grants presentes |
| Scripts transaccionales | T01, T02, T03 funcional, T04 y T05 finalizan con `ROLLBACK` |
| Concurrencia T03 | Existen setup, llamada concurrente y cleanup explícito verificable |
| Auditoría de nombres | Los objetos H4 nuevos usan nombres funcionales; referencias H2/H3 halladas pertenecen a migraciones históricas posteriormente renombradas |
| Regresión H1–H3 | Incluida en la suite completa, sin fallos |

### SQL remoto y concurrencia

| Ejecución | Resultado |
|---|---|
| `h4_t01_order_detail_sent_at.sql` | `Success. No rows returned` |
| `h4_t02_kitchen_board_snapshot.sql` | `Success. No rows returned` |
| `h4_t03_kitchen_detail_state_transition.sql` | `Success. No rows returned` |
| `h4_t04_derived_order_table_state.sql` | `Success. No rows returned` |
| `h4_t05_realtime_publication_rls.sql` | `Success. No rows returned` |
| Concurrencia T03, sesión ganadora | Detalle `-40391` confirmado en `RECIBIDO_COCINA` |
| Concurrencia T03, sesión perdedora | SQLSTATE `40001`: `El detalle fue actualizado por otra sesión` |
| Cleanup T03 corregido | `Success. No rows returned` |
| Conteo final de fixtures | `0` en `auth.users`, `local`, `perfil_usuario`, `mesa`, `categoria`, `producto`, `pedido`, `detalle_pedido` e `historial_estado` |

Con estos resultados quedan aprobadas H4-TM01–H4-TM09. La publicación Realtime contiene exclusivamente `detalle_pedido`, `pedido` y `mesa`; los SQL comprobaron RLS/grants, aislamiento por rol/local, timestamps, inmutabilidad, transiciones, rollback, derivación, auditoría y publicación.

## Validaciones técnicas pendientes

Ninguna. Las pruebas humanas H4-TH corresponden exclusivamente a H4-T10 y no se iniciaron durante esta tarea.

## Defectos encontrados

No se detectaron defectos funcionales de H4. Se corrigió un defecto exclusivo del script `h4_t03_concurrency_cleanup.sql`: la limpieza intentaba eliminar `pedido` antes de `historial_estado`, lo que era rechazado correctamente por la FK `RESTRICT`. Se agregó la eliminación y verificación del historial antes del pedido, se reejecutó el cleanup y se confirmó residuos `0`. No se modificó código funcional ni esquema.

## Conclusión

**H4-T09 completada.** Todas las pruebas H4-TA y H4-TM aplicables hasta T09 quedaron aprobadas, las migraciones están sincronizadas y los fixtures residuales son `0`. H4-T10 no fue iniciada.
