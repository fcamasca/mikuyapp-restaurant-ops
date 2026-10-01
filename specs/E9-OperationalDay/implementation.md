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

## 5. E9-T03 — RPC y lecturas

**Migración:** `supabase/migrations/20261001000200_e9_t03_rpc_jornada_operativa.sql` (nueva, aditiva; no modifica RPC operativas existentes, DC-10).

- `fn_formatear_identificacion_jornada(date, integer)` interna `IMMUTABLE`: `Jornada YYYY-MM-DD (N)` definida en un único lugar.
- `rpc_abrir_jornada_operativa(uuid)` (E9-D07): contexto `ADMINISTRADOR` (`42501`), clave obligatoria (`22023`), `local FOR NO KEY UPDATE`, misma clave → misma jornada aunque esté cerrada, abierta existente → `ya_existia = true`, `clock_timestamp()` tras el lock, fecha operativa `America/Lima`, correlativo por local + fecha, `23505` defensivo resuelto como existente.
- `rpc_cerrar_jornada_operativa(bigint)` (E9-D08): contexto `ADMINISTRADOR`, jornada del local `FOR UPDATE` (`42501` si no existe o es de otro local), cerrada → `ya_estaba_cerrada = true` sin escribir, conteo de sesiones abiertas y pedidos no terminales en sentencias nuevas, `PT409` “No se puede cerrar la jornada: N pedidos pendientes y M sesiones de caja abiertas”, `cerrada_en = greatest(clock_timestamp(), abierta_en)`.
- `rpc_obtener_jornada_operativa_actual()` (`STABLE`, cuatro roles; cero filas = local cerrado; nombre de quien abrió y `servidor_ahora`).
- `rpc_obtener_pendientes_cierre_jornada()` (`STABLE`, ADMIN). Contrato: `tipo ∈ (PEDIDO, SESION_CAJA)`, `pedido_id`, `mesa_codigo`, `estado`, `sesion_caja_id`, `caja_codigo`, `abierta_por_nombre`, `desde` (creación del pedido o apertura de la sesión). Es la forma tabular única de los campos que enumera E9-D10 para ambos tipos; sin importes.
- `rpc_obtener_historial_jornadas_operativas(integer, integer)` (`STABLE`, ADMIN; paginación 1–200 / offset ≥ 0, si no `22023`; sin totales ni conteos).
- Todas `SECURITY DEFINER`, owner `postgres`, `search_path = pg_catalog`, `EXECUTE` sólo `authenticated`, comentarios.

**Pruebas focalizadas ejecutadas:**

| Prueba | Archivo | Resultado |
|---|---|---|
| TP03 — MOZO, COCINA, CAJA, perfil inactivo y sin sesión → `42501`; clave nula → `22023`; rechazos sin filas; apertura válida con local, actor, hora, fecha operativa, número 1, clave e identificación | `supabase/tests/e9_t03_rpc.sql` | PASS |
| TP04 — misma clave, otra clave y otro ADMIN con jornada abierta → la existente (`ya_existia`), sin filas nuevas; misma clave tras el cierre → la jornada `CERRADA`, no abre otra | idem | PASS |
| TP05 — 1, 2, 3 en la misma fecha; otro local numera aparte; jornada fixture abierta ayer 21:00: pedido y sesión de hoy se asignan a ella, identificación conserva la fecha de ayer, cierre hoy con `cerrada_en > abierta_en`, siguiente apertura numera en la fecha de hoy | idem | PASS |
| TP10 — rechazo `PT409` con conteos exactos por pedido `ABIERTO` vacío, cada estado `ENVIADO`…`ENTREGADO`, sesión abierta, `ENTREGADO` con cobro parcial + solicitud de cuenta y con descuento pendiente; resolución con liberación de mesa (H3), cobro total (E1, la solicitud E10 queda `ATENDIDA`), anulación (E1) y cierre de caja (E1); otro local / inexistente → `42501`, nulo → `22023`; cierre válido y repetición idempotente con mismo actor y hora | idem | PASS |
| TP11 — pendientes exactos (pedido con mesa/estado/desde; sesión con caja/quién/desde), vacío sin pendientes y con local cerrado | idem | PASS |
| TP12 — estado actual igual para los cuatro roles, otro local sin filas, sin contexto → `42501`; historial ordenado con nombres, paginación, sin columnas de totales, sin cruce de locales | idem | PASS |
| TP14 (SQL) — seguridad, owner, `search_path`, privilegios, volatilidad (`v`/`s`), función de identificación no expuesta; ninguna función vigente con `40001` manual; matriz de roles de pendientes, historial y cierre | idem | PASS |
| TP15 — I-2, I-3, I-4 y misma jornada local en toda la base; la jornada se deriva unívocamente de detalle, historial, solicitud de cuenta, cobro, pago, descuento, anulación, resumen de cierre y auditoría; apertura y cierre con actor y hora | idem | PASS |
| TP16 real — dos ADMIN simultáneos; doble envío con la misma clave | `scripts/e9_concurrency.sh` | PASS 2/2: una sola jornada, número 1, segundo envío `ya_existia` |
| TP17 real — cierre vs crear pedido y cierre vs abrir caja en ambos órdenes; cierre vs cierre | idem | PASS 5/5: gana la creación → cierre `PT409` con conteo; gana el cierre → creación `PT409` “Local cerrado…” sin residuos (pedido, mesa, sesión, solicitud de apertura, auditoría); segundo cierre idempotente con el actor del primero |

Las carreras usan una base efímera nueva por carrera (plantilla con E9) y la eliminan al terminar, sin limpiezas. En todas: sin `40001`, sin `40P01`, sin conexiones residuales. `e9_t02_modelo.sql` sigue en PASS con T03 aplicada.

**Defectos:** ninguno abierto.

## 6. E9-T04 — Frontend operativo

**Archivos:**

- `src/services/operationalDayService.ts` (nuevo): `LOCAL_CLOSED_MESSAGE`, `isLocalClosedError` (sólo `PT409` con el mensaje exacto de PostgreSQL), `createOperationalDayService` (`getCurrent`, `open`, `close`, `getClosingBlockers`, `getHistory`; todo por RPC, sin local, actor, fecha ni número del cliente) y `subscribeToOperationalDay`: canal propio sobre `jornada_operativa` (`INSERT`/`UPDATE`), topic único con `subscriptionTopic` (pieza existente reutilizada; `operationsRealtimeService` no se modifica), debounce/coalescencia, relectura en `SUBSCRIBED` y ante `CHANNEL_ERROR`/`TIMED_OUT`/`CLOSED`; sin polling.
- `src/components/OperationalDayGate.tsx` (nuevo): `OperationalDayGate`, `useOperationalDay` (`{ jornada, resync }`), `LocalClosedScreen`. Estados `loading` / `open` / `closed` / `error`; sólo `open` renderiza la pantalla solicitada (fail-closed, E9-R12). Local cerrado: texto exacto “Local cerrado — el sistema no se encuentra aperturado”, local, menú de usuario, **Actualizar** y **Cerrar sesión**. Error: **Reintentar** y **Cerrar sesión**.
- `src/App.tsx`: función `gated` que envuelve todas las pantallas de MOZO, COCINA y CAJA —`/mozo/mesas`, `/mozo/pedidos/:id`, `/cocina`, `/caja`, `/ventas` y `/tecnica` (DC-11)—; ADMIN, `/login` y `/403` no pasan por el gate.
- `src/services/waiterOrderService.ts` (`createOrRecoverOrder`) y `src/pages/WaiterTablesPage.tsx`: el `PT409` de local cerrado devuelve el mensaje del servidor y la vista llama a `resync()` (HZ-06).
- `src/services/cashierService.ts` (helper `rpc`) y `src/pages/CashierPage.tsx`: la apertura de caja rechazada por local cerrado conserva el mensaje y resincroniza el gate; Caja muestra la identificación de la jornada sobre el estado de caja (E9-R31).
- Mozo y cocina no cambian con el local abierto; `KitchenBoardPage` y `kitchenRealtimeService` no se tocan.

**Pruebas focalizadas** (`node --experimental-strip-types --test`):

| Prueba | Resultado |
|---|---|
| `tests/e9OperationalDay.test.mjs` (nuevo, 12 pruebas): lectura del estado por RPC sin datos del cliente; cero filas = cerrado; error ≠ abierto/cerrado; reconocimiento exacto del `PT409` de local cerrado; suscripción sólo a `jornada_operativa` `INSERT`/`UPDATE` con topic único; coalescencia de señales duplicadas, relectura en `SUBSCRIBED` y ante error; `operationsRealtimeService` intacto y sin polling; pantalla de local cerrado (texto, local, Cerrar sesión, Actualizar, sin acciones operativas, ≥ 44 px, sin desplazamiento horizontal); fail-closed; todas las rutas de MOZO/COCINA/CAJA con gate y ADMIN//login//403 sin gate; Caja (identificación + resync); apertura de caja y apertura de pedido con local cerrado | PASS |
| `tests/appRoutes.test.mjs`, `tests/waiterBoard.test.mjs`, `tests/cashierPage.test.mjs`, `tests/kitchenRealtimeService.test.mjs` (cocina conserva sus enlaces) | PASS |
| Total focal | 124/124 PASS |
| `tsc --noEmit` | OK |

**Defectos:** ninguno abierto.
