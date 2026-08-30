# MikuyApp — H5 Entrega, caja, cobro e impresión: requisitos

## Estado y objetivo

H5 completa el flujo `LISTO → ENTREGADO → PAGADO` y deja la mesa en `LIBRE`, con precuenta antes del pago y ticket interno después. Antes del pago, una entrega puede reabrirse al agregar nuevos productos y recorrer nuevamente el flujo operativo.

El baseline vigente es H4: el trabajo se procesa por `detalle_pedido`, puede haber estados mixtos y PostgreSQL es la autoridad.

## Requisitos funcionales

| ID | Requisito | Prioridad |
|---|---|---|
| H5-R01 | El `MOZO` visualiza pedidos del mismo local cuyo trabajo esté completamente `LISTO`, identificando mesa y número de pedido. | Must |
| H5-R02 | El `MOZO` puede solicitar la entrega de un pedido solo cuando exista al menos un detalle y todos los detalles del pedido estén `LISTO`; la operación cambia la cabecera `LISTO → ENTREGADO` y la mesa a `PENDIENTE_PAGO` atómicamente. | Must |
| H5-R03 | La entrega bloquea el pedido y valida identidad, rol, local, estado y snapshot obsoleto; doble clic, repetición y dos sesiones producen como máximo una transición e historial. | Must |
| H5-R04 | Al entregar no se crean estados nuevos de detalle: los detalles conservan `LISTO`. `ENTREGADO` no es terminal: mientras no exista pago, el `MOZO` del mismo local puede agregar un producto; el nuevo detalle nace `ABIERTO`, los anteriores permanecen `LISTO`, pedido y mesa vuelven al flujo operativo derivado y el nuevo detalle sigue cocina hasta permitir una nueva entrega. `PAGADO` y `ANULADO` bloquean toda modificación posterior. | Must |
| H5-R05 | `CAJA` visualiza mesas/pedidos `PENDIENTE_PAGO`, selecciona un pedido y consulta mesa, número, líneas, cantidades, precios unitarios históricos, importes y total autoritativo. | Must |
| H5-R06 | `CAJA` puede abrir la precuenta antes del pago y el ticket interno después del pago. Ambos son documentos internos; ninguno es comprobante fiscal. | Must |
| H5-R07 | El MVP registra únicamente `EFECTIVO`, `YAPE`, `PLIN` o `TARJETA`, sin integración externa, pago mixto, división, propina, descuento o validación bancaria. | Must |
| H5-R08 | El cobro se ejecuta mediante una función PostgreSQL transaccional que valida usuario, rol `CAJA`, local y estado `ENTREGADO`; bloquea pedido/mesa, calcula el total desde `detalle_pedido`, inserta exactamente un pago, cambia a `PAGADO`, registra historial y libera la mesa. | Must |
| H5-R09 | Existe defensa de un único pago por pedido mediante `UNIQUE(pedido_id)` y lógica de bloqueo/validación; dos cobros concurrentes no pueden confirmar ambos. | Must |
| H5-R10 | El importe final nunca proviene del frontend ni de la carta actual: es `sum(cantidad * precio_unitario)` sobre detalles persistidos, usando precios copiados al momento del pedido. | Must |
| H5-R11 | La impresión usa `window.print()`, vista imprimible y CSS para papel térmico de 80 mm; oculta navegación y acciones innecesarias. No hay ESC/POS, impresión silenciosa ni servidor de impresión. | Must |
| H5-R12 | Se reutilizan Realtime de `detalle_pedido`, `pedido` y `mesa` para reflejar `PEDIDO_LISTO`, `PENDIENTE_PAGO` y `LIBRE`; `pago` no se publica. | Must |

## Seguridad y roles

`MOZO` puede leer mesas/pedidos/detalles de su local, agregar nuevos productos a pedidos aún no pagados —incluido `ENTREGADO`— y ejecutar únicamente entrega. `CAJA` puede leer mesas/pedidos/detalles entregados o pagados de su local necesarios para consumo, precuenta y ticket, y ejecutar únicamente cobro. `COCINA` conserva lectura/transición de cocina y no puede entregar, cobrar, leer pagos operativamente ni modificar pedidos. `ADMINISTRADOR` conserva su acceso administrativo de H2, pero no ejecuta las operaciones operativas H5 de entrega ni cobro. `anon` no ejecuta funciones ni lee datos transaccionales.

Toda mutación se protege con privilegios, RLS y funciones `SECURITY DEFINER` con identidad/contexto derivados de `auth.uid()`, `search_path` fijo y `EXECUTE` restringido. El frontend solo mejora la experiencia.

## Estados y terminalidad

La secuencia base es `ABIERTO → ENVIADO → RECIBIDO_COCINA → EN_PREPARACION → LISTO → ENTREGADO → PAGADO`. Solo `PAGADO` y `ANULADO` son terminales. La precondición de entrega es que exista al menos un detalle y todos estén `LISTO`; la precondición de cobro es `ENTREGADO` y ausencia de pago. `ENTREGADO` mantiene detalles `LISTO` y mesa `PENDIENTE_PAGO`, pero un nuevo producto crea un detalle `ABIERTO`, conserva los anteriores `LISTO`, devuelve la cabecera al estado operativo derivado y la mesa a `OCUPADA`. El detalle nuevo recorre cocina normalmente; cuando todos vuelven a `LISTO`, una nueva entrega devuelve pedido a `ENTREGADO` y mesa a `PENDIENTE_PAGO`. Después de `PAGADO` no se admite alta, modificación, retiro, envío, cocina ni nueva entrega. Reintentos se rechazan como estado obsoleto o ya procesado, sin historial duplicado.

## Fuera de alcance y pendientes

Fuera: SUNAT, boleta/factura, integraciones Yape/Plin/tarjeta, caja abierta/cerrada, movimientos de efectivo, descuentos, propinas, división, reportes/exportaciones/respaldo e infraestructura nueva.

Durante la construcción se verificó el estado real de la base/repositorio y se aplicó únicamente el ajuste técnico mínimo necesario para cumplir los contratos ya definidos: `UNIQUE(pago.pedido_id)`, pago único, aislamiento por local y RLS/privilegios. Esta verificación no representa una decisión funcional pendiente. La reapertura aprobada durante TH01 fue implementada, verificada y aceptada como parte del cierre de H5.

## Trazabilidad

El diseño desarrolla H5-D01–D12; las tareas H5-T01–T10 y las pruebas H5-TA/H5-TH mantienen la relación requisito → diseño → ejecución.
