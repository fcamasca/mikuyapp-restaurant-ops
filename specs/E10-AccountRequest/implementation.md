# E10 — Evidencia de construcción (T02–T07)

Rama `feature/E10-AccountRequest`, creada desde `9c71685` (spec aprobado, DH-01 A y DH-02 B). Esta evidencia no constituye aceptación: E10-T08 (validación humana) no se inició y no existe `acceptance.md`.

## 1. Ambiente de construcción y desviación

| Componente | Detalle |
|---|---|
| SQL | PostgreSQL **16.13** local (clúster efímero, socket `/tmp`, puerto 54329) con emulación mínima de la plataforma Supabase: `scripts/e10_local_platform.sql` (roles `anon`/`authenticated`/`service_role`, `auth.users`, `auth.uid()/role()/jwt()` con la semántica de `request.jwt.claim.*`, `extensions.pgcrypto` y los privilegios por defecto de Supabase sobre `public`). |
| Replay | `scripts/e10_local_replay.sh <db> <repo> [prefijo|all]`: plataforma + migraciones en orden + `seed.sql`. |
| Suite histórica | `scripts/e10_local_sql_suite.sh <db> supabase/tests`: misma selección, orden y carreras H4/H5 que `scripts/e7_t11_sql_campaign.sh`. |
| Frontend | Node 22.23.2 en la máquina del responsable (carpeta del repositorio, `node_modules` existente). |

**Desviación de ambiente (a validar por el responsable).** El stack Supabase local en Docker usado en E7 (PostgreSQL 17.6, PostgREST, Auth, Realtime) no está disponible en este entorno de construcción: los registros de imágenes, `npm` y `apt` están bloqueados por la política de red y la máquina Linux enlazada no tiene Docker. Consecuencias:

- Las pruebas SQL corren sobre PostgreSQL 16 con emulación de plataforma, no sobre la imagen `supabase/postgres:17.6`. El replay de las 57 migraciones existentes + seed es limpio y la suite histórica reproduce exactamente la clasificación de E7-T11 (§2.1), lo que valida la emulación para este alcance.
- No hay servidor Realtime ni PostgREST locales: la entrega Realtime extremo a extremo y la lectura embebida vía PostgREST se verifican por partes (publicación, RLS evaluada como el suscriptor, decodificación lógica de la publicación y pruebas Node del cliente). La verificación Realtime/PostgREST real queda como prerequisito de E10-T08 en DEV (§6).
- DEV (`ibfr…uinf`) **no** se modificó: en `TRANSITIONING` ese proyecto también atiende Production y esta sesión no tiene credenciales de base; aplicar la migración en DEV es decisión y acción del responsable.

## 2. Línea base (antes de E10)

Base `e10_base`: replay de las 57 migraciones vigentes (`…20260823235106` a `…20260924000800`) + seed: **OK**.

### 2.1 Suite SQL histórica sobre la línea base (sin homologar)

| Bloque | Resultado |
|---|---|
| Independientes (orden alfabético) | 12 FAIL: `dbstd_t03_function_metadata`, `dbstd_t04_catalog_comments`, `domain_object_names`, `e1_delta_t09_cobro_atomico`, `e1_t09_pagos_multiples`, `h3_t04_open_order_detail_mutations`, `h4_t03_kitchen_detail_state_transition`, `h5_t02_reopen_delivered_order`, `h5_t02_safe_order_delivery`, `h5_t04_transactional_payment`, `order_audit_trail`, `tp09_tp11_schema`; el resto PASS |
| E1 con fixtures (12 pasos) | 6 fixtures PASS / 6 pruebas FAIL (`e1_t03`–`e1_t08`) |
| Carreras H4/H5 | H4-T03, H5-T02 ×2 correctas; H5-T04 falla (ambas `PT409`); cleanup H4-T03 falla |

Coincide uno a uno con la clasificación de `specs/E7-OrderOperationalImprovements/implementation-t11.md` §5 (fallos preexistentes o superados por E1-T18/E7). Esta lista es la referencia para detectar regresiones de E10.

## 3. E10-T02 — Base de datos

**Commit:** ver `git log` (`feat(e10): T02 …`).

**Archivos:**

- `supabase/migrations/20260930000100_e10_t02_solicitud_cuenta.sql` (nueva, aditiva): tabla `solicitud_cuenta` con `ck_solicitud_cuenta_estado_valido`, `ck_solicitud_cuenta_motivo_valido`, `ck_solicitud_cuenta_cierre_coherente`, FKs `RESTRICT`, `uq_solicitud_cuenta_pedido_pendiente` (único parcial `WHERE estado = 'PENDIENTE'`), `idx_solicitud_cuenta_pedido_solicitada_en`; RLS + `pol_solicitud_cuenta_select_local` (MOZO/CAJA del local); `GRANT SELECT` a `authenticated` y `REVOKE ALL` a `public/anon/service_role` (tabla y secuencia); `tgf_solicitud_cuenta_inmutable` + `trg_solicitud_cuenta_before_update_delete_inmutable`; `tgf_pedido_cerrar_solicitud_cuenta` + `trg_pedido_after_update_cerrar_solicitud_cuenta` (`AFTER UPDATE OF estado … WHEN old.estado = 'ENTREGADO' AND new.estado IS DISTINCT FROM old.estado`); alta idempotente en `supabase_realtime`; comentarios.
- `supabase/tests/e10_t02_modelo.sql` (nueva).
- `scripts/e10_local_platform.sql`, `scripts/e10_local_replay.sh`, `scripts/e10_local_sql_suite.sh` (herramientas de prueba local, §1).

**Pruebas focalizadas (test-plan §2, T02):**

| Verificación | Resultado |
|---|---|
| Migración sobre la baseline local: incremental sobre `e10_base` y replay completo (58 migraciones + seed) | PASS |
| TP01 — columnas, restricciones, FKs `RESTRICT`, índices, RLS, única política, privilegios (`authenticated` sólo `SELECT`; `anon`/`service_role` sin privilegios ni `TRUNCATE`; secuencia sin uso), triggers y su `WHEN`, funciones de trigger `SECURITY DEFINER`/owner `postgres`/`search_path` sin `EXECUTE` cliente, publicación = `detalle_pedido, mesa, pedido, solicitud_cuenta`, comentarios | PASS |
| Partes SQL de TP06–TP08 — `ENTREGADO → PAGADO` ⇒ `ATENDIDA` (actor CAJA, `cerrada_en ≥ solicitada_en`); `→ ABIERTO` ⇒ `SIN_EFECTO/REAPERTURA` (actor MOZO); `→ ANULADO` ⇒ `SIN_EFECTO/ANULACION` (actor ADMIN); actualización sin cambio de estado no cierra; nueva entrega no reactiva y permite una nueva solicitud; cierre sin actor autenticado admitido con `cerrada_por` nulo | PASS |
| TP09 (parte SQL) — segunda `PENDIENTE` → `23505`; `ATENDIDA` sin cierre → `23514`; `DELETE`, reapertura, segundo cierre y cambio de datos → `42501`; `INSERT/UPDATE/DELETE` directos de `authenticated` → `42501`; MOZO del local lee por RLS | PASS |

**Defectos encontrados / corregidos:** `pg_catalog.greatest(...)` no existe (`GREATEST` es una construcción SQL, no una función); se corrigió en la migración antes del commit (sin calificar). Dos ajustes de la propia prueba (patrón de `pg_get_triggerdef`, número de columna del comentario).

**Pendientes no bloqueantes:** ninguno.
