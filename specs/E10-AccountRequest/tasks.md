# MikuyApp — Evolución 10 — Solicitud de cuenta y atención en caja: tareas

## 1. Estado

**SPEC APROBADO (30/09/2026)** con DH-01 = A y DH-02 = B. La construcción queda habilitada a partir de E10-T02 y todavía no se inició.

| Tarea | Estado |
|---|---|
| E10-T01 | Completada — Spec aprobado 30/09/2026 |
| E10-T02–E10-T08 | Pendientes (habilitadas, no iniciadas) |

## 2. Tareas

Derivadas directamente de `design.md`. Cada tarea declara sus verificaciones **focalizadas**; la validación integral se concentra en E10-T07 (ver `test-plan.md` §1–2).

| ID | Grupo | Unidad implementable | Depende de | Resultado verificable | Requisitos | Diseño | Verificación focalizada | Est. |
|---|---|---|---|---|---|---|---|---:|
| E10-T01 | Spec | **Elaborada.** Inspección del repositorio (`main` `ee3c94c`); `requirements.md`, `design.md`, `tasks.md`, `test-plan.md`; incorporación de E10 y ajuste de E8 en `PLAN_MVP.md`; hallazgos HZ-01–HZ-06; DH-01/DH-02. | E7 integrada en `main` | Cuatro documentos sin código, migraciones ni `acceptance.md`. | Todos | Todos | Revisión documental | 3 h |
| E10-T02 | 1. Base de datos | Migración aditiva: tabla `solicitud_cuenta` (checks, FKs, `uq_solicitud_cuenta_pedido_pendiente`, `idx_solicitud_cuenta_pedido_solicitada_en`, comentarios); RLS y `pol_solicitud_cuenta_select_local`; `GRANT SELECT` a `authenticated` y `REVOKE` a `public/anon/service_role` (tabla y secuencia); `tgf_solicitud_cuenta_inmutable`; `tgf_pedido_cerrar_solicitud_cuenta` con su trigger `AFTER UPDATE OF estado … WHEN old.estado = 'ENTREGADO'`; alta idempotente en `supabase_realtime`. | T01 aprobada | Migración aplicada sobre la baseline local; objetos, privilegios y publicación verificados; cierre automático operativo al cambiar el estado de un pedido de prueba. | R03, R09–R12, R15, R16 | D03, D05, D06, D07, D09, D17 | Aplicación sobre baseline local; TP01; partes SQL de TP06–TP09 con fixtures directas | 2 h |
| E10-T03 | 2. RPC / lecturas | `rpc_solicitar_cuenta_pedido` (contexto, lock del pedido, matriz de estados, idempotencia, `clock_timestamp()`, `23505` defensivo, `PT409`); recreación extendida de `obtener_pedidos_pendientes_pago_caja` con `solicitud_cuenta_id`, `cuenta_solicitada_en`, `cuenta_solicitada_por_nombre`, `servidor_ahora`, restaurando privilegios y comentario. | T02 | Solicitud creada/recuperada según el estado persistido; lectura de Caja coherente en un solo snapshot; columnas previas idénticas. | R01–R05, R06, R08, R15, R17 | D04, D08, D09, D12 | SQL: TP02–TP04, TP12, parte SQL de TP14; carreras reales TP05 y TP10 | 2 h |
| E10-T04 | 3. Realtime y mozo | Opción `additionalSignalTables` en `operationsRealtimeService` (por defecto sin cambios); `waiterOrderService.requestBill` y lecturas embebidas en `getOrderReview`/`getTableBoard`; `WaiterOrderPage`: “Solicitar cuenta” con confirmación y guard, estado “Cuenta solicitada · hh:mm”, `PT409` → resync/`order-not-current`, aviso de reapertura; `WaiterTablesPage`: etiqueta “Cuenta solicitada”; suscripciones de mozo con `solicitud_cuenta`. | T03 | Mozo solicita desde celular, ve el estado en pedido y mesas; cocina conserva seis enlaces. | R01, R04, R16, R18, R20 | D07, D08, D13 | `tests/waiterBoard.test.mjs`, `tests/waiterRealtime.test.mjs`, `tests/kitchenRealtimeService.test.mjs` (sin cambios de conteo); TP13, TP17 | 2.5 h |
| E10-T05 | 4. Caja | `cashierService.getPendingOrders` mapea los campos nuevos; `CashierPage`: orden por solicitud, etiqueta “Cuenta solicitada · hace N min” (también en barra colapsada), contador, línea en el panel, región `aria-live` para solicitudes nuevas, suscripción con `solicitud_cuenta`; **DH-02 B:** invalidación del borrador sólo si cambia la huella del pedido seleccionado. Sin nuevas acciones de cobro. | T03, T04 (opción Realtime) | Caja ve y prioriza solicitudes sin refrescar; el cobro E1 no cambia; una solicitud de otra mesa no borra el cobro en curso. | R06–R08, R16, R19, R20, R22 | D07, D08, D11, D14 | `tests/cashierService.test.mjs`, `tests/cashierPage.test.mjs`, `tests/cashierPrint.test.mjs`; TP18 | 2.5 h (1.75 h con DH-02 A) |
| E10-T06 | 5. Integración | Recorrido local → DEV con dos dispositivos (mozo celular + caja PC) y segunda caja/segundo mozo: solicitud, repetición, cobro parcial y total, reapertura, anulación; confirmar HZ-02 y registrar resultado; replay de la migración E10 sobre la baseline; evidencia y defectos. | T02–T05 | Flujo integrado funcionando en DEV; lista de defectos no bloqueantes. | R09–R11, R16, R17 | D05, D07, D12, D16 | Recorrido de TP15 y TP19; replay E10 | 1.5 h |
| E10-T07 | 6. Pruebas finales y regresión | Ejecución única de TP01–TP21: SQL integral, concurrencia, seguridad/RLS, Realtime, regresión H3/H4/H5/H6/E1/E7 con homologación documentada (`h4_t05`, `h5_t03`/`e1_t10`, conteo de enlaces del mozo), replay limpio total, suite Node completa, `typecheck`, `build`. Corregir defectos pendientes. | T06 | Evidencia integral aprobada; cero defectos abiertos. | Todos | D18 | `test-plan.md` §3 completo | 3 h |
| E10-T08 | Validación humana | TH01–TH07 en celular, tablet y PC con DEV/Preview; luego, y sólo con aprobación, crear `acceptance.md`. | T07 | Pruebas humanas aprobadas; aceptación formal posterior. | Todos | Todos | `test-plan.md` §4 | 1.5 h |

## 3. Orden y dependencias

1. T02 → T03 son secuenciales (misma migración/zona de base de datos).
2. T04 depende de T03 (RPC y lectura embebida); T05 depende de T03 y de la opción Realtime de T04. T04 y T05 pueden avanzar en paralelo una vez disponible la opción `additionalSignalTables`.
3. T06 integra todo; T07 es la única puerta integral; T08 es humana y precede a `acceptance.md`.
4. Dependencias externas: E1 y E7 aplicadas en el ambiente de construcción (ya en `main`); PM-002 `TRANSITIONING` limita la construcción a local/DEV/Preview y la próxima revalidación de PM-002 deberá esperar cuatro tablas publicadas; E10 no puede desplegarse a PROD antes que E1 y E7.
5. Relación con E8: E10 no depende de E8. E8, cuando se especifique, consumirá los datos de E10 para distinguir tiempo del cliente y tiempo de Caja; puede ejecutarse antes que E10, pero en ese caso no podrá desagregar `ENTREGADO → PAGADO`.

## 4. Reglas de validación durante la construcción

1. Cada tarea ejecuta únicamente su columna “Verificación focalizada”.
2. No se ejecuta tras cada tarea: suite Node completa, regresión completa, todos los SQL, `build` repetido, todas las pruebas de seguridad ni la matriz histórica.
3. Cambios sólo SQL no exigen `typecheck`/`build`; cambios sólo UI no exigen SQL.
4. Las carreras reales se ejecutan sólo donde la tarea lo indica (T03: TP05 y TP10; la carrera TP11 queda para T07).
5. Defectos bloqueantes se corrigen de inmediato; los no bloqueantes se registran en la evidencia de la tarea y se resuelven antes de T07.
6. Ninguna tarea marca E10 como cerrada. E10 se cierra sólo tras T07, T08 y la aprobación posterior de `acceptance.md`.

## 5. Matriz de trazabilidad Requirement → Design → Task → Test

| Requisito | Diseño | Tareas | Pruebas |
|---|---|---|---|
| E10-R01 Solicitud sobre `ENTREGADO` | D04, D13 | T03, T04 | TP02, TP03, TP17, TH01 |
| E10-R02 Sólo cuenta total, sin efecto financiero | D01, D04, D11 | T03 | TP02, TP06, TH03 |
| E10-R03 Datos mínimos y derivación segura | D03, D04 | T02, T03 | TP01, TP02, TP19 |
| E10-R04 Una pendiente por pedido / idempotencia | D03, D04, D12 | T02, T03, T04 | TP04, TP05, TP17, TH02 |
| E10-R05 Decisión sobre estado persistido | D04, D12 | T03 | TP03, TP10, TP11 |
| E10-R06 Caja ve solicitudes en tiempo real | D07, D08, D14 | T03, T05 | TP12, TP15, TP18, TH01 |
| E10-R07 Atención con cobro E1 existente | D11 | T05 | TP06, TP20, TH03 |
| E10-R08 Cobro sin solicitud (DH-01) | D11 | T03, T05 | TP06, TH06 |
| E10-R09 Cierre `ATENDIDA` en el cobro final | D05 | T02 | TP06, TP10, TP19 |
| E10-R10 `SIN_EFECTO` por reapertura | D05 | T02 | TP07, TP11, TH04 |
| E10-R11 `SIN_EFECTO` por anulación | D05 | T02 | TP08, TP11 |
| E10-R12 Inmutabilidad | D06, D09 | T02 | TP09, TP14 |
| E10-R13 Datos para E8 | D15 | T02, T03 | TP19 |
| E10-R14 Sin backfill; pedidos sin solicitud identificables | D15 | T02 | TP06, TP19 |
| E10-R15 Seguridad por rol/local, `PT409` | D09 | T02, T03 | TP03, TP14 |
| E10-R16 Realtime señal → refetch, sin polling | D07 | T02, T04, T05, T06 | TP15, TP16 |
| E10-R17 Concurrencia serializada por pedido | D05, D12 | T03, T06 | TP05, TP10, TP11 |
| E10-R18 UI del mozo | D08, D13 | T04 | TP13, TP17, TH01, TH02, TH04 |
| E10-R19 UI de Caja | D14 | T05 | TP18, TH01, TH05 |
| E10-R20 Responsive y táctil | D13, D14 | T04, T05 | TP17, TP18, TH07 |
| E10-R21 Sin regresiones | D01, D16, D18 | T06, T07 | TP20, TP21, TH03, TH06 |
| E10-R22 Borrador de Caja conservado (DH-02) | D14 | T05 | TP18, TH05 |

## 6. Estimación

| Alcance | Horas |
|---|---:|
| Spec Mode (T01) | 3 h |
| Construcción T02–T06 | 10.5 h |
| Fase final T07 | 3 h |
| Validación humana T08 | 1.5 h |
| **Total (con DH-01 A y DH-02 B, aprobadas)** | **18 h** |

Variantes: con DH-02 A el total baja a **17.25 h** (T05 −0.75 h). Con DH-01 B se agregarían ≈ **2.5 h** (validación en todas las vías de pago, pruebas E1 ampliadas y UX de rechazo en Caja). Cifras de referencia de planificación, no tiempo real consumido.

## 7. Riesgos de planificación

- La semántica exacta de Realtime ante un `UPDATE` que deja la fila fuera de la RLS del suscriptor (HZ-02) se confirma en T06; no cambia el diseño de E10.
- `CashierPage` concentra la mayor parte del cambio de UI y ya es extenso (≈1.200 líneas); se recomienda un commit por tarea y mantener la lógica de ordenamiento y huella en funciones puras probadas.
- La homologación de pruebas históricas que fijan la publicación o la firma de la lectura de Caja debe documentarse en T07 sin editar la evidencia histórica.
