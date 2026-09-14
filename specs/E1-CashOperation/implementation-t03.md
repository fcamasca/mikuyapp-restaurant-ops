# E1 — Entrega parcial de construcción: T03

Fecha: 2026-09-13. No constituye aceptación de E1.

## Estado inicial y alcance alcanzado

Rama `feature/E1-CashOperation`, HEAD `e2c05e3`, árbol inicialmente limpio. Se inspeccionaron las fuentes obligatorias del plan/spec, el estándar de base de datos, migraciones, RPC, grants/RLS, servicios y pruebas H5/H6/PM-001. No se encontraron instrucciones `AGENTS.md` aplicables.

PM-002 continúa documentado como `TRANSITIONING` en `docs/PM002_ENVIRONMENTS.md`. Su DEV alojado aún comparte proyecto con Production. No se realizaron conexiones ni escrituras a Supabase alojado, Cloudflare ni variables remotas. Las consultas adicionales al contenedor local existente fueron sólo de catálogo de permisos; no se copiaron sus datos.

| Tarea | Estado | Evidencia / motivo |
|---|---|---|
| T03 | COMPLETADA técnicamente en local aislado | Migración aplicada desde las 28 históricas, 67 comprobaciones SQL y carrera real del índice único. |
| T04 | BLOQUEADA, sin implementar | D03 y TP03 especifican respuestas distintas ante una segunda apertura. |
| T05 | PENDIENTE, sin implementar | Se conserva el orden solicitado. |
| T06 | PENDIENTE, sin implementar | Se conserva el orden solicitado. |
| T07 | PENDIENTE, sin implementar | Se conserva el orden solicitado. |
| T08 | PENDIENTE, sin implementar | Se conserva el orden solicitado. |
| T09 | PENDIENTE, sin implementar | Se conserva el orden solicitado. |

T10–T14 no implementadas. No se modificaron decisiones, PLAN_MVP, PM-002, UI, servicios ni migraciones históricas. No se creó `acceptance.md`; tampoco commit, merge, push ni despliegue. Las estimaciones permanecen en 53 h de construcción planificada / 59 h totales; no se registran como tiempo consumido.

## Bloqueo y alternativa mínima

- `design.md`, D03, paso 3 (línea 30): si ya existe una sesión abierta, devuelve su snapshot autorizado para continuarla.
- `test-plan.md`, E1-TP03 (línea 17): el segundo intento falla e identifica la sesión vigente.
- No hay conflicto respecto de la unicidad ni de compartir sesión entre cajeros: ambas reglas están implementadas estructuralmente. El conflicto está en el resultado observable de la RPC de apertura, éxito con recuperación versus fallo.
- No se eligió unilateralmente uno de esos contratos ni se alteró el spec para hacer pasar la prueba.
- Alternativa mínima recomendada: conservar D03 y homologar TP03 para que una nueva solicitud sobre caja ya abierta devuelva la sesión existente sin insertar otra. La misma clave de idempotencia seguirá identificando la apertura original. Requiere confirmar la homologación antes de implementar T04.

## Migración y objetos nuevos

`supabase/migrations/20260913000100_e1_t03_caja_sesion.sql`:

- `caja`: caja física, código/nombre por local, UUID, estado activo, fecha servidor; unicidad `(local_id,codigo)` y FK restrict a local.
- Configuración inicial `CAJA-01` / `Caja principal` para cada local activo existente. No crea sesiones, no relaciona navegadores ni usuarios con la caja, ni atribuye pagos anteriores. Nuevos locales requerirán su configuración explícita, sin añadir administración multilocal a E1.
- `sesion_caja`: caja/local con FK compuesta; actor/fecha/monto de apertura, clave de solicitud, estado y campos de snapshot de cierre. Montos `numeric(14,2)`, sin NaN ni infinitos. La mayor precisión admite acumulados de sesión sin utilizar flotantes.
- Índice único parcial `uq_sesion_caja_abierta`: una sola ABIERTA por caja. Unicidad de idempotencia por caja/actor/clave, independiente de quién opere después.
- `tgf_sesion_caja_conservar_historia()` y `trg_sesion_caja_before_write_historia`: no permiten borrar sesiones, alterar identidad/apertura ni modificar sesiones cerradas. La función es invocadora, con `search_path=pg_catalog`, propietario postgres y sin EXECUTE para PUBLIC/anon/authenticated.
- Checks de cierre coherente: actores/fechas/cifras completos, diferencia igual a contado menos esperado, motivo cuando diferencia es distinta de cero. Estos checks no implementan la RPC, saldo esperado, cierre operativo ni auditoría de T05.
- RLS habilitado en ambas tablas y revocación de todos los privilegios de PUBLIC/anon/authenticated. Sin políticas permisivas, RPC ni grants cliente nuevos: corresponden a T04. Sin cambios a Realtime.
- Comentarios de catálogo para semántica de caja/sesión, actores e historia. Se adopta expresamente la nomenclatura semántica del repositorio.

## Pruebas y preservación legacy

Archivos nuevos de prueba: `supabase/tests/e1_t03_fixture.sql`, `supabase/tests/e1_t03_caja_sesion.sql` y `scripts/testE1T03.mjs`.

El runner exige contenedor de prueba con nombre acotado, imagen PostgreSQL Supabase 17, red `none`, sin bind mounts y plantilla sin tablas de aplicación. No lee `.env` ni acepta URLs remotas. Crea una base distinta por ejecución, copia sólo bootstrap de esquema y reproduce los defaults de no auto-exposición de la CLI local. Aplica 28 migraciones históricas, seed de desarrollo y fixtures sintéticos antes de aplicar T03.

La ejecución final usó PostgreSQL 17.6, Node 22.12.0 y npm 10.9.0. Base de evidencia:

`mikuyapp-e1-t03-validation-20260913/e1_t03_bb669c9b7f2c4dd3aba3c68b906ff9f7`.

Se compararon fingerprints de **todas las filas y campos de las diez tablas legacy**, antes y después de la migración y tras la regresión: 10/10 idénticos. Incluye un pago histórico con importe, medio, actor y fecha explícitos. No se fabricaron sesiones retroactivas. `uq_pago_pedido_id` y la RPC H5 siguen intactos: su evolución pertenece a T08–T09.

Las 67 comprobaciones cubren configuración, RLS/grants, FK caja/local, FK restrict, unicidad, clave de apertura persistente tras cierre, montos inválidos, inmutabilidad y estructura de cierre con actores distintos. Se ejecutaron SELECT/INSERT reales bajo `authenticated` y SELECT bajo `anon`, rechazados. Los permisos legacy, sus 27 policies, RLS y comentarios conservaron los valores esperados.

**Límite de cobertura:** TP01–TP08 sólo en sus invariantes de modelo aplicables a T03. No se declara validada apertura/recuperación por RPC, aislamiento entre perfiles mediante nuevas RPC, idempotencia con devolución de resultado, auditoría de apertura, movimientos, descuentos, anulación ni pagos E1. No se marcaron esos casos como aprobados.

### Concurrencia real

Dos procesos psql independientes intentaron insertar sesiones abiertas de la misma caja. La primera transacción mantuvo su INSERT sin confirmar; el runner comprobó `pg_blocking_pids` de la segunda antes de liberar la primera. Resultado: **1 commit, 1 rechazo SQLSTATE 23505, 1 sesión ABIERTA y 0 conexiones de prueba residuales**. No son llamadas secuenciales ni prueba de RPC inexistente.

### Regresión SQL

22 suites aprobadas, todas incluidas explícitamente en el runner:

`h3_t01_model`, `h3_t02_open_or_recover_order`, `h3_t03_add_order_detail`, `h3_t04_open_order_detail_mutations`, `h3_t05_send_order_to_kitchen`, `release_empty_order_table`, `order_audit_trail`, `h4_t01_order_detail_sent_at`, `h4_t02_kitchen_board_snapshot`, `h4_t03_kitchen_detail_state_transition`, `h4_t04_derived_order_table_state`, `h4_t05_realtime_publication_rls`, `h5_t02_safe_order_delivery`, `h5_t02_reopen_delivered_order`, `h5_t03_cashier_pending_orders_read`, `h5_t04_transactional_payment`, `h5_t06_realtime_cashier_signal`, `h6_t02_sales_exports`, `dbstd_t02_authenticated_context_hardening`, `dbstd_t03_function_metadata`, `dbstd_t04_catalog_comments`, `domain_object_names`.

Los dos tests DBSTD de metadatos/comentarios se ajustaron para aplicar sus fingerprints y conteos al conjunto original de diez tablas y funciones históricas, no a objetos aditivos de E1. **No se cambiaron hashes, cantidades ni textos esperados.** La seguridad nueva se verifica por separado.

En corridas preliminares se corrigieron problemas del harness (bootstrap con conexiones internas, propietario Supabase y cast UUID del fixture). También se detectaron los defaults de auto-exposición de la imagen distintos de la CLI y los conteos globales de DBSTD. Todo se corrigió y la corrida final completa pasó desde una base nueva. No se borraron ni reescribieron datos legacy para superar pruebas.

## Comandos y resultados finales

Desde la raíz del repositorio:

| Comando | Resultado |
|---|---|
| `node scripts/testE1T03.mjs mikuyapp-e1-t03-validation-20260913` | Exit 0: 28 migraciones baseline + T03; 67 checks SQL, 1 carrera estructural, 22 suites de regresión; 0 fallos. |
| `node --experimental-strip-types --test tests/*.test.mjs` | Exit 0: 305 aprobadas, 0 fallidas, 0 omitidas/canceladas; incluye guardias de ambiente. |
| `npm run typecheck` | Exit 0, `tsc --noEmit`. |
| `npm run build` | Exit 0; prebuild guard OK `local / TRANSITIONING / DEV`; Vite 79 módulos. Advertencia de bundle >500 kB, sin cambio de código cliente. |
| `git diff --check` | Exit 0. |

Para reproducir el contenedor de prueba sin puertos ni conexión de red:

```powershell
docker run --detach --network none --name mikuyapp-e1-t03-validation-20260913 --env POSTGRES_PASSWORD=e1-isolated-test-only --env POSTGRES_DB=postgres public.ecr.aws/supabase/postgres:17.6.1.166
node scripts/testE1T03.mjs mikuyapp-e1-t03-validation-20260913
```

La contraseña anterior es exclusivamente sintética para la base aislada. Si el contenedor ya existe y está detenido, usar `docker start mikuyapp-e1-t03-validation-20260913`, no recrearlo. Cada corrida conserva su base con nombre UUID para inspección.

Build con valores sintéticos de CI, asignados sólo al proceso PowerShell, sin modificar archivos de ambiente:

```powershell
$env:VITE_SUPABASE_URL='https://abcdefghijklmnopqrst.supabase.co'
$env:VITE_SUPABASE_PUBLISHABLE_KEY='public-ci-placeholder'
$env:MIKUY_ENVIRONMENT_STATE='TRANSITIONING'
$env:MIKUY_LOGICAL_ENVIRONMENT='DEV'
$env:MIKUY_EXPECTED_SUPABASE_PROJECT_REF='abcdefghijklmnopqrst'
$env:MIKUY_DEV_SUPABASE_PROJECT_REF='abcdefghijklmnopqrst'
npm run build
```

No sumar checks y suites como si fueran casos homogéneos: **Node 305/0; checks SQL T03 67/0; suites SQL legacy 22/0; carrera estructural 1/0**. No se afirma ejecución de TP01–TP61 completos ni de las carreras de pagos/cierre de T09.

## Archivos y estado Git de entrega

```text
 M specs/E1-CashOperation/tasks.md
 M supabase/tests/dbstd_t03_function_metadata.sql
 M supabase/tests/dbstd_t04_catalog_comments.sql
?? scripts/testE1T03.mjs
?? specs/E1-CashOperation/implementation-t03.md
?? supabase/migrations/20260913000100_e1_t03_caja_sesion.sql
?? supabase/tests/e1_t03_caja_sesion.sql
?? supabase/tests/e1_t03_fixture.sql
```

## Riesgos y siguiente paso

T03 sólo está aplicada y validada en la base local aislada; no está desplegada en DEV alojado/Preview/PROD. Las nuevas tablas permanecen sin acceso cliente. Los snapshots de cierre son estructura, no lógica operativa. T04–T09 y sus verificaciones permanecen pendientes; ningún flujo nuevo se presenta como utilizable. La primera acción para continuar es homologar la respuesta D03/TP03, sin cambiar unicidad ni operación compartida. La aceptación y pruebas humanas quedan para su etapa posterior.
