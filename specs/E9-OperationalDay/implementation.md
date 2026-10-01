# MikuyApp — Evolución 9 — Jornada operativa del local: implementación y evidencia

**Estado: construcción en curso (E9-T02–E9-T07).** E9-T08 (validación humana con dispositivos reales) no se ejecuta en esta fase. E9 no está cerrada ni aceptada; no existe `acceptance.md`.

## 1. Baseline, rama y ambiente

| Elemento | Valor |
|---|---|
| Rama de construcción | `feature/E9-OperationalDay` (convención `feature/<evolución>`), creada desde `main` `5e3b40b` |
| Commit del spec aprobado | `313794a` (“docs: spec aprobado”) |
| Árbol al iniciar | limpio |
| Última migración previa | `20260930000200_e10_t03_solicitar_cuenta_lectura_caja.sql` (59 migraciones) |
| Base de datos | PostgreSQL 16 local y efímero, con la emulación de plataforma Supabase de E10 (`scripts/e10_local_platform.sql`, `scripts/e10_local_replay.sh`). Nunca DEV, el proyecto compartido ni `mikuyapp-prod` (DC-12). |
| Node / TypeScript | Node 22 (`node --experimental-strip-types --test`), `tsc --noEmit` con `typescript` 7.0.2 (binario `linux-x64` presente en `node_modules`). |
| `vite build` | Requiere los binarios nativos `win32` de rolldown/lightningcss instalados en el equipo Windows del responsable; se ejecuta en Windows, como en E10 (`implementation.md` de E10). |

## 2. Línea base anterior a E9 (para demostrar procedencia de fallos)

Replay limpio de las 59 migraciones + seed: **OK**. Ejecución del runner vigente `scripts/e10_local_sql_suite.sh` sobre esa base (sin E9):

| Suite | Resultado en la baseline |
|---|---|
| SQL independientes | 46 PASS / 23 FAIL |
| Fallos | `dbstd_t03_function_metadata`, `dbstd_t04_catalog_comments`, `domain_object_names`, `e1_delta_t09_cobro_atomico`, `e1_t09_pagos_multiples`, `h3_t04_open_order_detail_mutations`, `h4_t03_kitchen_detail_state_transition`, `h4_t05_realtime_publication_rls`, `h5_t02_reopen_delivered_order`, `h5_t02_safe_order_delivery`, `h5_t04_transactional_payment`, `h5_t06_realtime_cashier_signal`, `order_audit_trail`, `tp09_tp11_schema`, `e1_t03_caja_sesion`–`e1_t08_pago_sesion` (6), cleanup de la carrera H4-T03, carrera H5-T04 (ejecución y verificación) |
| Node | 409/409 PASS |
| `tsc --noEmit` | OK |

Coincide con lo registrado por E10 (`specs/E10-AccountRequest/implementation.md` §8, “sin homologar”: 23 fallos). Esta línea base **no** es criterio de éxito de E9 (`design.md` E9-D16): sirve sólo para demostrar, fallo por fallo, si algo que siga fallando tras E9 es ajeno a E9 (§T07).

## 3. Preparación documental

- `docs/PLAN_MVP.md` §15 Evolución 9: estado “SPEC APROBADO — CONSTRUCCIÓN EN CURSO”, estimación 22 h, T08 pendiente.
- `specs/README.md`: entrada E9.
- Cabeceras de estado de los cuatro documentos del spec y E9-T01 completada en `tasks.md`. El contenido aprobado no cambia.

## 4. E9-T02 — Base de datos

**Migración:** `supabase/migrations/20261001000100_e9_t02_jornada_operativa.sql` (nueva, aditiva).

- Precondición DC-12: cuenta filas de `pedido` y `sesion_caja`; si hay, aborta (`P0001`) con mensaje explícito y `HINT` hacia la acción separada y autorizada. Sin backfill.
- `jornada_operativa` (E9-D03) con `pk_`, `uq_jornada_operativa_id_local_id`, `uq_jornada_operativa_local_fecha_numero`, `uq_jornada_operativa_idempotencia`, FKs `RESTRICT`, `ck_jornada_operativa_estado_valido`, `ck_jornada_operativa_numero_positivo`, `ck_jornada_operativa_cierre_coherente`, `ck_jornada_operativa_fecha_operativa` (`timezone(text,timestamptz)` es `IMMUTABLE`), `uq_jornada_operativa_local_abierta` (único parcial, I-1), `idx_jornada_operativa_local_abierta_en`; comentarios.
- RLS + `pol_jornada_operativa_select_local` (cuatro roles del local); `GRANT SELECT` a `authenticated`; `REVOKE ALL` a `public/anon/service_role` en tabla y secuencia.
- `tgf_jornada_operativa_inmutable` + `trg_jornada_operativa_before_update_delete_inmutable` (sólo `ABIERTA → CERRADA`; `23514`).
- `fn_obtener_jornada_operativa_abierta(uuid)` (interna, `FOR SHARE`, `PT409` “Local cerrado — el sistema no se encuentra aperturado”).
- `pedido.jornada_operativa_id` y `sesion_caja.jornada_operativa_id` `NOT NULL` con FK compuesta `(jornada_operativa_id, local_id)` e índices `(jornada_operativa_id, estado)`.
- `tgf_pedido_asignar_jornada_operativa` / `tgf_sesion_caja_asignar_jornada_operativa` con triggers `BEFORE INSERT OR UPDATE OF jornada_operativa_id`: asignan la jornada abierta, rechazan un valor distinto (`42501`) y cualquier cambio (`23514`).
- `tgf_pago_validar_jornada_operativa` + `trg_pago_before_insert_validar_jornada_operativa`: `PT409` si pedido y sesión pertenecen a jornadas distintas (ver DV-01).
- Funciones `SECURITY DEFINER`, owner `postgres`, `search_path = pg_catalog`, sin `EXECUTE` cliente; publicación `supabase_realtime` + `jornada_operativa` (idempotente).
- Ninguna RPC operativa existente fue modificada (DC-10); verificado en TP01.

**Pruebas focalizadas ejecutadas** (base local efímera):

| Prueba | Archivo | Resultado |
|---|---|---|
| Aplicación sobre la baseline local (incremental y en replay completo de 60 migraciones + seed) | — | PASS |
| TP02 — aborta con pedido existente, aborta con sesión existente (mensaje exacto, sin tabla ni columnas parciales, filas intactas); aplica sobre la baseline vacía sin crear jornadas | `scripts/e9_t02_precondicion.sh` | PASS 4/4 |
| TP01 (parte T02) — columnas, 11 restricciones, FKs `RESTRICT`, índices, `jornada_operativa_id` sólo en `pedido`/`sesion_caja` (R19), FK compuestas, RLS y única política, privilegios de tabla y secuencia, seguridad y comentarios de las 5 funciones, 4 triggers, publicación = 5 tablas, comentarios; ninguna RPC operativa referencia la jornada (DC-10) | `supabase/tests/e9_t02_modelo.sql` | PASS |
| TP06 — sin jornada: `crear_o_recuperar_pedido_mesa` y `rpc_abrir_sesion_caja` → `PT409`, inserción directa como owner → `PT409`, mensaje exacto, sin residuos en pedido/historial/mesa/sesión/solicitud de apertura/auditoría/notificaciones; con jornada: asignación de la jornada del local (incluido el `to_jsonb` de la sesión) y recuperación idempotente E1-R02 intacta | idem | PASS |
| TP07 — valor distinto suministrado → `42501`; mismo valor admitido; `UPDATE` de la jornada en pedido/sesión → `23514` incluso como owner; transiciones de estado no cambian la jornada | idem | PASS |
| TP09 — pedido de J1 y sesión de J2: `rpc_registrar_cobro_pedido`, `registrar_pago_pedido`, `rpc_registrar_pago_total_pedido`, `rpc_registrar_pago_pedido_v2` → `PT409` con mensaje exacto, sin `cobro`, `pago`, auditoría ni cambio de estado; misma jornada → cobro normal a `PAGADO` | idem | PASS |
| TP13 (modelo) — `DELETE`, reapertura, cambios de cierre, número, local, apertura y clave → `23514`; segunda abierta → `23505`; fecha y cierre incoherentes → `23514`; escritura directa de `authenticated` → `42501`; RLS limitada al local | idem | PASS |

**Fixture de TP09 (instrucción §8 de la construcción).** El estado “pedido vigente de una jornada + sesión de otra” se fabrica **sin desactivar ninguna defensa**: dentro de la transacción de prueba (`ROLLBACK`), el owner cierra la jornada J1 con un `UPDATE` directo (transición `ABIERTA → CERRADA` que el trigger de inmutabilidad admite) mientras J1 aún tiene un pedido `ENTREGADO`, y abre J2. Las condiciones de cierre las impone `rpc_cerrar_jornada_operativa`, que es la única vía disponible para clientes (`authenticated` no tiene `UPDATE` sobre la tabla, verificado en TP13); que esa inconsistencia no puede generarse fuera del fixture se prueba en T03 (TP10: cierre rechazado con pendientes) y TP17 (carreras de cierre).

**Hallazgos de T02:**

| ID | Hallazgo | Tratamiento |
|---|---|---|
| HZ-E9-01 | `h3_abrir_o_recuperar_pedido(uuid)` (vía heredada) invoca `public.h2_auth_context()`, renombrada a `obtener_contexto_autenticado` en `20260826000300`; falla con `42883` para todo usuario autenticado ya en la baseline. No puede crear pedidos con o sin E9. | Preexistente y ajeno a E9; no se corrige (fuera de alcance). El trigger de E9 la cubre igualmente. Informado al responsable. |
| DV-01 | E9-D06 prevé que `tgf_pago_validar_jornada_operativa` rechace también los pagos sin `sesion_caja_id`. Cuatro tests vigentes insertan pagos legacy sin sesión como dato de su escenario (`e1_t03_fixture.sql`, `e7_t05_cancelacion.sql`, `h6_t02_sales_exports.sql`, `tp10_constraints.sql`; este último espera la violación del `CHECK` de medio, que el trigger anticiparía). Ningún requisito lo exige (R18 e I-4 se refieren a pagos con sesión) y ningún cliente puede insertar en `pago`. | **Sub-punto detenido** conforme a la instrucción de construcción: se implementa la coherencia pedido/sesión y los pagos sin sesión siguen gobernados por `ck_pago_asociacion_e1` como hoy. Ajuste mínimo propuesto: retirar ese rechazo de E9-D06. Pendiente de decisión del responsable. |

**Defectos:** ninguno abierto.
