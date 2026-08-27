# MikuyApp — H3 Flujo del mozo: plan de pruebas

## 1. Pruebas automatizadas

Estas pruebas validan reglas funcionales, datos, transacciones y servicios sin depender de inspección visual.

| ID | Caso | Resultado esperado |
|---|---|---|
| H3-TA01 | Crear pedido en mesa libre. | Se crea una sola cabecera `ABIERTO`, historial inicial y mesa `OCUPADA`. |
| H3-TA02 | Dos clientes intentan crear pedido en la misma mesa. | Una operación gana; no existe una segunda cabecera vigente. |
| H3-TA03 | Recargar y recuperar un pedido vigente en cada estado real. | Se recupera para `ABIERTO`, `ENVIADO`, `RECIBIDO_COCINA`, `EN_PREPARACION`, `LISTO` y `ENTREGADO`; no para `PAGADO` o `ANULADO`. |
| H3-TA04 | Agregar o consolidar producto con la función de servidor. | PostgreSQL controla precio y estado; consolida atómicamente producto + observación equivalente solo contra un detalle `ABIERTO`. Observaciones diferentes o detalles enviados producen una nueva línea `ABIERTO`. |
| H3-TA05 | Intentar falsear `precio_unitario` o solicitar estado `ENVIADO` al agregar. | El contrato no acepta esos valores y no existe `INSERT` directo; precio y estado resultan definidos por PostgreSQL. |
| H3-TA06 | Modificar cantidad/observación y retirar detalle `ABIERTO`. | Solo el detalle abierto cambia o se elimina; el total se recalcula correctamente. |
| H3-TA07 | Modificar o retirar detalle `ENVIADO` o posterior. | La operación es rechazada y no produce cambios parciales. |
| H3-TA08 | Guardar observación frecuente y libre. | El texto final queda en `detalle_pedido.observacion`, sin catálogo adicional. |
| H3-TA09 | Calcular el total. | Coincide con la suma de `cantidad * precio_unitario` de todos los detalles existentes. |
| H3-TA10 | Envío inicial. | La función cambia los detalles `ABIERTO → ENVIADO`, cambia la cabecera `ABIERTO → ENVIADO`, registra el historial de cabecera y fija `pedido.enviado_en` con la fecha del primer envío. |
| H3-TA11 | Intentar cambiar directamente `detalle_pedido.estado`. | PostgreSQL rechaza la operación por ausencia de privilegio, aunque el actor sea `MOZO`. |
| H3-TA12 | Doble envío simultáneo o repetido. | No duplica transición ni historial; sin detalles abiertos devuelve resultado sin cambios. |
| H3-TA13 | Agregar productos a pedido previamente enviado. | Se usa la misma cabecera y los nuevos detalles nacen `ABIERTO`; no se envían automáticamente. |
| H3-TA14 | Enviar agregados posteriores con la cabecera en cada estado vigente posterior a `ABIERTO`. | Solo los nuevos detalles `ABIERTO` pasan a `ENVIADO`; los detalles anteriores no cambian, la cabecera no retrocede ni se sobrescribe y `pedido.enviado_en` conserva exactamente la fecha del primer envío. |
| H3-TA15 | Usar producto/categoría inactivos o de otro local. | La función rechaza el alta sin crear filas ni filtrar información. |
| H3-TA16 | Liberar una mesa con pedido vacío. | Solo un `MOZO` del mismo local puede transformar atómicamente pedido `ABIERTO` sin detalles a `ANULADO`, registrar historial y devolver mesa `OCUPADA → LIBRE`; detalles existentes, otros estados, doble llamada o error no producen transición parcial. |

## 2. Pruebas técnicas manuales

Estas verificaciones se ejecutan contra PostgreSQL/Supabase y se documentan con consultas, respuesta API o matriz de privilegios.

| ID | Verificación | Evidencia esperada |
|---|---|---|
| H3-TM01 | Restricción única de pedido vigente por mesa. | Se rechaza una segunda cabecera en cualquiera de los seis estados vigentes. |
| H3-TM02 | Clasificación de estados. | `PAGADO` y `ANULADO` permiten un nuevo ciclo; `PENDIENTE_PAGO` solo existe en mesa. |
| H3-TM03 | Privilegios de alta de detalle. | `authenticated` no tiene `INSERT`; solo puede ejecutar `agregar_detalle_pedido`. |
| H3-TM04 | Precio y estado controlados por servidor. | Traza SQL demuestra lectura de `producto.precio` e inserción explícita `ABIERTO`. |
| H3-TM05 | Privilegios por columna y RLS. | Solo `cantidad` y `observacion` son actualizables y solo en filas `ABIERTO`; DELETE tiene la misma restricción. |
| H3-TM06 | Atomicidad del envío. | Un error inducido revierte cabecera, detalles e historial; sin transición parcial. |
| H3-TM07 | Seguridad de funciones y aislamiento. | Propietario, `SECURITY DEFINER`, search path, grants y RLS impiden acceso `anon`, otros roles y otros locales. |
| H3-TM08 | Seguridad y atomicidad de liberación de mesa vacía. | La función autorizada es la única que cambia ambos estados, rechaza cualquier detalle, soporta concurrencia y revierte pedido, historial y mesa ante error inducido. |

## 3. Pruebas humanas funcionales y visuales

Estas pruebas validan experiencia táctil, claridad visual y comportamiento responsive; no sustituyen las pruebas de seguridad.

| ID | Escenario | Resultado esperado |
|---|---|---|
| H3-TH01 | Cards de mesa en celular y tablet. | Estados distinguibles por texto y estilo, total legible y objetivos táctiles de al menos 44 px. |
| H3-TH02 | Filtrar y ordenar mesas. | Filtro por estado y orden ascendente/descendente funcionan sin desbordamiento horizontal. |
| H3-TH03 | Volver a una mesa tras recargar o cerrar sesión. | Se presenta el pedido persistido y sus detalles, no un carrito vacío. |
| H3-TH04 | Explorar la carta mediante cards. | Productos agrupados/filtrables por categoría y selección táctil con escritura mínima. |
| H3-TH05 | Responsive de carta y revisión. | Celular y tablet mantienen controles visibles en ambas orientaciones. |
| H3-TH06 | Usar observaciones frecuentes y libres. | Ambas opciones son comprensibles y el texto confirmado reaparece al recuperar el pedido. |
| H3-TH07 | Revisar y enviar. | La UI distingue “por enviar” de “ya solicitado”, muestra total y exige acción explícita. |
| H3-TH08 | Agregar y enviar productos posteriormente. | Se conservan los ya solicitados; los nuevos aparecen abiertos hasta el nuevo envío. |
| H3-TH09 | Liberar mesa ocupada por pedido vacío. | La acción solo aparece en pedido `ABIERTO` vacío, confirma la mesa, evita doble tap, muestra `Liberando…` y vuelve al tablero con la mesa `LIBRE`. |

## 4. Evidencia, aprobación y aceptación

Cada ejecución registra ID, resultado, ambiente y evidencia sin credenciales. Las pruebas visuales anotan dispositivo, navegador, viewport y orientación. La construcción no comienza hasta la aprobación humana explícita de los cuatro documentos del Spec. Esa aprobación no equivale a aceptación de H3. `acceptance.md` no se crea todavía: corresponde después de construcción, ejecución satisfactoria de pruebas humanas y aprobación explícita.
