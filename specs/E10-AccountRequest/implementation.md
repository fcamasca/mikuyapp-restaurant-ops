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

## 4. E10-T03 — RPC y lecturas

**Commit:** ver `git log` (`feat(e10): T03 …`).

**Archivos:**

- `supabase/migrations/20260930000200_e10_t03_solicitar_cuenta_lectura_caja.sql` (nueva, aditiva). Se separó de la migración de T02 según lo previsto en E10-D17: `rpc_solicitar_cuenta_pedido(bigint)` (contexto `MOZO`/local, lock del pedido, matriz de estados, mesa `PENDIENTE_PAGO`, idempotencia por la pendiente existente, `clock_timestamp()` tras el lock, `23505` defensivo resuelto como existente, `PT409`/`42501`/`22023`); recreación atómica (`DROP` + `CREATE`, patrón E1-T10) de `obtener_pedidos_pendientes_pago_caja()` con las 19 columnas previas intactas y, al final, `solicitud_cuenta_id`, `cuenta_solicitada_en`, `cuenta_solicitada_por_nombre`, `servidor_ahora`; privilegios (`EXECUTE` sólo `authenticated`) y comentarios.
- `supabase/tests/e10_t03_solicitud.sql` (nueva).
- `supabase/tests/e10_concurrency_setup.sql`, `e10_concurrency_call.sql`, `e10_concurrency_verify.sql` y `scripts/e10_concurrency.sh` (carreras reales en base efímera).

**Pruebas focalizadas (test-plan §2, T03):**

| Verificación | Resultado |
|---|---|
| Replay completo (59 migraciones + seed) | PASS |
| TP02 — solicitud sobre `ENTREGADO` (sin pagos y con cobro parcial): fila con local/pedido/actor correctos, hora posterior a la entrega, mesa derivable; pedido, mesa, `historial_estado`, `cobro`, `pago`, `descuento_pedido` y `auditoria_caja` idénticos antes y después | PASS |
| TP03 — `ABIERTO`, `ENVIADO`, `RECIBIDO_COCINA`, `EN_PREPARACION`, `LISTO`, reabierto, `PAGADO`, `ANULADO` → `PT409`; nulo → `22023`; otro local, `COCINA`, `CAJA`, `ADMINISTRADOR`, sin sesión y pedido inexistente → `42501`; ningún rechazo crea filas | PASS |
| TP04 — segunda llamada del mismo mozo y de otro mozo: misma solicitud, misma hora y autor, `ya_existia = true`, una sola fila | PASS |
| TP12 — contrato exacto (19 columnas previas + 4 nuevas); pedido con solicitud (nombre del mozo, hora, `servidor_ahora`), con cobro parcial, sin solicitud y multi-línea; pedidos no pendientes excluidos; solicitud `SIN_EFECTO` no aparece tras la reentrega y la nueva sí; `MOZO`, `COCINA`, `ADMINISTRADOR` → `42501`; CAJA de otro local sin filas | PASS |
| Parte SQL de TP14 — ambas funciones `SECURITY DEFINER`, owner `postgres`, `search_path = pg_catalog`, `EXECUTE` sólo `authenticated`, comentadas; lectura `STABLE`; sin `40001` | PASS |
| Regresión puntual de la lectura de Caja: `h5_t03_cashier_pending_orders_read`, `e1_t10_lecturas_autoritativas`, `e1_delta_t10_lecturas_cobro` | PASS (sin homologación: la firma extendida conserva las aserciones históricas) |
| TP05 real — dos mozos simultáneos sobre el mismo pedido | PASS: una fila `PENDIENTE`; A `ya_existia = f`, B `ya_existia = t`; sin `23505` expuesto |
| TP10 real — solicitud antes que cobro final | PASS: el cobro espera el lock y deja la solicitud `ATENDIDA` (`cerrada_en ≥ solicitada_en`) |
| TP10 real — cobro final antes que solicitud | PASS: la solicitud recibe `PT409`, sin filas |
| Carreras: `40001`, `40P01`, conexiones residuales | 0 / 0 / 0 |

**Defectos encontrados / corregidos:** el comentario interno de la RPC mencionaba el literal `40001`, lo que el catálogo de seguridad (búsqueda de `40001` en `prosrc`) contaría como uso manual; se reescribió antes del commit. Ajustes del arnés de carreras (configuración de sesión y `VERBOSITY`).

**Pendientes no bloqueantes:** ninguno. La homologación prevista de `h5_t03`/`e1_t10` resultó innecesaria.

## 5. E10-T04 — Realtime y mozo

**Commit:** ver `git log` (`feat(e10): T04 …`).

**Archivos:**

- `src/services/operationsRealtimeService.ts`: opción `additionalSignalTables` (tipo `AdditionalSignalTable = 'solicitud_cuenta'`), por defecto vacía. Mismo canal, mismo topic único por suscripción (corrección E7-T12 intacta), mismos eventos `INSERT`/`UPDATE`, debounce, coalescencia y resincronización.
- `src/services/waiterOrderService.ts`: `requestBill` (`rpc_solicitar_cuenta_pedido`; `PT409` → conflicto recuperable; otros errores sin éxito falso; rol ajeno sin llamada); `canRequestBill`, `formatBillRequestTime`; lectura embebida `solicitud_cuenta(id,solicitada_en)` filtrada por `estado = 'PENDIENTE'` en `getOrderReview` y `getTableBoard` (misma petición, sin viajes adicionales); campo opcional `cuentaSolicitadaEn` presente sólo si existe una solicitud pendiente (conserva exactamente el contrato previo cuando no hay solicitud).
- `src/pages/WaiterOrderPage.tsx`: botón “Solicitar cuenta” sólo para `ENTREGADO` sin solicitud (≥ 44 px, ancho completo en celular), confirmación en línea con el patrón de “Entregar pedido”, guard `useRef`, resincronización del snapshot tras la respuesta (un pedido no vigente vuelve a mesas por el flujo E7-T12), estado “Cuenta solicitada a caja · hh:mm”, mensaje de “ya estaba solicitada”, aviso de reapertura junto a la carta sin bloquear la reapertura H5; suscripción con `additionalSignalTables: ['solicitud_cuenta']`.
- `src/pages/WaiterTablesPage.tsx`: etiqueta “Cuenta solicitada · hh:mm” en la tarjeta; suscripción con `solicitud_cuenta`.
- `tests/e10AccountRequest.test.mjs` (nueva): servicio, pantallas y Realtime del mozo.
- Cocina (`KitchenBoardPage`, `kitchenRealtimeService`) sin cambios.

**Pruebas focalizadas (test-plan §2, T04):**

| Verificación | Resultado |
|---|---|
| `tests/e10AccountRequest.test.mjs` (TP13, TP17 y parte de TP16: RPC sin datos de identidad, idempotencia, `PT409`, errores y rol ajeno; lectura embebida con filtro `PENDIENTE` y contrato previo intacto sin solicitud; tablero sin viajes extra; matriz `canRequestBill`; botón/confirmación/guard/estado/aviso; cocina con 6 enlaces; mozo con 8 enlaces, topic único, señal `INSERT` → refetch; sin polling) | 12/12 PASS |
| `tests/waiterBoard.test.mjs`, `tests/waiterRealtime.test.mjs`, `tests/kitchenRealtimeService.test.mjs`, `tests/kitchenBoard.test.mjs` | PASS sin modificar (113/113 en total con la nueva prueba) |
| `npm run typecheck` | PASS |

**Defectos:** ninguno. La homologación prevista del conteo de enlaces en `waiterRealtime` resultó innecesaria (la prueba histórica usa sus propias opciones, sin tablas adicionales).

**Pendientes no bloqueantes:** la lectura embebida vía PostgREST y la entrega Realtime real de `solicitud_cuenta` sólo pueden comprobarse con Supabase real (§6).

**Nota de entorno:** las pruebas Node y `typecheck` se ejecutaron en el entorno de construcción con una copia de `node_modules` del responsable.

## 6. E10-T05 — Caja

**Commit:** ver `git log` (`feat(e10): T05 …`).

**Archivos:**

- `src/services/cashierService.ts`: `CashierPendingOrder` incorpora `billRequestId`, `billRequestedAt`, `billRequestedBy`, `serverNow` (mapeados de la lectura extendida; `null` si faltan). Funciones puras: `sortCashierOrders` (solicitudes primero por antigüedad; luego el orden E1 por creación), `cashierDraftFingerprint` (pedido, estado, subtotal, neto, descuento, pagado, saldo), `newBillRequests` y `billRequestElapsedMinutes` (desfase medido con `servidor_ahora`). Ninguna RPC nueva de cobro.
- `src/pages/CashierPage.tsx`: contador “N cuentas solicitadas”, etiqueta “Cuenta solicitada · hace N min” en la lista, punto ámbar en la barra colapsada (sin alterar sus textos accesibles E1), línea “Cuenta solicitada por {mozo} a las hh:mm · hace N min” en el panel, región `aria-live="polite"` que anuncia sólo solicitudes nuevas (sin sonido), reloj de pantalla de 30 s sólo mientras haya solicitudes (no consulta la base), suscripción con `solicitud_cuenta`. **DH-02 B:** `refresh` recibe `preserveDraft`; la señal Realtime pasa `true` y el borrador/confirmación sólo se limpia si cambia la huella autoritativa del pedido seleccionado o si desaparece; cargas iniciales, “Reintentar” y refrescos tras una mutación propia conservan la invalidación E1; un error de lectura también invalida.
- `tests/e10AccountRequest.test.mjs`: 6 pruebas de Caja (TP18).

**Pruebas focalizadas (test-plan §2, T05):**

| Verificación | Resultado |
|---|---|
| `tests/e10AccountRequest.test.mjs` (TP18: mapeo, orden, huella DH-02 B —otra mesa conserva, cambio de saldo/descuento/total o desaparición invalida—, aviso sólo de nuevas, espera con reloj de servidor, cableado Realtime `preserveDraft`, contador/etiqueta/panel/`aria-live`, reloj de pantalla sin consultas, sin acciones nuevas de cobro) | 18/18 PASS (incluye T04) |
| `tests/cashierPage.test.mjs`, `tests/cashierService.test.mjs`, `tests/cashierPrint.test.mjs` | PASS sin modificar |
| `npm run typecheck` | PASS |

**Defectos:** ninguno. **Pendientes no bloqueantes:** ninguno.

## 7. E10-T06 — Integración

**Commit:** ver `git log` (`test(e10): T06 …`).

**Desviación de ambiente (ver §1).** El recorrido “local → DEV con dos dispositivos” no pudo ejecutarse en DEV: no hay Supabase local en Docker ni credenciales de base para DEV, y en `TRANSITIONING` el proyecto DEV también atiende Production, por lo que aplicar migraciones allí queda como acción del responsable. El recorrido se ejecutó en PostgreSQL local con las RPC reales y **actores independientes** (dos mozos, dos cajas, cocina, administrador y usuarios de otro local); la entrega Realtime se verificó por sus dos componentes (autorización RLS del suscriptor y cambios decodificados de la publicación).

**Archivos:** `supabase/tests/e10_t06_integracion.sql`, `scripts/e10_t06_integracion.sh`.

| Verificación | Resultado |
|---|---|
| Migraciones E10 incrementales sobre la línea base (57 + seed): `…0930000100`, `…0930000200` | PASS |
| Replay completo (59 migraciones + seed) | PASS |
| Flujo 1 — pedido mixto con cocina; solicitud rechazada antes de la entrega (`PT409`); solicitud del mozo 1 y repetición del mozo 2 (misma solicitud, autor y hora); la segunda caja la ve; cobro parcial deja `PENDIENTE` y saldo 26; cobro total con dos medios y propina → `PAGADO`/`LIBRE` y `ATENDIDA` (`cerrada_por` = caja 1); segunda caja rechazada con el conflicto E1 (`PT409`); solicitud sobre `PAGADO` → `PT409` | PASS |
| Flujo 2 — solicitud → reapertura por el mozo 2 → `SIN_EFECTO/REAPERTURA`; nueva entrega → nueva solicitud → cobro por la caja 2; historia `SIN_EFECTO/REAPERTURA, ATENDIDA` | PASS |
| Flujo 3 — solicitud → anulación ADMIN → `SIN_EFECTO/ANULACION` (`cerrada_por` = administrador) | PASS |
| Flujo 4 — cobro directo sin solicitud (DH-01 A): sin filas; pedido identificable como “sin solicitud registrada” | PASS |
| TP15 (autorización Realtime emulada: lectura de la fila nueva con rol y claims del suscriptor) | Reciben: mozo 1, mozo 2, caja 1, caja 2. No reciben: cocina, administrador, mozo y caja de otro local, `anon` |
| Señal en WAL (decodificación lógica `test_decoding`; publicación = `detalle_pedido, mesa, pedido, solicitud_cuenta`) | 3 `INSERT` (altas) y 3 `UPDATE` (cierres `ATENDIDA`, `SIN_EFECTO/REAPERTURA`, `SIN_EFECTO/ANULACION`); la repetición idempotente y el cobro sin solicitud no emiten cambios; 0 `DELETE` |
| TP19 (SQL) — intervalos de E8 (`entregado → solicitud`, `solicitud → cierre`, `creación → pago`) derivados con las reglas de E10-D15: no negativos, una sola `ATENDIDA` por pedido pagado con solicitud, cobro final unívoco | PASS |
| Residuos (slots de replicación, bases efímeras) | 0 / 0 |

**HZ-02 — confirmado a nivel de RLS.** Tras la reapertura de un pedido `ENTREGADO`, la fila nueva de `pedido` (`ABIERTO`) no es legible por `CAJA` (`pedido_select_caja_local_cobro` sólo cubre `ENTREGADO`/`PAGADO`) y `CAJA` no tiene política sobre `mesa`; como Supabase Realtime entrega un cambio sólo si el suscriptor puede leer el registro nuevo, Caja **no** recibe señal de esa reapertura (comportamiento heredado de H5). En pedidos con solicitud, la fila `SIN_EFECTO` sí es legible por Caja y produce la señal de E10 (mitigación prevista). Pendiente: observarlo con Realtime real en DEV durante T08. No se corrige en E10 (fuera de alcance).

**Defectos:** ninguno. **Pendientes no bloqueantes:** verificación con Supabase real (§9).

## 8. E10-T07 — Validación final (ejecución única)

**Commits:** `fix(e10): T07 …` (corrección) y `test(e10): T07 …` (campaña y evidencia).

**Runner:** `scripts/e10_t07_campaign.sh` (replay limpio, SQL E10, suite histórica sin homologar y homologada sobre línea base y E10, seguridad/catálogo, carreras reales, integración/WAL, residuos). Nueva prueba complementaria: `supabase/tests/e10_t07_complementos.sql`. `scripts/e10_local_sql_suite.sh` admite `pre-e10` para omitir las pruebas E10 en la línea base.

### 8.1 Resultados

| Verificación | Resultado |
|---|---|
| Replay limpio total | 59 migraciones en orden estricto + seed: OK (línea base 57 + seed: OK) |
| SQL E10 (`e10_t02_modelo`, `e10_t03_solicitud`, `e10_t06_integracion`, `e10_t07_complementos`) | 4/4 PASS |
| Suite histórica sin homologar | Línea base: 44 PASS / 21 FAIL. E10: 46 PASS / 23 FAIL (+2 PASS por las pruebas E10 en B1). Únicas diferencias: `h4_t05_realtime_publication_rls` y `h5_t06_realtime_cashier_signal`, que fijan la publicación exacta de tres tablas |
| Suite histórica homologada (H1 y H2 de E7-T11 en ambas bases; **H3** de E10 sólo en E10: arreglo esperado de la publicación ampliado con `public.solicitud_cuenta` en `h4_t05` y `h5_t06`, en copias temporales) | Línea base 53/12 y E10 57/12: **mismo conjunto de 12 fallos preexistentes** (clasificados en E7-T11 §5.4); `h4_t05` y `h5_t06` pasan completos con H3 |
| Carreras H4/H5 históricas | Idénticas a la línea base (H4-T03, H5-T02 ×2 correctas; H5-T04 preexistente) |
| Carreras E10 reales (TP05, TP10 ×2, TP11 ×5) | 8/8 PASS; sin `40001`, `40P01` ni deadlocks; 0 conexiones residuales |
| Integración y señal WAL (T06) | PASS (incremental, recorrido, 3 `INSERT` + 3 `UPDATE`, 0 `DELETE`) |
| Seguridad | `40001` manual en funciones: 0. `SECURITY DEFINER` inseguras: 0. Tablas sin RLS: 0. Escritura de `anon`: 0. Funciones ejecutables por `anon`: sólo `h3_abrir_o_recuperar_pedido(uuid)` (preexistente, E7-T11 §7). RPC y lectura E10: `EXECUTE` sólo `authenticated`; funciones de trigger sin `EXECUTE`. `solicitud_cuenta`: `authenticated` sólo `SELECT`; `anon` y `service_role` sin privilegios |
| Estados | `pedido`, `mesa` y `detalle_pedido` conservan exactamente sus dominios (sin estados nuevos) |
| Publicación | `detalle_pedido, mesa, pedido, solicitud_cuenta` |
| Suite Node completa (26 archivos) | Primera ejecución: 408/409 (1 fallo, D-1). Tras la corrección: **409/409 PASS** |
| `npm run typecheck` | PASS |
| `npm run build` | **No ejecutable en este entorno**: la guardia de ambiente exige `.env.local`/variables del proyecto y `rolldown` sólo tiene el binario nativo de Windows en `node_modules` (misma limitación que E1-T18/E7). Pendiente en Windows (§9) |
| `git diff --check` (`9c71685..HEAD`) | OK |
| Revisión de secretos | Sin claves, tokens ni contraseñas; sólo referencias de proyecto ya redactadas (`ibfr…uinf`) |
| Residuos | 0 bases efímeras, 0 slots de replicación, 0 conexiones; sin archivos sin versionar |

### 8.2 Defectos de T07

| ID | Defecto | Clasificación | Corrección |
|---|---|---|---|
| D-1 | `tests/h5Realtime.test.mjs` (H5-T06) exige la llamada `refresh(false, () => !disposed)` y prohíbe `setInterval` en `CashierPage`; T05 había agregado un tercer argumento y un reloj con `setInterval` | Regresión real de contrato histórico (no homologable) | `fix(e10): T07`: la recarga con guard de vigencia (sólo la suscripción Realtime) es la que conserva el borrador (DH-02 B intacta); el reloj de pantalla usa `setTimeout` rearmado. Sin cambios en la prueba histórica; `e10AccountRequest` actualizada. Suite 409/409 |
| — | `registrar_pago_pedido(bigint,text)` (H5) sigue pagando pedidos | Observación (HZ-05 del spec) | Cubierto: el trigger cierra la solicitud también por esta vía (TP06) |

### 8.3 Matriz TP01–TP21

| TP | Resultado | Evidencia |
|---|---|---|
| TP01 | Aprobada | `e10_t02_modelo`; §8.1 seguridad/publicación |
| TP02 | Aprobada | `e10_t03_solicitud` |
| TP03 | Aprobada | `e10_t03_solicitud` |
| TP04 | Aprobada | `e10_t03_solicitud`; `e10_t06_integracion` |
| TP05 | Aprobada | Carrera real |
| TP06 | Aprobada | `e10_t02` (trigger), `e10_t06` (parcial/total con N medios y propina, sin solicitud), `e10_t07` (vías históricas, cobro fallido, descuento autorizado) |
| TP07 | Aprobada | `e10_t02`, `e10_t03` (reabierto → `PT409`), `e10_t06` (flujo 2), `e10_t07` (retiro E7 HZ-01, reapertura bloqueada tras parcial) |
| TP08 | Aprobada | `e10_t02`, `e10_t06` (flujo 3), `e10_t07` (sin solicitud) |
| TP09 | Aprobada | `e10_t02`; `e10_t07` (`TRUNCATE`/`DELETE` de `service_role` → `42501`) |
| TP10 | Aprobada | Carreras reales (ambos órdenes) |
| TP11 | Aprobada | Carreras reales (reapertura y anulación en ambos órdenes; dos cajas) |
| TP12 | Aprobada | `e10_t03_solicitud`; `h5_t03`, `e1_t10`, `e1_delta_t10` sin homologar |
| TP13 | Aprobada (Node); **PostgREST real pendiente** | `e10AccountRequest` (petición embebida y filtro); verificación con Supabase real en §9 |
| TP14 | Aprobada | `e10_t02`, `e10_t03`, `e10_t07`; §8.1 |
| TP15 | Aprobada con desviación; **Realtime real pendiente** | `e10_t06` (autorización RLS emulada por suscriptor) y WAL de la publicación; entrega a clientes reales en §9 |
| TP16 | Aprobada (Node); **red real pendiente** | `e10AccountRequest` (topic único, 8/6 enlaces, coalescencia, sin polling), `waiterRealtime`/`h5Realtime`/`kitchenRealtimeService` (duplicados, reconexión, remontaje E7-T12) |
| TP17 | Aprobada | `e10AccountRequest` |
| TP18 | Aprobada | `e10AccountRequest` |
| TP19 | Aprobada | `e10_t06_integracion` |
| TP20 | Aprobada | §8.1 (mismos fallos preexistentes con homologaciones H1–H3; Node 409/409) |
| TP21 | Aprobada salvo `build` | Replay, SQL, Node, `typecheck` PASS; `build` pendiente en Windows |

## 9. Pendientes antes de E10-T08 (validación humana)

Ninguno es un defecto abierto de E10; todos derivan de la desviación de ambiente (§1) y requieren acción del responsable:

1. **`npm run build` en Windows** con `.env.local` (guardia de ambiente y `rolldown` nativo).
2. **Aplicar en DEV** (`ibfr…uinf`) las migraciones `20260930000100_e10_t02_solicitud_cuenta.sql` y `20260930000200_e10_t03_solicitar_cuenta_lectura_caja.sql`. Son aditivas y compatibles con el frontend ya desplegado (la lectura de Caja conserva sus 19 columnas; la publicación sólo agrega una tabla), pero en `TRANSITIONING` ese proyecto también atiende Production: decisión del responsable. No tocar `mikuyapp-prod`.
3. **Verificación con Supabase real antes o al inicio de T08:** entrega Realtime de `solicitud_cuenta` a mozo y caja (TP15/TP16 con red real), lectura embebida `solicitud_cuenta(...)` de PostgREST (TP13) y observación de HZ-02 (Caja no recibe la reapertura de un pedido sin solicitud; sí recibe el `SIN_EFECTO` de uno con solicitud).
4. **PM-002:** la próxima revalidación debe esperar cuatro tablas publicadas (HZ-03).

**Estado:** E10-T02–E10-T07 técnicamente completas en el entorno descrito. E10-T08 no iniciada; no existe `acceptance.md`; E10 no está cerrada.
