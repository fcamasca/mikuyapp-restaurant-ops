# MikuyApp — Evolución 9 — Jornada operativa del local: tareas

## 1. Estado

**E9: SPEC APROBADO — construcción autorizada (E9-T02–E9-T07); E9-T08 pendiente; no cerrada ni aceptada.** DH-01, DH-02 y DH-03 están resueltas (DC-10, DC-11 y DC-12, `requirements.md` §10.2); no quedan decisiones humanas pendientes. El responsable aprobó el spec (estimación 22 h) y autorizó la construcción de E9-T02 a E9-T07. La evidencia se registra en `implementation.md`.

| Tarea | Estado | Evidencia |
|---|---|---|
| E9-T01 | Completada — spec aprobado; DC-01–DC-12 cerradas | `requirements.md`, `design.md`, `tasks.md`, `test-plan.md` |
| E9-T02 | Completada | `implementation.md` §4 |
| E9-T03 | Completada | `implementation.md` §5 |
| E9-T04 | Completada | `implementation.md` §6 |
| E9-T05 | Completada | `implementation.md` §7 |
| E9-T06 | En curso — falta TP22 con servidor Realtime real (stack Supabase local, Windows) | `implementation.md` §8 |
| E9-T07 | En curso — regresión con 0 fallos nuevos; faltan TP22 real, `npm run build` y la decisión del responsable sobre 21 fallos preexistentes y DV-01 | `implementation.md` §9 |
| E9-T08 | No iniciada | — |

## 2. Tareas

Derivadas directamente de `design.md`. Cada tarea declara sus verificaciones **focalizadas**; la validación integral se concentra en E9-T07 (ver `test-plan.md` §1–2).

| ID | Grupo | Unidad implementable | Depende de | Resultado verificable | Requisitos | Diseño | Verificación focalizada | Est. |
|---|---|---|---|---|---|---|---|---:|
| E9-T01 | Spec | **Elaborada.** Inspección de `main` (`5e3b40b`), `PLAN_MVP.md`, `DATABASE_STANDARD.md`, specs y código de H3–H5, E1, E7 y E10; `requirements.md`, `design.md`, `tasks.md`, `test-plan.md`; hallazgos HZ-01–HZ-09; DH-01–DH-03 planteadas y resueltas por el responsable (DC-10–DC-12). Tras la aprobación final: actualizar el estado de E9 en `PLAN_MVP.md` §15 y en `specs/README.md`. | E10 cerrada en `main` | Cuatro documentos, sin código, migraciones ni `acceptance.md`. | Todos | Todos | Revisión documental | 3 h |
| E9-T02 | 1. Base de datos | Migración aditiva `…_e9_t02_jornada_operativa.sql`: precondición de `pedido`/`sesion_caja` vacías con aborto explícito (DC-12); tabla `jornada_operativa` con checks, FKs, `uq_jornada_operativa_local_abierta`, `uq_jornada_operativa_local_fecha_numero`, `uq_jornada_operativa_idempotencia`, `uq_jornada_operativa_id_local_id`, `idx_jornada_operativa_local_abierta_en` y comentarios; RLS + `pol_jornada_operativa_select_local`; privilegios (tabla y secuencia); `tgf_jornada_operativa_inmutable` + trigger; `fn_obtener_jornada_operativa_abierta`; columnas `jornada_operativa_id` `NOT NULL` con FK compuesta e índice en `pedido` y `sesion_caja`; `tgf_pedido_asignar_jornada_operativa`, `tgf_sesion_caja_asignar_jornada_operativa` y sus triggers; `tgf_pago_validar_jornada_operativa` + trigger; alta idempotente en `supabase_realtime`. | T01 aprobada y construcción autorizada | Migración aplicada sobre la baseline local; objetos, privilegios y publicación verificados; creación de pedido/sesión con y sin jornada abierta según lo previsto usando fixtures directas. | R02–R04, R11, R14–R19, R21, R27 | D03, D04, D05, D06, D09, D11, D12, D17 | Aplicación sobre baseline local; TP01, TP02, TP06, TP07, TP09 | 3 h |
| E9-T03 | 2. RPC / lecturas | Migración `…_e9_t03_rpc_jornada_operativa.sql`: `rpc_abrir_jornada_operativa` (contexto, lock del local, idempotencia, fecha operativa, correlativo, `clock_timestamp()`, `23505` defensivo); `rpc_cerrar_jornada_operativa` (lock de la jornada, idempotencia, verificación en sentencia nueva, `PT409` con conteos); `rpc_obtener_jornada_operativa_actual`, `rpc_obtener_pendientes_cierre_jornada`, `rpc_obtener_historial_jornadas_operativas`; privilegios y comentarios. Sin cambios en las RPC operativas existentes (DC-10). | T02 | Apertura, cierre y lecturas según el estado persistido; carreras de apertura y de cierre vs creación resueltas sin duplicados ni interbloqueos. | R01–R08, R20–R23, R25–R28 | D07, D08, D10, D11 | SQL: TP03–TP05, TP10–TP12, TP14, TP15; carreras reales TP16 y TP17 | 2.5 h |
| E9-T04 | 3. Frontend operativo | `operationalDayService` (lectura, suscripción con topic propio, resync); `OperationalDayGate`, `useOperationalDay`, `LocalClosedScreen` en `App.tsx` para MOZO/COCINA/CAJA en todas sus rutas, incluidas `/ventas` y `/tecnica` (DC-11); fail-closed; `resync` ante `PT409` de local cerrado en `waiterOrderService.openOrder` y en la apertura de caja; identificación de jornada en `CashierPage`. | T03 | Con el local cerrado los tres roles ven “Local cerrado…” y pueden cerrar sesión; al abrir/cerrar la jornada las pantallas cambian sin refrescar. | R09–R12, R29, R31–R33 | D12, D13 | Nuevas pruebas Node del gate y del servicio; `tests/appRoutes.test.mjs`, `tests/waiterBoard.test.mjs`, `tests/cashierPage.test.mjs`, `tests/kitchenRealtimeService.test.mjs` (cocina conserva sus enlaces); TP19, TP21 | 3 h |
| E9-T05 | 4. Frontend ADMIN | Bloque “Jornada operativa” en `AdminHomePage` (abrir/cerrar con confirmación, guard, `ya_existia`/`ya_estaba_cerrada`, pendientes de cierre con enlaces); `OPERACIÓN → Jornadas` en `AdminShell`; ruta `/admin/jornadas` en `appRoutes`/`App.tsx`; página de historial paginado. | T03, T04 (servicio) | El administrador abre, intenta cerrar con pendientes, ve qué lo impide, cierra y consulta el historial. | R01, R05, R06, R13, R20, R22, R23, R25, R30, R32 | D10, D14 | `tests/adminHome.test.mjs`, `tests/appRoutes.test.mjs`, prueba Node nueva del historial; TP20 | 2.5 h |
| E9-T06 | 5. Integración técnica | Recorrido técnico integrado en el ambiente local con las migraciones, RPC y frontend de T02–T05: local cerrado, apertura, operación completa (pedido, cocina, entrega, solicitud de cuenta, cobro parcial), cierre de caja con pendiente, intento de cierre de jornada rechazado, nueva sesión y cobro total, cierre de caja y de jornada, segunda jornada de la misma fecha y jornada con cruce de medianoche simulado por fixture; señal Realtime verificada con clientes Realtime programáticos autenticados por rol (sin dispositivos físicos); replay de las migraciones E9 sobre la baseline; evidencia y defectos. | T02–T05 | Flujo integrado técnicamente correcto; lista de defectos no bloqueantes. | R07, R08, R10, R18, R24, R28, R29 | D04, D08, D12, D15 | TP22 y TP23; replay E9 | 1.5 h |
| E9-T07 | 6. Homologación y pruebas finales | (1) Homologación mínima, directamente en el repositorio, de los tests vigentes impactados por la precondición de E9 (E9-D16): jornada abierta válida antes de crear `pedido`/`sesion_caja`, ajustes de limpieza estrictamente necesarios y actualización de los contratos que E9 cambia deliberadamente (`h4_t05`/`h5_t06` publicación, claves de `to_jsonb(sesion_caja)`), sin alterar comportamiento, datos relevantes, aserciones ni objetivo; registro de cada test actualizado y su motivo. (2) Ejecución única de TP01–TP25: SQL integral, matriz de operaciones con local cerrado, concurrencia, seguridad/RLS, Realtime, regresión H3/H4/H5/H6/E1/E7/E10, replay limpio total, suite Node completa, `typecheck`, `build`. (3) Todo fallo se corrige o, si se sostiene que es ajeno a E9, se demuestra contra la baseline anterior a E9, se documenta individualmente y se informa al responsable antes de dar T07 por finalizada. | T06 | Tests afectados por E9 pasando tras su homologación; ningún fallo aceptado automáticamente; fallos ajenos a E9, si existen, demostrados, documentados e informados; evidencia histórica de aceptación sin cambios; cero defectos abiertos de E9. | Todos | D16, D18 | `test-plan.md` §3 completo | 4.5 h |
| E9-T08 | Validación humana | TH01–TH08 con dispositivos reales (PC ADMIN, celular de mozo, tablet de cocina, PC de caja): validación multi-dispositivo, Realtime, responsive y táctil; aprobación explícita del cierre y redacción de `acceptance.md`. Única tarea con dispositivos físicos. | T07 | Pruebas humanas aprobadas y E9 aceptada/cerrada por el responsable. | Todos | Todos | `test-plan.md` §4 | 2 h |

## 3. Orden y dependencias

1. T02 → T03 son secuenciales (misma zona de base de datos).
2. T04 depende de T03 (RPC de estado y señal); T05 depende de T03 y del servicio de T04. T04 y T05 pueden avanzar en paralelo una vez disponible `operationalDayService`.
3. T06 integra; T07 cierra la validación técnica; T08 la validación humana y la redacción de `acceptance.md`.
4. Dependencias externas: E1, E7 y E10 aplicados en el ambiente de construcción (ya en `main`). T02–T07 se ejecutan en local. Para T08 se requiere un ambiente sin filas en `pedido`/`sesion_caja`; prepararlo es una acción separada y autorizada por el responsable (DC-12), fuera de las tareas de E9. PM-002 `TRANSITIONING` impide tocar `mikuyapp-prod`. La próxima revalidación de PM-002 deberá esperar cinco tablas publicadas.
5. Despliegue: las migraciones E9 y el frontend que permite abrir la jornada deben publicarse juntos en cualquier ambiente con usuarios; aplicar sólo las migraciones deja el local cerrado sin forma de abrirlo desde la interfaz.
6. Relación con E8: E9 no depende de E8. E8 podrá, si lo decide, agregar por jornada usando `pedido.jornada_operativa_id` y `sesion_caja.jornada_operativa_id`; E9 no implementa nada de E8.

## 4. Reglas de validación durante la construcción

1. Cada tarea ejecuta únicamente su columna “Verificación focalizada”.
2. No se ejecuta tras cada tarea: suite Node completa, regresión completa, todos los SQL, `build` repetido, todas las pruebas de seguridad ni la matriz histórica.
3. Cambios sólo SQL no exigen `typecheck`/`build`; cambios sólo UI no exigen SQL.
4. Las carreras reales se ejecutan sólo donde la tarea lo indica (T03: TP16 y TP17; TP18 queda para T07).
5. Defectos bloqueantes se corrigen de inmediato; los no bloqueantes se registran en la evidencia de la tarea y se resuelven antes de T07.
6. No se edita ninguna migración histórica ni la evidencia histórica de aceptación de H1–H6, E1, E7 y E10. Los tests vigentes impactados por la precondición de E9 se homologan directamente en el repositorio en T07, antes de la regresión (E9-D16); Git conserva sus versiones anteriores. No se crean mecanismos de base de datos exclusivos para tests ni tests duplicados que reemplacen a tests que sólo requieren homologación.
7. Ningún fallo de test se acepta por haber existido antes: un fallo ajeno a E9 se demuestra contra la baseline anterior a E9, se documenta individualmente y se informa al responsable antes de finalizar T07.
8. Las pruebas con dispositivos físicos se concentran en T08; T02–T07 usan pruebas automatizadas y clientes programáticos.
9. La evidencia de construcción se registrará en `implementation.md` (patrón E10) cuando la construcción esté autorizada; no forma parte de este Spec Mode.

## 5. Matriz de trazabilidad Requirement → Design → Task → Test

| Requisito | Diseño | Tareas | Pruebas |
|---|---|---|---|
| E9-R01 Apertura sólo ADMIN | D07, D11 | T03, T05 | TP03, TP14, TH01 |
| E9-R02 Una abierta por local | D02, D03, D07 | T02, T03 | TP01, TP04, TP16 |
| E9-R03 Datos de apertura del servidor | D03, D07 | T02, T03 | TP03 |
| E9-R04 Fecha operativa y correlativo | D03, D07 | T02, T03 | TP03, TP05, TH06 |
| E9-R05 Apertura idempotente | D07 | T03, T05 | TP04, TP16, TH02 |
| E9-R06 Identificación visible | D03, D10, D14 | T03, T05 | TP12, TP20, TH01 |
| E9-R07 Sin cierre automático; cruce de medianoche | D03, D08 | T03, T06 | TP05, TP23, TH06 |
| E9-R08 Nueva jornada al reabrir el local | D07 | T03, T06 | TP05, TH06 |
| E9-R09 Pantalla “Local cerrado” y logout (DC-11) | D13 | T04 | TP19, TH03 |
| E9-R10 Cambio sin refrescar | D12, D13 | T04, T06 | TP21, TP22, TH01, TH05 |
| E9-R11 Rechazo autoritativo con local cerrado (DC-10) | D04, D05 | T02, T03, T07 | TP06, TP08, TH07 |
| E9-R12 Fail-closed ante error | D13 | T04 | TP19 |
| E9-R13 ADMIN conserva funciones no operativas | D13, D14 | T04, T05 | TP08, TP20, TH03 |
| E9-R14 Pedido con jornada asignada por servidor | D04, D17 | T02 | TP02, TP06, TP07 |
| E9-R15 Sin jornada no hay pedido (toda vía) | D04, D05 | T02 | TP06, TP08 |
| E9-R16 Jornada del pedido inmutable | D04 | T02 | TP07 |
| E9-R17 Sesión de caja con jornada | D04, D17 | T02 | TP02, TP06, TP07 |
| E9-R18 Pedido y sesión de cobro en la misma jornada | D06 | T02, T06 | TP09, TP23 |
| E9-R19 Sin duplicación de la jornada | D04 | T02 | TP01 |
| E9-R20 Condiciones de cierre | D08 | T03 | TP10, TP17, TH05 |
| E9-R21 Cierre definitivo e inmutable | D08, D09 | T02, T03 | TP10, TP13 |
| E9-R22 Pendientes de cierre visibles | D10, D14 | T03, T05 | TP11, TP20, TH05 |
| E9-R23 Cierre idempotente | D08 | T03, T05 | TP10, TP17 |
| E9-R24 Sin cierre forzado ni traslado | D05, D08, D15 | T03, T06 | TP10, TP23, TH05 |
| E9-R25 Historial ADMIN sin analítica | D10, D14 | T03, T05 | TP12, TP20, TH08 |
| E9-R26 Trazabilidad reconstruible | D03, D04 | T02 | TP15 |
| E9-R27 Seguridad por rol/local, `PT409` | D11 | T02, T03 | TP13, TP14 |
| E9-R28 Concurrencia serializada | D04, D07, D08 | T03, T06 | TP16, TP17, TP18 |
| E9-R29 Realtime señal → relectura | D12 | T02, T04, T06 | TP21, TP22 |
| E9-R30 UI ADMIN | D14 | T05 | TP20, TH01, TH02, TH05, TH08 |
| E9-R31 Jornada visible en Caja | D13 | T04 | TP19, TH04 |
| E9-R32 Responsive y táctil | D13, D14 | T04, T05 | TP19, TP20, TH08 |
| E9-R33 Sin regresiones con local abierto (incluye homologación mínima de fixtures) | D01, D15, D16, D18 | T06, T07 | TP24, TP25, TH04 |

E9-T01 (spec) y E9-T08 (validación humana) cubren todos los requisitos; todo escenario TH de la columna Pruebas se ejecuta en E9-T08 y todo TP en su tarea focalizada o en E9-T07. Las decisiones cerradas se trazan así: DC-10 → R11, R15, D05, T02/T03, TP06/TP08/TP09/TP10; DC-11 → R09, R13, D13, T04, TP19/TH03; DC-12 → D04/D17, T02, TP02.

## 6. Estimación

| Alcance | Horas |
|---|---:|
| Spec Mode (T01) | 3 h |
| Construcción T02–T06 | 12.5 h |
| T07: homologación de tests vigentes en el repositorio y regresión integral | 4.5 h |
| Validación humana T08 (multi-dispositivo) | 2 h |
| **Total propuesto** | **22 h** |

Cifras de referencia de planificación, no tiempo real consumido. Respecto de la versión anterior (21.5 h), T07 sube de 4 h a 4.5 h: el criterio ya no es reproducir la línea base, sino que los tests afectados pasen, y cada fallo restante exige demostración contra la baseline anterior a E9, documentación individual e informe al responsable. La homologación directa en el repositorio no agrega esfuerzo frente a la anterior sobre copias. No incluye la corrección de fallos que se demuestren ajenos a E9 (decisión del responsable) ni la preparación o limpieza de ambientes (DC-12).

## 7. Riesgos de planificación

- La homologación en el repositorio (E9-D16) alcanza a 41 archivos que crean pedidos y 26 que crean sesiones; las limpiezas que borran locales o perfiles deben dejar de hacerlo porque la jornada es inmutable. Es la pieza con mayor incertidumbre de T07; se mitiga con un cambio uniforme, mínimo y registrado por archivo.
- La evidencia de E10 registra fallos de la suite histórica anteriores a E9. Cada uno que siga fallando debe demostrarse contra la baseline anterior a E9, documentarse e informarse; si el responsable decide corregirlo, el esfuerzo queda fuera de la estimación de E9.
- Las pruebas humanas (T08) requieren un ambiente vacío preparado por una acción separada y autorizada (DC-12); si no está disponible, T08 se bloquea aunque T02–T07 estén completas.
- `CashierPage` y `AdminHomePage` ya son extensas; se recomienda mantener la lógica del gate y del bloque de jornada en componentes y funciones puras probadas, y un commit por tarea.
- Los tests vigentes que fijan la publicación Realtime o las claves de sesión de caja se actualizan en el repositorio en T07; la evidencia histórica que los cita no se modifica.
