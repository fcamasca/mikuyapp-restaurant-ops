# MikuyApp — Evolución 7 — Mejoras operativas de pedidos: tareas

## 1. Estado

**E7-T01 (Spec Mode) elaborada y ajustada con las decisiones DH-01–DH-04 — pendiente de aprobación humana del Spec.** E7-T02 en adelante **no se han iniciado**. No existen migraciones, RPC, componentes ni pruebas de E7 en el repositorio. No quedan decisiones funcionales pendientes: la construcción comienza sólo tras aprobar los cuatro documentos.

## 2. Tareas

Cada tarea declara sus verificaciones **focalizadas**; la validación integral se concentra en E7-T11 (ver `test-plan.md` §1–2).

| ID | Grupo | Unidad implementable | Depende de | Resultado verificable | Requisitos | Diseño | Verificación focalizada | Est. |
|---|---|---|---|---|---|---|---|---:|
| E7-T01 | Spec | **Elaborada.** Inspección del repositorio; `requirements.md`, `design.md`, `tasks.md`, `test-plan.md`; actualización de la sección E7 de `PLAN_MVP.md`; incorporación de DH-01–DH-04. | E1 cerrada | Cuatro documentos sin código, migraciones ni `acceptance.md`. | Todos | Todos | Revisión documental | 4 h |
| E7-T02 | 1. Base de datos | Migración aditiva: `producto.requiere_cocina`, `detalle_pedido.requiere_cocina` + backfill + `ck_detalle_pedido_sin_cocina_estado`; tablas `historial_detalle_pedido` y `comanda` con constraints, índices, RLS habilitado, triggers de historial e inmutabilidad; grants de columna de `producto`; comentarios. | T01 aprobada | Migración aplicada en local; objetos y restricciones verificados; clientes sin acceso directo a tablas nuevas. | R01, R02, R19, R21, R23, R27 | D02, D03, D11, D12, D14, D19 | Aplicación sobre baseline local; partes estructurales de TP02, TP21, TP26 | 2.5 h |
| E7-T03 | 2. RPC / reglas | `agregar_detalle_pedido` (snapshot + clave de consolidación) y `enviar_pedido_cocina` (sin cocina → `LISTO`, generación de comanda), conservando firmas y errores E1-T18. | T02 | Pedidos con/sin cocina y mixtos derivan correctamente; comanda sólo con líneas de cocina y correlativa. | R02–R05, R07, R08, R20, R22–R24 | D04–D07, D12 | SQL: TP03, TP22; partes SQL de TP05, TP06; parte `ENVIO` de TP20 | 2.5 h |
| E7-T04 | 2. RPC / reglas | `rpc_obtener_tablero_cocina` (detalles/comandas/cancelaciones), filtro `requiere_cocina` en `obtener_tablero_cocina`, `rpc_recibir_pedido_cocina`, `PT409` para detalle inexistente en `actualizar_estado_detalle_cocina`. | T03 | Cocina sólo ve trabajo de cocina; recepción completa idempotente y segura en concurrencia. | R05, R09–R11, R15, R22, R29 | D08, D09, D10, D16 | SQL: TP08; partes SQL de TP05 y TP09; carrera real TP10 | 3 h |
| E7-T05 | 2. RPC / reglas | `rpc_cancelar_detalle_pedido` (locks, matriz de estados, línea completa, idempotencia, rama sin detalles, snapshot en historial) y `rpc_obtener_cancelaciones_pedido`. | T04 | Cancelación trazable, atómica y coherente con total/pedido/mesa; carrera con cocina resuelta. | R12–R19, R21, R22, R29 | D10, D11, D13, D14, D18 | SQL: TP14–TP17; parte `CANCELACION` de TP20; carrera real TP18 | 3.5 h |
| E7-T05B | 2. RPC / reglas | **Aprobada (DH-01).** Reproducir HZ-01; `rpc_modificar_detalle_pedido` y `rpc_retirar_detalle_pedido` con orden `pedido → detalle → mesa` y derivación en el retiro; revocar `UPDATE`/`DELETE` directos y eliminar las dos políticas de mutación directa; adaptar `updateOpenDetail`/`removeOpenDetail` del servicio del mozo conservando interfaz y mensajes; pruebas E7 equivalentes a las aserciones superadas de `h3_t04`. | T05 | HZ-01 reproducido y corregido; edición/retiro con capacidades H3 idénticas y sin interbloqueos. | R32, R33, R21, R31 | D14, D15, D16 | SQL: TP11, TP12; carrera real TP13; Node focal del servicio del mozo (edición/retiro) | 2.5 h |
| E7-T06 | 3. Frontend administrativo | Checkbox “Requiere preparación en cocina” en alta/edición, indicador en lista, validación en `catalogService`. | T02 | ADMIN configura la condición; default marcado. | R01 | D02, D17 | `tests/productAdministration.test.mjs`, `tests/catalogService.test.mjs`; parte UI de TP01 | 1 h |
| E7-T07 | 4. Flujo del mozo | Indicador “Sin cocina”, “Listo para servir”, acción “Cancelar producto” con motivo y guard, sección “Cancelados”, manejo de `PT409`. | T03, T05, T05B | Mozo opera pedidos mixtos y cancela sólo cuando corresponde. | R06, R12–R17 | D10, D13, D17 | `tests/waiterBoard.test.mjs`, `tests/waiterRealtime.test.mjs`; parte mozo de TP19 | 3 h |
| E7-T08 | 5. Cocina | Migrar a `rpc_obtener_tablero_cocina`; botón “Recibir pedido (N)” con guard por pedido; cancelaciones en grupos; conflicto tras cancelación. | T04, T05 | Cocina sin bebidas; recepción completa y cancelaciones visibles; flujo individual intacto. | R05, R09–R11, R15, R17, R30 | D08, D09, D16, D17 | `tests/kitchenBoard.test.mjs`, `tests/kitchenRealtimeService.test.mjs`; parte UI de TP09; parte cocina de TP19 | 3.5 h |
| E7-T09 | 6. Impresión de comandas | `rpc_registrar_impresion_comanda`; comandas en cada grupo con acciones manuales `Imprimir`/`Reimprimir`, “COPIA n” y líneas canceladas; documento 80 mm con `window.print()` hacia la impresora del sistema operativo. Sin preferencias ni almacenamiento del navegador. | T04, T08 | Impresión opcional, deduplicada y trazable sin alterar estados. | R23–R28 | D12, D17 | SQL: TP23, parte SQL de TP24, parte comanda de TP21; Node del componente de comanda | 3.25 h |
| E7-T10 | 7. Integración | Recorrido integrado local → DEV (Preview): pedido mixto, edición/retiro, recepción, cancelación, comanda, dos dispositivos; replay de migraciones E7 sobre baseline; registrar evidencia y defectos. | T02–T09 | Flujo integrado funcionando en DEV; lista de defectos no bloqueantes. | R07, R08, R17, R30, R32 | D16, D19 | Recorrido de TP06, TP07, TP27; replay E7 | 2 h |
| E7-T11 | 8. Pruebas finales y regresión | Ejecución única de TP01–TP31: SQL integral, seguridad, concurrencia, Realtime, regresión H3/H4/H5/E1, replay limpio total, suite Node completa, `typecheck`, `build`. Corregir defectos pendientes. | T10 | Evidencia integral aprobada; cero defectos abiertos. | Todos | D20 | `test-plan.md` §3 completo | 4 h |
| E7-T12 | Validación humana | TH01–TH07 en dispositivos reales con DEV/Preview, incluida la compatibilidad física de la impresora del dispositivo `COCINA`; luego, y sólo con aprobación, crear `acceptance.md`. | T11 | Pruebas humanas aprobadas; aceptación formal posterior. | Todos | Todos | `test-plan.md` §4 | 2 h |

## 3. Orden y dependencias

1. T02 → T03 → T04 → T05 → T05B son secuenciales (misma zona de base de datos y mismo orden de locks).
2. T06 sólo depende de T02 y puede ejecutarse en paralelo con T03–T05B.
3. T07 depende de T03, T05 y T05B (el servicio del mozo ya usa las RPC de edición/retiro); T08 de T04 y T05; T09 de T04 y T08.
4. T10 integra todo; T11 es la única puerta integral; T12 es humana y precede a `acceptance.md`.
5. Dependencias externas: E1 (incluida E1-T18) debe estar aplicada en el ambiente de construcción; E7 no puede desplegarse a PROD antes que E1; PM-002 `TRANSITIONING` limita la construcción a local/DEV/Preview.

## 4. Reglas de validación durante la construcción

1. Cada tarea ejecuta únicamente su columna “Verificación focalizada”.
2. No se ejecuta tras cada tarea: suite Node completa, regresión completa, todos los SQL, `build` repetido, todas las pruebas de seguridad ni la matriz histórica.
3. Cambios sólo SQL no exigen `typecheck`/`build`; cambios sólo UI no exigen SQL.
4. Las carreras reales se ejecutan sólo donde la tarea lo indica (T04: TP10; T05: TP18; T05B: TP13).
5. Defectos bloqueantes se corrigen de inmediato; no bloqueantes se registran en la evidencia de la tarea y se resuelven antes de T11.
6. La validación integral (suite completa, regresión, replay limpio total, SQL integral, seguridad, `typecheck`, `build`) se ejecuta en T11. No reduce cobertura: sólo cambia el momento.
7. Ninguna tarea marca E7 como cerrada. E7 se cierra sólo tras T11, T12 y la aprobación posterior de `acceptance.md`.

## 5. Matriz de trazabilidad Requirement → Design → Task → Test

| Requisito | Diseño | Tareas | Pruebas |
|---|---|---|---|
| E7-R01 Condición de cocina por producto | D02 | T02, T06 | TP01, TH01 |
| E7-R02 Snapshot en detalle | D03 | T02, T03 | TP02, TP03 |
| E7-R03 Consolidación por condición | D04 | T03 | TP03 |
| E7-R04 Sin cocina → `LISTO` al enviar | D05, D06 | T03 | TP05, TP06 |
| E7-R05 Sin trabajo indebido en cocina | D03, D08, D09 | T04, T08 | TP05, TP08, TP27 |
| E7-R06 Identificación para el mozo | D17 | T07 | TP06, TH02 |
| E7-R07 Pedidos mixtos | D07 | T03, T10 | TP06 |
| E7-R08 Estado agregado pedido/mesa | D07 | T03 | TP05–TP07, TP14 |
| E7-R09 Recepción completa | D09 | T04, T08 | TP08, TP10 |
| E7-R10 Procesamiento individual conservado | D09 | T04, T08 | TP08, TP29 |
| E7-R11 Doble clic/reintento/concurrencia | D09 | T04, T08 | TP09, TP10 |
| E7-R12 Estados cancelables | D10 | T05, T07 | TP14, TP15 |
| E7-R13 Línea completa y motivo | D10 | T05, T07 | TP14, TP15 |
| E7-R14 Recálculo total/pedido/mesa | D10 | T05 | TP14, TP16 |
| E7-R15 Concurrencia mozo vs cocina | D10 | T04, T05, T08 | TP10, TP18 |
| E7-R16 Idempotencia de cancelación | D10 | T05 | TP17 |
| E7-R17 Visibilidad de cancelaciones | D08, D13 | T05, T07, T08 | TP19, TP27 |
| E7-R18 Distinta de anulación ADMIN | D18 | T05 | TP15, TP18, TP30 |
| E7-R19 Historial de detalle | D11 | T02–T05 | TP08, TP14, TP20, TP21 |
| E7-R20 `historial_estado` sólo cabecera | D06, D07 | T03, T05 | TP20 |
| E7-R21 Invariantes en PostgreSQL | D03, D14, D15 | T02–T05B | TP01, TP02, TP11, TP12, TP21, TP26 |
| E7-R22 `PT409`, sin `40001` | D09, D10, D14 | T03–T05B, T09 | TP09, TP26 |
| E7-R23 Comanda por envío | D06, D12 | T02, T03 | TP06, TP21, TP22 |
| E7-R24 Comandas posteriores | D12 | T03, T09 | TP07, TP22 |
| E7-R25 Impresión manual opcional 80 mm | D12, D17 | T09 | TP23, TH05 |
| E7-R26 Deduplicación y reimpresión | D12 | T09 | TP23 |
| E7-R27 Trazabilidad de impresión | D12 | T02, T09 | TP23 |
| E7-R28 Impresora no disponible / sin efecto en estados | D12 | T09 | TP24, TH05 |
| E7-R29 Seguridad por rol/local | D14 | T02–T05B, T09 | TP01, TP09, TP25, TP26 |
| E7-R30 Realtime | D16 | T08, T10 | TP27, TP28 |
| E7-R31 Sin regresiones | D01, D15, D18 | T05B, T10, T11 | TP04, TP11, TP12, TP29–TP31, TH06 |
| E7-R32 Retiro con recálculo (HZ-01) | D15 | T05B, T10 | TP12, TP13 |
| E7-R33 Edición/retiro vía RPC con semántica H3 | D15, D16 | T05B | TP11–TP13, TP26, TH02 |

## 6. Estimación

| Alcance | Horas |
|---|---:|
| Spec Mode (T01) | 4 h |
| Construcción T02–T10, incluida T05B | 26.75 h |
| Fase final T11 | 4 h |
| Validación humana T12 | 2 h |
| **Total** | **36.75 h** |

Ajuste respecto del borrador anterior (34.5 h sin T05B / 36 h con T05B condicional de 1.5 h): T05B pasa a ser alcance aprobado y crece a **2.5 h** porque además del retiro normaliza la edición, revoca los grants/políticas de mutación directa y reemplaza con pruebas E7 las aserciones superadas de `h3_t04` (+1 h). T09 baja a **3.25 h** al eliminar la preferencia por dispositivo (−0.25 h). La simplificación del plan de pruebas agrupa escenarios sin reducir validaciones, por lo que T11 conserva 4 h. `PLAN_MVP.md` no registra estimación para E7; esta cifra es referencia de planificación, no tiempo real.

## 7. Riesgos de planificación

- La compatibilidad física entre el navegador del dispositivo `COCINA` y la impresora configurada en su sistema operativo sólo se confirma en TH05; una incompatibilidad no bloquea el flujo digital.
- Si la reproducción de HZ-01 muestra otras rutas sin derivación, se documentan antes de ampliar T05B.
- Cambios en `KitchenBoardPage` y `WaiterOrderPage` concentran varias tareas: se recomienda mantener commits por tarea para acotar revisiones.
