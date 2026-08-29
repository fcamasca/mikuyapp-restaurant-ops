# MikuyApp — H5 Entrega, caja, cobro e impresión: plan de pruebas

Este plan separa pruebas automatizadas/SQL-técnicas de pruebas humanas. H5 no está implementado; los casos son criterios de ejecución futura.

## Pruebas automatizadas y SQL/técnicas

| ID | Caso | Resultado esperado | Req./tarea |
|---|---|---|---|
| H5-TA01 | Pedido con al menos un detalle y todos sus detalles `LISTO`. | Se ofrece entrega; cabecera `ENTREGADO`, mesa `PENDIENTE_PAGO`, detalles siguen `LISTO`. | R01-R04/T02 |
| H5-TA02 | Un detalle `EN_PREPARACION`, `ABIERTO` o agregado no listo. | Entrega rechazada, cero cambios e historial. | R02/T02 |
| H5-TA03 | Doble entrega secuencial, doble clic, snapshot obsoleto y dos sesiones. | Como máximo una transición `LISTO→ENTREGADO`; segundo intento falla sin duplicado. | R03/T02 |
| H5-TA04 | Leer mesas/pedidos pendientes como `CAJA`; intentar entrega/cobro como `MOZO`, `COCINA`, `ADMINISTRADOR` y anon. | `CAJA` solo cobra y `MOZO` solo entrega; cocina, administrador y demás roles no ejecutan operaciones H5 no autorizadas. | R05,R08/T02-T04 |
| H5-TA05 | Usuario válido de otro local y rol no autorizado. | Sin filas transaccionales y sin ejecución de funciones. | R03,R08/T01,T03 |
| H5-TA06 | Consumo con varias líneas/cantidades, producto inactivo y cambio posterior de precio/nombre. | Producto inactivo sigue siendo visible/resoluble; `precio_unitario` histórico y total son correctos; el nombre se obtiene de `producto.nombre` vigente y no se afirma snapshot histórico. | R05,R10/T03 |
| H5-TA07 | Cada medio `EFECTIVO`, `YAPE`, `PLIN`, `TARJETA`. | Un cobro válido por medio; medio persistido exactamente. | R07/T04 |
| H5-TA08 | Cobro correcto de `ENTREGADO`. | Exactamente un `pago`, importe autoritativo, `PAGADO`, historial y mesa `LIBRE` en una transacción. | R08-R10/T04 |
| H5-TA09 | Cobro de `LISTO`, `PAGADO`, `ANULADO`, pedido inexistente o medio inválido. | Rechazo sin cambios ni pago. | R08/T04 |
| H5-TA10 | Doble cobro secuencial. | Segundo intento falla; `count(pago)=1`. | R09/T04 |
| H5-TA11 | Dos cobros concurrentes sobre el mismo pedido. | Un commit, un pago, un historial `ENTREGADO→PAGADO`; otra sesión falla tras lock/conflicto. | R03,R09/T04,T08 |
| H5-TA12 | Error inducido después de insertar pago o antes de liberar mesa. | Rollback completo: sin pago, pedido sigue `ENTREGADO`, mesa `PENDIENTE_PAGO`, sin historial parcial. | R08/T04,T08 |
| H5-TA13 | Intentar agregar/modificar/retirar/enviar después de `ENTREGADO` y `PAGADO`; cocina intenta cobrar/entregar. | Todo prohibido; no se modifica precio, detalle, estado ni mesa. | R04/T02,T08 |
| H5-TA14 | Ver precuenta antes de pago y ticket antes/después, con locale/zona horaria definidos. | Precuenta sí para `ENTREGADO`; ticket solo para `PAGADO`; campos, `local.nombre`, `es-PE` y `America/Lima` coinciden. | R06/T05 |
| H5-TA15 | Publicación y RLS Realtime. | Solo `detalle_pedido`, `pedido`, `mesa`; señales actualizan mozo/caja sin refresh y resync maneja reconexión/duplicados. | R12/T06 |
| H5-TA16 | Inspección de impresión. | CSS oculta navegación/acciones y produce ancho razonable de 80 mm; documento sigue visible si impresora falla. | R11/T07 |
| H5-TA17 | Suite regresiva H1–H4. | Auth, roles, catálogos, mesa, creación/envío, estados mixtos, cocina, Realtime y liberación de pedido vacío siguen pasando. | R01-R12/T09 |

## Pruebas humanas finales

| ID | Escenario | Evidencia |
|---|---|---|
| H5-TH01 | Mozo observa un pedido completamente listo, entrega desde celular y confirma mesa pendiente de pago. | Capturas/registro de estados y número de pedido. |
| H5-TH02 | Mozo intenta entregar con una línea no lista y luego reintenta con estado actualizado. | Mensaje comprensible, sin falso éxito. |
| H5-TH03 | Dos dispositivos intentan entregar/cobrar el mismo pedido. | Una sola transición/pago; segundo dispositivo muestra conflicto o estado ya procesado. |
| H5-TH04 | Caja en PC consulta mesas pendientes, abre consumo, verifica total y estado `ENTREGADO`. | Flujo usable sin navegación insegura. |
| H5-TH05 | Caja abre precuenta, cobra probando los cuatro medios en pedidos de prueba y abre ticket interno. | Documentos con todos los campos y medio correcto. |
| H5-TH06 | Imprimir/vista previa en 80 mm desde navegador. | Ancho, legibilidad, ausencia de menú/acciones y corte razonable. |
| H5-TH07 | Caja en tablet y PC; mozo ve `PENDIENTE_PAGO` y luego `LIBRE` sin refresh. | Video/capturas de Realtime y responsive. |
| H5-TH08 | Usuario de otro rol/local intenta entrar, leer y operar caja/entrega. | Acceso denegado y datos aislados. |
| H5-TH09 | Ejecutar regresión manual H1–H4 y flujo completo cocina→entrega→cobro. | Checklist firmado por revisor humano. |

## Datos y controles

Usar al menos dos locales, usuarios de cada rol, pedido con múltiples detalles y estados mixtos, producto desactivado después de pedido, cantidades mayores que uno, cambio posterior de precio y nombre, los cuatro medios y fallos inducidos en transacción. Verificar que el producto inactivo siga resolviendo por `producto.nombre`, que solo `precio_unitario` sea histórico, además de conteos, historial, actor, timestamps, estados de mesa, aislamiento y ausencia de filas parciales directamente en PostgreSQL.

## Trazabilidad de cobertura

H5-R01–R04: TA01–TA03, TH01–TH03. H5-R05–R07: TA04–TA07, TA14, TH04–TH05. H5-R08–R10: TA08–TA13, TH03/TH05. H5-R11: TA16, TH06. H5-R12: TA15, TH07. Seguridad, aislamiento y regresión: TA04–TA05, TA17, TH08–TH09.
