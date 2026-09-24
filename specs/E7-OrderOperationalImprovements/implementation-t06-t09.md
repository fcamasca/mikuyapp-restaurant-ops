# E7 — Evidencia de construcción: T06–T09

Fecha: 24/09/2026. Rama `feature/E7-OrderOperationalImprovements`, a partir del checkpoint `818e9c4` (T02–T05B aprobado, árbol limpio). No constituye aceptación de E7. T10, T11 y T12 **no iniciadas** por indicación del responsable.

Política aplicada: sólo verificaciones focalizadas por tarea (`tasks.md` §4). No se ejecutaron la suite Node completa, todos los SQL, la regresión completa, el replay integral, `typecheck`, `build` ni la campaña integral de seguridad.

- Node: `node --experimental-strip-types --test <archivos focales>` en el equipo del usuario (Node 22.23.2).
- SQL (T09): PostgreSQL 16.13 local aislado con *shim* de Supabase; migraciones E7 aplicadas sobre copia de la baseline (mismo método y limitación D-6 de `implementation-t02-t05b.md`).

## E7-T06 — Frontend administrativo — COMPLETADA (`49eaf3e`)

- Archivos: `src/services/catalogService.ts`, `src/pages/CategoryAdministrationPage.tsx`, `tests/productAdministration.test.mjs`, `tests/catalogService.test.mjs`.
- Comportamiento: `CatalogProduct.requiere_cocina`; la carta lee la columna; `ProductInput.requiere_cocina` opcional y validado como booleano; el alta envía `requiere_cocina ?? true` (default verdadero); la edición sólo la envía cuando se indica (no sobrescribe con el default); casilla “Requiere preparación en cocina” marcada por defecto y precargada al editar; distintivo “Sin cocina” en la lista. Categorías y demás capacidades sin cambios.
- Focal: `productAdministration.test.mjs` + `catalogService.test.mjs` → **56/56 PASS**.
- Expectativas históricas sustituidas por E7-D02 (documentadas): lista exacta de columnas de la carta (`catalogService.test.mjs`) y *payload* exacto del alta (`productAdministration.test.mjs`), ahora con `requiere_cocina`.
- Pruebas nuevas: alta sin cocina, edición explícita vs omitida, valor no booleano rechazado, roles no ADMIN sin mutación, formulario/indicador.

## E7-T07 — Flujo del mozo — COMPLETADA (`c374f9b`)

- Archivos: `src/services/waiterOrderService.ts`, `src/pages/WaiterOrderPage.tsx`, `tests/waiterBoard.test.mjs`.
- Comportamiento:
  - Distintivo “Sin cocina” en la carta y en cada detalle (snapshot `requiere_cocina` leído del detalle); tras el envío, estado “Listo para servir”.
  - `canCancelOrderDetail`: sólo `ENVIADO`/`RECIBIDO_COCINA` con cocina. `ABIERTO`, `EN_PREPARACION`, `LISTO` y productos sin cocina enviados no muestran la acción y se explica el motivo.
  - “Cancelar producto”: confirmación con producto, cantidad e importe de la línea completa, estado actual, motivo obligatorio (opciones frecuentes + texto, máx. 200) y guard por detalle; `rpc_cancelar_detalle_pedido` sin parámetro de cantidad (DH-04).
  - Éxito y `PT409` resincronizan el snapshot autoritativo (detalles, cabecera y cancelaciones); el conflicto se muestra en la tarjeta.
  - Sección “Cancelados” de sólo lectura (`rpc_obtener_cancelaciones_pedido`), cargada al abrir el pedido y en cada resincronización Realtime.
  - Edición/retiro H3 vía RPC (T05B) sin cambios.
- Focal: `waiterBoard.test.mjs` + `waiterRealtime.test.mjs` → **64/64 PASS** (9 pruebas nuevas E7-T07).

## E7-T08 — Cocina — COMPLETADA (`bd8ca7b`)

- Archivos: `src/services/kitchenRealtimeService.ts`, `src/pages/KitchenBoardPage.tsx`, `tests/kitchenBoard.test.mjs`, `tests/kitchenRealtimeService.test.mjs`.
- Comportamiento:
  - El servicio lee `rpc_obtener_tablero_cocina` (una llamada por refresco), valida la forma `{detalles, comandas, cancelaciones}` y entrega `onSnapshot(detalles, snapshot)`; un snapshot inválido se trata como error recuperable. Los productos sin cocina no llegan (filtro del servidor). Patrón Realtime intacto (6 señales, debounce, segunda carga, resync); sin polling.
  - `receiveOrder` → `rpc_recibir_pedido_cocina`; 0 recibidos = éxito; `PT409` = conflicto recuperable.
  - Botón “Recibir pedido (N)” por grupo (N = detalles `ENVIADO`), guard por pedido; mientras se recibe se bloquean los botones individuales del grupo; siempre resincroniza.
  - Acciones individuales conservadas; `PT409` por producto cancelado muestra “El mozo canceló este producto…”.
  - Cancelaciones del pedido dentro de su grupo (“Cancelado por el mozo · no preparar”) y, si el pedido ya no tiene detalles de cocina, en “Productos cancelados por el mozo”.
- Focal: `kitchenBoard.test.mjs` + `kitchenRealtimeService.test.mjs` → **32/32 PASS** (9 pruebas nuevas E7-T08).
- Expectativas históricas sustituidas por E7-D08 (documentadas): nombre de la RPC y forma de datos en los mocks de `kitchenRealtimeService.test.mjs`; firma `onSnapshot(snapshot, board)` en dos patrones de `kitchenBoard.test.mjs`.

## E7-T09 — Impresión de comandas — COMPLETADA

- Migración: `supabase/migrations/20260924000700_e7_t09_impresion_comanda.sql` — `rpc_registrar_impresion_comanda(bigint, boolean)`: sólo `COCINA` del local; bloquea únicamente la comanda; pedido fuera de `ABIERTO…LISTO` → `PT409`; primera solicitud única (`PT409` si ya existe, “usa Reimprimir”); reimpresión sólo tras la primera; actualiza `impresiones`, `primera_impresion_*` (se conserva) y `ultima_impresion_*`. No toca detalle, pedido ni mesa.
- Frontend: `src/services/kitchenCommandService.ts` (`commandPrintAction`, `commandCopyLabel`, `buildCommandDocument`, `registerPrint`), `src/components/KitchenCommandDocument.tsx` (documento 80 mm con las clases `print-overlay`/`print-document` existentes), `src/pages/KitchenBoardPage.tsx` (comandas por grupo con `Imprimir`/`Reimprimir`, “Sin imprimir” / “Solicitada n veces”, guard por comanda, registro **antes** de abrir el documento; `window.print()` al abrirse; “COPIA n” desde la segunda solicitud; líneas canceladas marcadas “CANCELADO”).
- Sin preferencias, `localStorage`, ESC/POS, bridge, agente, servicio Android, impresión silenciosa ni backend adicional. El documento no ofrece imprimir sin registrar: otra copia exige `Reimprimir`.
- Focal SQL: `supabase/tests/e7_t09_impresion_comanda.sql` → **PASS** (TP23: reimpresión previa rechazada, primera única, segunda primera desde otra sesión `PT409`, dos reimpresiones → 3, trazabilidad; parte SQL de TP24: estados de detalle/pedido/mesa, `modificado_en` e historiales idénticos; parte TP21: contenido inmutable; roles MOZO/CAJA/otro local `42501`; pedido fuera de cocina `PT409`; metadatos de seguridad).
- Carrera real adicional R15 (`scripts/e7_concurrency.sh t09`): dos primeras solicitudes simultáneas → la segunda espera el lock y recibe `PT409`; una sola primera registrada; 0 fallos, sin conexiones residuales.
- Focal Node: `tests/kitchenCommand.test.mjs` (nuevo) + `kitchenBoard.test.mjs` + `kitchenRealtimeService.test.mjs` → **40/40 PASS**.

## Defectos encontrados y corregidos

| Tarea | Defecto | Corrección |
|---|---|---|
| T06 | Aplicar el default `true` también en la edición habría sobrescrito productos “sin cocina” cuando el formulario no envía el campo. | El default sólo se aplica al alta; la edición incluye el campo únicamente si se indica. |
| T09 | El primer borrador del documento tenía un botón para reabrir el diálogo de impresión sin registrar la solicitud (rompía E7-R26/R27). | Se eliminó; otra copia exige `Reimprimir` (registrada). |

No hubo defectos bloqueantes abiertos ni cambios en las RPC de T02–T05B.

## Desviaciones respecto del Spec

| ID | Desviación | Motivo / impacto |
|---|---|---|
| D-7 | Las cancelaciones de un pedido que ya no tiene detalles de cocina se muestran como “Pedido #N” sin mesa. | El snapshot aprobado de cancelaciones (E7-D08) no incluye datos de mesa; no se modificó la RPC de T04 al no ser un defecto bloqueante. |
| D-8 | “COPIA n” se numera desde la segunda solicitud (`impresiones = 3` → “COPIA 2”). | Precisa la etiqueta de E7-D12 (la primera solicitud es el original). |
| D-9 | La reimpresión también se ofrece sólo mientras el pedido está en `ABIERTO…LISTO`; la RPC rechaza con `PT409` fuera de ese rango. | Coincide con E7-D12 (“disponible mientras el pedido esté en ABIERTO…LISTO”). |

## Deuda para T10/T11

- `npm run typecheck` y `npm run build` no se ejecutaron por política: las nuevas firmas (`onSnapshot(rows, snapshot)`, `updateOpenDetail` con snapshot completo, props de `KitchenCommandDocument`) y el JSX de `WaiterOrderPage`/`KitchenBoardPage` se revisaron manualmente (balance de llaves/paréntesis) y deben confirmarse en T11.
- Pruebas históricas que E7 deja obsoletas y requieren tratamiento documentado en T11: `h3_t04_open_order_detail_mutations.sql`, `order_audit_trail.sql` (ver T05B).
- Revalidar en DEV/Preview (PostgreSQL 17 de Supabase) las migraciones `20260924000100`–`20260924000700` (D-6).
- Pruebas humanas pendientes (T12): impresión física con la impresora del sistema operativo del dispositivo `COCINA` (TH05) y uso táctil de las nuevas acciones.
