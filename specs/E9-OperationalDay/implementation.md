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

## 7. E9-T05 — Frontend ADMIN

**Archivos:**

- `src/components/OperationalDayAdminPanel.tsx` (nuevo): bloque “Jornada operativa”, primero en Inicio. Local cerrado → **Abrir jornada** con confirmación en línea; abierto → `Jornada YYYY-MM-DD (N) · abierta por X a las hh:mm` (y “desde el dd/mm” si cruzó la medianoche, comparando con `servidor_ahora`) y **Cerrar jornada** con confirmación. Guard `useRef` + botones deshabilitados durante la operación; clave de apertura conservada entre reintentos hasta el éxito; `ya_existia` / `ya_estaba_cerrada` informados como aviso, no como error. Ante `PT409` del cierre muestra el mensaje con conteos del servidor, carga `rpc_obtener_pendientes_cierre_jornada` y lista pedidos (mesa, pedido, estado) y cajas (caja, quién, desde) con enlaces **Ver pedidos** / **Ver caja** y la secuencia sugerida. Se actualiza con la misma señal Realtime (aperturas/cierres de otro administrador). Sin métricas ni totales.
- `src/pages/AdminOperationalDaysPage.tsx` (nuevo): historial en tabla responsive (identificación, estado, apertura, cierre), páginas de 20 con **Cargar más**; sin totales.
- `src/services/appRoutes.ts`: `/admin/jornadas` (sólo ADMIN por la regla vigente de `/admin/*`).
- `src/components/AdminShell.tsx`: `OPERACIÓN → Jornadas`.
- `src/App.tsx`: ruta `/admin/jornadas`; `AdminHomePage` recibe `onOrders`.
- `src/pages/AdminHomePage.tsx`: inserta el bloque antes de los bloques existentes, que no cambian ni de contenido ni de orden.

**Pruebas focalizadas:**

| Prueba | Resultado |
|---|---|
| `tests/e9AdminOperationalDay.test.mjs` (nuevo, 9 pruebas): abrir envía sólo la clave y `ya_existia` no es error; cerrar envía sólo la jornada, `ya_estaba_cerrada` no es error y el `PT409` conserva los conteos; pendientes e historial sin importes; MOZO/COCINA/CAJA no llaman a las RPC ADMIN; `/admin/jornadas` sólo ADMIN y en `OPERACIÓN`; bloque primero en Inicio sin alterar el orden E1; confirmaciones, guard, clave idempotente, avisos y señal; pendientes con enlaces y secuencia; sin métricas ni totales; paginación; objetivos de 44 px y filas sin desplazamiento horizontal | PASS |
| `tests/adminHome.test.mjs`, `tests/appRoutes.test.mjs` | PASS |
| Total focal | 28/28 PASS |
| `tsc --noEmit` | OK |

**Defectos:** ninguno abierto.

## 8. E9-T06 — Integración técnica

Sin dispositivos físicos. Ambiente: PostgreSQL 16 local efímero con `wal_level=logical`.

**Archivos:** `supabase/tests/e9_t06_integracion.sql` (recorrido TP23), `scripts/e9_t06_integracion.sh` (migraciones incrementales, recorrido, señal local), `scripts/e9_realtime_verificacion.mjs` (TP22 con clientes Realtime reales, para el ambiente preparado de DC-12).

| Verificación | Resultado |
|---|---|
| Migraciones E9 incrementales (`20261001000100`, `20261001000200`) sobre la línea base de 59 migraciones + seed | PASS 2/2 |
| Replay completo (61 migraciones + seed) | OK |
| TP23 recorrido integrado con las RPC reales de cada rol: local cerrado (crear pedido y abrir caja → `PT409` “Local cerrado…”, estado actual vacío) → apertura → caja → pedido con producto de cocina y sin cocina → recepción completa y preparación en cocina → entrega → solicitud de cuenta → cobro parcial → cierre de caja con el pedido pendiente (E1 DF-01) → cierre de jornada rechazado (“1 pedidos pendientes y 0 sesiones de caja abiertas”) → nueva sesión de otro cajero en la **misma** jornada → cobro total (pedido `PAGADO`, mesa `LIBRE`, solicitud `ATENDIDA`) → cierre de caja → cierre de jornada → operación rechazada → segunda jornada de la misma fecha `(2)` → jornada con cruce de medianoche (fixture ayer 21:00): pedido de hoy en ella, identificación con la fecha de ayer, cierre posterior. Pedido, sesiones, cobros, solicitud e historial derivan de la jornada correcta | PASS |
| TP22 (local) — publicación = `detalle_pedido, jornada_operativa, mesa, pedido, solicitud_cuenta` | PASS |
| TP22 (local) — cambios decodificados del WAL (`test_decoding`) de `jornada_operativa`: 2 `INSERT` (aperturas) y 1 `UPDATE` (cierre); apertura idempotente, cierre rechazado y cierre repetido no emiten; 0 `DELETE` | PASS |
| TP22 (local) — autorización de `postgres_changes` (RLS de `SELECT` sobre la versión nueva de la fila): ADMIN, MOZO, COCINA y CAJA del local ven la fila `ABIERTA` y la `CERRADA` (reciben apertura y cierre); ADMIN de otro local no ve ninguna; `anon` sin privilegio | PASS |
| Reacción del cliente a la señal (relectura autoritativa, coalescencia, `SUBSCRIBED`, error, topic único) | Cubierta en T04 (`tests/e9OperationalDay.test.mjs`) con canal simulado |
| Residuos | 0 slots, 0 bases efímeras |
| **TP22 con clientes Realtime programáticos contra un servidor Supabase real** | **PENDIENTE de ejecución en Windows.** El entorno de construcción no puede levantar un servidor Realtime (la política de red bloquea el registro npm y Docker Hub). Conforme a DC-12 se usa el stack Supabase **local** del repositorio (Docker + `supabase start`, patrón aprobado en E7-T10), nunca DEV, el proyecto compartido ni PROD: `scripts/e9_t06_local.ps1` levanta los servicios mínimos, ejecuta `db reset --local` (61 migraciones + seed), corre las pruebas SQL de E9 sobre la imagen PostgreSQL de Supabase y lanza `scripts/e9_realtime_verificacion.mjs` (guarda de loopback; local de prueba propio sin jornadas; cinco clientes con un segundo ADMIN; apertura, idempotencia, remontaje con topic único, ausencia de polling, reconexión y cierre). Resultado a registrar en §9.7. |

**Estado de T06:** recorrido técnico y señal local completos; **no se marca completada** mientras falte la ejecución real de TP22 descrita arriba.

**Defectos:** ninguno abierto.

## 9. E9-T07 — Homologación y pruebas finales

Ambiente: PostgreSQL 16 local efímero con `wal_level=logical` (mismas plataforma y scripts de E10: `scripts/e10_local_platform.sql`, `e10_local_replay.sh`, `e10_local_sql_suite.sh`). Ejecución única con `scripts/e9_t07_campaign.sh c83c8fd` (en el repositorio del responsable la misma línea base es `313794a`). Registro completo: salida de la campaña (`== fallos: 0`).

### 9.1 Homologación mínima de tests vigentes (E9-D16)

Realizada directamente en el repositorio, sin copias temporales. Cada línea añadida lleva el marcador `E9 (homologación mínima)` o `Contrato actualizado`. No se alteró ninguna aserción, dato relevante ni objetivo de prueba; 66 archivos, +648/−57 líneas.

| Motivo | Cambio | Archivos |
|---|---|---|
| Precondición global de E9: crear `pedido`/`sesion_caja` exige jornada `ABIERTA` (R11, D05) | Tras el alta de perfiles del fixture se inserta una jornada `ABIERTA` válida (fecha operativa de Lima, correlativo siguiente, abierta por un perfil del local) para los locales del fixture que no la tengan. `tp10_constraints.sql` (manual) la crea para `demo_local_id` | 60: `e1_*` (21, incluidos fixtures y setups de carreras), `e7_*` (11, incluido `e7_concurrency_setup`), `e10_*` (5, incluido `e10_concurrency_setup`), `h3_t01`–`h3_t05` (6), `h4_t01`–`h4_t05` (6), `h5_t02`–`h5_t06` (7), `h6_t02_sales_exports`, `order_audit_trail`, `release_empty_order_table`, `tp10_constraints` |
| Jornada inmutable (D03): las limpiezas de setups de carreras borraban el local y el perfil, ahora referenciados por la jornada | La limpieza cierra la jornada con la transición permitida `ABIERTA → CERRADA`; los `DELETE` de perfil, `auth.users` y local omiten lo referenciado por una jornada; las altas de esos tres usan `on conflict (id) do nothing`; las verificaciones de limpieza ignoran lo conservado | `h3_t05_concurrency_setup`, `h4_t03_concurrency_setup`, `h5_t02_concurrency_setup`, `h5_t02_reopen_vs_payment_setup`, `h5_t04_concurrency_setup`, `e7_concurrency_setup` |
| Contrato cambiado deliberadamente por E9 (D12): publicación Realtime | Lista esperada = `detalle_pedido, jornada_operativa, mesa, pedido, solicitud_cuenta`. En `h4_t05`/`h5_t06` se incorpora además `solicitud_cuenta` (E10-D07): esos dos contratos ya fallaban en la baseline porque E10 sólo los homologó en copias | `h4_t05_realtime_publication_rls`, `h5_t06_realtime_cashier_signal`, `e10_t02_modelo` |
| Claves de `to_jsonb(sesion_caja)` | Revisadas: ningún test vigente compara el conjunto exacto de claves, no fue necesario cambio | — |

Nuevo: `supabase/tests/e9_t07_matriz_local_cerrado.sql` (TP08).

### 9.2 Resultados

| Bloque | Resultado |
|---|---|
| TP25 replay limpio total (61 migraciones + seed) | OK |
| TP02 precondición de la migración (aborta con `pedido`, aborta con `sesion_caja`, aplica sobre baseline vacía, no crea jornadas) | PASS 4/4 |
| DC-10: definiciones (`md5(pg_get_functiondef)`) de funciones y políticas previas a E9, baseline vs E9 | 100 previas; **0 modificadas, 0 eliminadas**; nuevas: 11 funciones + `pol_jornada_operativa_select_local` |
| Pruebas SQL de E9: `e9_t02_modelo` (TP01, TP06, TP07, TP09, TP13), `e9_t03_rpc` (TP03–TP05, TP10–TP12, TP14, TP15), `e9_t06_integracion` (TP23), `e9_t07_matriz_local_cerrado` (TP08) | PASS 4/4 |
| TP08 matriz con local cerrado: 25 operaciones operativas de MOZO, COCINA, CAJA y ADMIN rechazadas sin efectos (conteos y estados iguales antes/después; RPC → `PT409` “Local cerrado…”; escrituras directas en tablas → `42501`); ADMIN conserva catálogo, usuarios, reportes, historial y auditoría; reapertura → `(2)` | PASS |
| Suite SQL vigente completa (tests homologados + E9) | 52 PASS / 21 FAIL — **los 21 preexistentes** (§9.3), **0 nuevos** |
| Diagnóstico complementario (no criterio; no versionado): mismas correcciones H1/H2 de E10 aplicadas en copias a ambos lados | baseline 57/12; E9 61/12; **ningún fallo adicional** con E9 oculto detrás de los preexistentes |
| TP16–TP18 carreras reales E9 (base efímera por carrera) | 13/13 PASS: dos ADMIN abren a la vez y doble envío con la misma clave (una sola jornada); cierre vs crear pedido y vs abrir caja en ambos órdenes; cierre vs cierre; cobro final, cierre de caja, anulación y liberación de mesa en curso vs cierre; apertura en curso vs crear pedido. Sin `40001`, sin interbloqueos, conflictos con `PT409` |
| Carreras E7 vigentes / E10 vigentes | 50 OK / 8 PASS, 0 fallos |
| Carreras H4-T03, H5-T02 (doble entrega y reapertura vs pago) en la suite | un ganador y `PT409` para el perdedor |
| T06 (incremental, TP23, publicación, WAL, RLS por rol) | PASS (ver §8) |
| Suite Node completa | 430/430 PASS |
| `tsc --noEmit` (typecheck) | OK |
| Residuos | 0 slots, 0 conexiones de carrera, 0 bases efímeras |

### 9.3 Fallos preexistentes, ajenos a E9 (pendientes de decisión del responsable)

Demostración: cada prueba fallida con E9 se ejecutó también en la baseline pre-E9 (migraciones hasta `20260930000200`) con la versión del test de `c83c8fd`, extraída con `git archive`. Las 21 fallan allí (la baseline, con los tests de `c83c8fd`, tiene 23 fallos: estos 21 más `h4_t05_realtime_publication_rls` y `h5_t06_realtime_cashier_signal`, que pasan tras la homologación de §9.1). Causas ya descritas en E7-T11 §5.4: tests H3–H6/E1 que esperan `40001` donde E1-T18 normalizó a `PT409`, contratos superados por E7/E10 que sólo se homologaron en copias, y snapshots de catálogo de su época. **No se corrigen** (fuera del alcance de E9; corregirlos alteraría aserciones) ni se reclasifican como esperados: se informan.

| # | Prueba | Error con E9 | Error en la baseline |
|---|---|---|---|
| 1 | `dbstd_t03_function_metadata` | `P0001 DBSTD-TP14 grants de tablas o columnas cambiaron: b29f118c…` | igual con hash `a42c2a24…` (snapshot de grants de su época; E9 añade la tabla, por eso el hash difiere) |
| 2 | `dbstd_t04_catalog_comments` | `P0001 DBSTD-TP16 comentario inesperado: public.registrar_auditoria_detalle_pedido()` | igual (comentario cambiado por E7-D05) |
| 3 | `domain_object_names` | `P0001 Objetos permanentes con prefijo de hito: {function:h3_abrir_o_recuperar_pedido}` | igual |
| 4 | `e1_delta_t09_cobro_atomico` | `PT409 La sesión ya no está abierta` | igual (espera `40001`) |
| 5 | `e1_t09_pagos_multiples` | `PT409 Un pedido con pagos no admite mutaciones` | igual |
| 6 | `h3_t04_open_order_detail_mutations` | `P0001 H3-T04 matriz de privilegios inesperada: <NULL>` | igual |
| 7 | `h4_t03_kitchen_detail_state_transition` | `P0001 H4-T03 contrato, bloqueo o alcance inesperados` | igual |
| 8 | `h5_t02_reopen_delivered_order` | `PT409 El pedido ya no está listo para entregar` | igual |
| 9 | `h5_t02_safe_order_delivery` | `PT409 El pedido ya no está listo para entregar` | igual |
| 10 | `h5_t04_transactional_payment` | `PT409 Pedido no disponible para cobro` | igual |
| 11 | `order_audit_trail` | `P0001 TP21 cambió el cuerpo de registrar_auditoria_detalle_pedido()` | igual |
| 12 | `tp09_tp11_schema` | `P0001 TP-09: expected 10 exact public tables, found 27` | igual con 26 (snapshot de H1; E9 suma `jornada_operativa`) |
| 13 | `e1_t03_caja_sesion` | `P0001 E1-T03: una caja minima por local activo` | igual |
| 14 | `e1_t04_apertura_sesion` | `P0001 T04: TP08 sesion de otra caja rechazada` | igual |
| 15 | `e1_t05_movimientos_cierre` | `PT409 La sesión de caja ya está cerrada` | igual |
| 16 | `e1_t06_descuento_pedido` | `PT409 El pedido no admite descuento` | igual |
| 17 | `e1_t07_anulacion_administrativa` | `PT409 El pedido ya fue anulado` | igual |
| 18 | `e1_t08_pago_sesion` | `P0001 T08: fila pago actor sesion propina clave` | igual |
| 19 | Carrera H4-T03 doble transición cocina — cleanup | `23503 … fk_historial_detalle_pedido_pedido` | igual |
| 20 | Carrera H5-T04 doble pago — “ambas sesiones fallaron” | ambas `PT409` | igual |
| 21 | Carrera H5-T04 doble pago — verify | `P0001 H5-T04 resultado concurrente incorrecto` | igual |

### 9.4 Seguridad, RLS y concurrencia

- RPC nuevas `SECURITY DEFINER` con `search_path = pg_catalog`; contexto y rol validados en servidor; `anon`/`public`/`service_role` sin privilegios sobre `jornada_operativa` ni su secuencia (TP12–TP14).
- RLS: cualquier rol del local lee sus jornadas; otro local no ve nada (T06).
- Inmutabilidad (`23514`) y asignación de jornada no suplantable (`42501`) verificadas (TP06, TP07, TP09). TP09 no desactiva defensas: la fixture cierra J1 con la transición permitida.
- Concurrencia: apertura serializada por `local FOR NO KEY UPDATE`; cierre con `FOR UPDATE` y conteo en sentencia nueva frente al `FOR SHARE` de los triggers; resultado deterministas en las 13 carreras.

### 9.5 Realtime

Sólo señal + relectura autoritativa, sin polling y sin refactor de `operationsRealtimeService` (DC-10/E9-D12). Verificado: publicación, WAL (`test_decoding`), autorización por RLS por rol y reacción del cliente con canal simulado. Pendiente: TP22 con servidor Realtime real (§9.7).

### 9.6 Desviaciones y hallazgos

- **DV-01** (ver §4): pendiente de decisión del responsable.
- **HZ-E9-01** (ver §4): preexistente, informado.
- Homologación de `h4_t05`/`h5_t06`: además de `jornada_operativa` incorporan `solicitud_cuenta`, contrato de E10 que nunca se había llevado al repositorio (se documenta como parte del mismo contrato de publicación).

### 9.7 Pendiente en Windows (stack Supabase local)

`powershell -ExecutionPolicy Bypass -File scripts\e9_t06_local.ps1` → TP22 real, pruebas SQL de E9 sobre la imagen de Supabase, `npm run typecheck` y `npm run build` (el build requiere los binarios nativos win32 de `rolldown`/`lightningcss`, no instalables en el entorno de construcción). Resultado: _pendiente_.

**Estado de T07:** homologación y regresión técnica completas con 0 fallos nuevos; **no se marca completada** hasta registrar §9.7 y la decisión del responsable sobre los 21 fallos preexistentes de §9.3 y DV-01.

**Defectos de E9 abiertos:** ninguno.
