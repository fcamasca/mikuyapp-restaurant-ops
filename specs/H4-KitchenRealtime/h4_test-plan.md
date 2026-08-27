# MikuyApp — H4 Cocina en tiempo real: plan de pruebas

## Estado y clasificación

**CERRADO / VALIDADO / ACEPTADO.** H4-TA, H4-TM y H4-TH01–H4-TH06 fueron aprobadas; la decisión final se registra en `acceptance.md`. Las pruebas se separan en:

- **Automatizadas (H4-TA):** contratos de servicios/UI y SQL ejecutable en entorno controlado.
- **Técnicas manuales (H4-TM):** inspección remota de esquema, privilegios, Realtime, concurrencia y recuperación.
- **Humanas (H4-TH):** operación táctil, comprensión visual y comportamiento real entre dispositivos.

Las pruebas automatizadas no sustituyen las humanas. PostgreSQL es la autoridad para resultados funcionales; Realtime solo transporta señales.

## Preparación y datos

- Usuarios activos de prueba `COCINA`, `MOZO`, `ADMINISTRADOR` y `CAJA`, con al menos dos locales para aislamiento.
- Mesas y pedidos controlados con detalles en todos los estados admitidos.
- Dos navegadores, perfiles o dispositivos independientes para concurrencia y Realtime.
- Fixtures SQL siempre dentro de transacción con `ROLLBACK` o limpieza explícita verificable.
- Reloj del cliente no se usa para persistir antigüedad; la fecha proviene de PostgreSQL.

## Pruebas automatizadas

| ID | Caso | Resultado esperado |
|---|---|---|
| H4-TA01 | Ruta y destino de `COCINA`; otros roles intentan acceder. | Cocina entra a `/cocina`; roles no autorizados reciben `/403`; sesión ausente va a login. |
| H4-TA02 | Snapshot con detalles de los cuatro estados de cocina, un `ABIERTO` y pedidos terminales. | Se devuelven únicamente `ENVIADO`, `RECIBIDO_COCINA`, `EN_PREPARACION`, `LISTO` de pedidos no terminales del local; se excluyen `ENTREGADO`, `PAGADO` y `ANULADO`. |
| H4-TA03 | Render de mesa, pedido, producto, cantidad, observación y estado. | Todos los datos requeridos son visibles; ausencia de observación se representa sin texto falso. |
| H4-TA04 | Detalles enviados en momentos distintos, incluidos agregados posteriores. | Orden estable por `detalle_pedido.enviado_en`; tiempo transcurrido usa ese instante. |
| H4-TA05 | Secuencia válida completa por detalle. | `ENVIADO → RECIBIDO_COCINA → EN_PREPARACION → LISTO`. |
| H4-TA06 | Cantidad mayor a uno. | El estado cambia para la línea completa; no aparece estado por unidad. |
| H4-TA07 | Cliente intenta `UPDATE estado` directo. | Rechazado; la única vía autorizada es la función. |
| H4-TA08 | Saltos, retrocesos, detalle abierto, pedido terminal y otro local. | Todas las transiciones se rechazan sin cambios parciales. |
| H4-TA09 | Dos llamadas simultáneas con el mismo estado esperado. | Una confirma; la otra detecta conflicto y recupera el ganador. |
| H4-TA10 | Pedido con detalles en estados distintos. | Cada línea conserva su estado y acción válida; no se homogeneiza el grupo. |
| H4-TA11 | Nuevo detalle enviado mientras otro está `EN_PREPARACION`. | Aparece como `ENVIADO`; el anterior no cambia ni retrocede. |
| H4-TA12 | Nuevo detalle enviado cuando otros están `LISTO`. | Nuevo trabajo aparece separado; los listos permanecen listos. |
| H4-TA13 | Derivación agregada de cabecera con combinaciones de estados. | Prevalece el estado menos avanzado existente y cada cambio real genera historial. |
| H4-TA14 | Cabecera avanzada y agregado posterior. | La cabecera se recalcula a `ABIERTO` al agregar y a `ENVIADO` al enviar; detalles anteriores no retroceden. |
| H4-TA15 | Todos los detalles llegan a `LISTO`. | Mesa pasa a `PEDIDO_LISTO` atómicamente. |
| H4-TA16 | Agregado posterior sobre mesa `PEDIDO_LISTO`. | Mesa vuelve a `OCUPADA`; mismo pedido vigente; cabecera se recalcula a `ABIERTO`. |
| H4-TA17 | Auditoría antes/después de transición de cocina. | Cambia `detalle.modificado_*` con actor servidor; creación y `pedido.modificado_*` permanecen iguales. |
| H4-TA18 | Evento INSERT de detalle enviado. | Cocina incorpora una sola card sin refresh. |
| H4-TA19 | Evento UPDATE de estado. | Cocina y mozo recargan/reflejan el estado persistido sin escribirlo localmente. |
| H4-TA20 | Eventos múltiples, repetidos o fuera de orden. | Las señales se agrupan cuando corresponde, se recarga el snapshot y la UI converge al estado PostgreSQL sin cards duplicadas. |
| H4-TA21 | Desconexión, cambios durante desconexión y reconexión. | Resincro recupera todos los cambios sin polling ni duplicados. |
| H4-TA22 | Error RPC, doble tap y guard por detalle. | Una llamada pendiente por detalle, feedback local, guard liberado y sin falso éxito. |
| H4-TA23 | Contratos responsive y accesibles. | Sin overflow crítico; texto de estado; controles principales ≥44 px. |

## Pruebas técnicas manuales

| ID | Verificación | Evidencia requerida |
|---|---|---|
| H4-TM01 | RLS/privilegios por rol y local para snapshot, tablas y función. | Matriz de grants/policies y ejecuciones con los cuatro roles y otro local. |
| H4-TM02 | Columna `enviado_en`, backfill, inmutabilidad, check e índice. | Catálogo PostgreSQL y casos válidos/inválidos aprobados. |
| H4-TM03 | Definición de `actualizar_estado_detalle_cocina`. | `SECURITY DEFINER`, dueño `postgres`, `search_path`, `auth.uid()`, lock y grants correctos. |
| H4-TM04 | Ausencia de mutación directa. | `authenticated` sin privilegio de estado/cabecera/mesa; `PUBLIC` y `anon` sin ejecución. |
| H4-TM05 | Concurrencia y rollback inducido. | Dos sesiones reales; una transición ganadora; error revierte detalle, cabecera, historial y mesa. |
| H4-TM06 | Matriz de derivación con estados mixtos y agregados posteriores. | Consultas antes/después demuestran cabecera agregada recalculable, detalles sin retroceso y mesa derivada. |
| H4-TM07 | Auditoría operativa. | UUID del actor coincide con `auth.uid()`; detalle cambia; auditoría comercial de pedido se conserva; FK `RESTRICT`. |
| H4-TM08 | Publicación, desconexión y resincro real. | Tablas estrictamente necesarias publicadas; cambios offline aparecen al reconectar, sin residuos. |
| H4-TM09 | Regresión y calidad. | Suite H1–H4, typecheck, build, rutas, responsive técnico, auditoría de nombres, `db lint --linked`, migraciones sincronizadas, fixtures 0 y `git diff --check`. |

## Pruebas humanas

| ID | Escenario | Criterio de aprobación |
|---|---|---|
| H4-TH01 | Tablero en tablet vertical y horizontal. | Se identifican mesa, productos, cantidades, observaciones y estados sin overflow crítico; acciones táctiles claras. |
| H4-TH02 | Antigüedad y tiempo transcurrido. | El trabajo más antiguo se reconoce primero y el tiempo es legible/coherente para un agregado posterior. |
| H4-TH03 | Flujo por detalle. | Cocina recibe, inicia preparación y marca listo sin confundir ni modificar otras líneas. |
| H4-TH04 | Mozo agrega y envía un detalle con otros en preparación/listos. | La cabecera se recalcula, el nuevo trabajo aparece sin refresh en cocina y los detalles anteriores no retroceden ni se reabren. |
| H4-TH05 | Reflejo hacia el mozo. | Cambios de cocina y `PEDIDO_LISTO` aparecen sin refresh y coinciden con PostgreSQL. |
| H4-TH06 | Dos dispositivos, conflicto, pérdida de conexión y reconexión. | No hay duplicados ni falso éxito; la sesión perdedora muestra el ganador y la reconexión resincroniza. |

Registrar dispositivo, navegador, viewport y orientación cuando estén disponibles. No fabricar metadata ausente.

## Matrices obligatorias

### Transiciones

| Desde | Hacia | Resultado |
|---|---|---|
| `ENVIADO` | `RECIBIDO_COCINA` | Permitida a `COCINA`. |
| `RECIBIDO_COCINA` | `EN_PREPARACION` | Permitida a `COCINA`. |
| `EN_PREPARACION` | `LISTO` | Permitida a `COCINA`. |
| Cualquier estado | El mismo estado | Conflicto/no-op explícito; sin historial duplicado. |
| Cualquier estado | Salto o retroceso | Rechazado. |
| `ABIERTO` | Estado de cocina | Rechazado; debe enviarlo el mozo. |
| `LISTO` | Cualquier estado de detalle | Rechazado en H4. |

### Estados mixtos y derivados

Se deben probar, como mínimo: `ABIERTO + LISTO → ABIERTO`, `ENVIADO + LISTO → ENVIADO`, `ENVIADO + RECIBIDO_COCINA → ENVIADO`, `RECIBIDO_COCINA + EN_PREPARACION → RECIBIDO_COCINA`, `EN_PREPARACION + LISTO → EN_PREPARACION`, todos `LISTO → LISTO`, cabecera `LISTO` con nuevo `ABIERTO → ABIERTO` y su envío posterior `→ ENVIADO`.

## Criterio de finalización

H4-T10 no se completa si falla una prueba obligatoria, queda una validación humana requerida sin evidencia, hay migraciones desincronizadas o existen fixtures residuales. Completar H4-T10 no equivale a aceptar H4; la aceptación requiere una decisión humana posterior y un documento separado que no se crea durante el Spec ni la construcción inicial.
