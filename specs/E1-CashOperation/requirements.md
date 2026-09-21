# MikuyApp — Evolución 1 — Operación de caja: requisitos

## 1. Estado, objetivo y fuente de verdad

El Spec Mode de **Evolución 1 — Operación de caja** está aprobado y la construcción se encuentra en validación humana. T03–T13 completaron su validación técnica previa y TP62 permanece abierto. Durante esa validación se aprobó incorporar notificaciones internas a los `ADMINISTRADOR` del mismo local por apertura y cierre de caja; este delta queda especificado, pero todavía no está construido ni validado. T14 permanece en validación humana y E1 todavía no está aceptada. La referencia histórica del plan es **30–40 horas**; no representa tiempo consumido.

`main`/`origin/main` en `f76c190`, verificado entonces sin cambios locales, se conserva como baseline histórica del inicio del Spec Mode y no describe el estado actual del árbol de trabajo. El MVP v1.0.0 y PM-001 están aceptados. PM-002 permanece `TRANSITIONING`; esta evolución no lo modifica y la construcción debe respetar su matriz de ambientes.

El objetivo es ampliar la estación de Caja para controlar turnos, efectivo, descuentos, anulaciones, pagos divididos, propinas y auditoría, preservando PostgreSQL como autoridad financiera y sin convertir MikuyApp en un sistema contable o fiscal. La impresión de comandas pertenece a Evolución 7 y queda fuera de este spec.

## 2. Baseline verificable y brechas

| Área | Estado actual verificable | Brecha de Evolución 1 |
|---|---|---|
| Caja | Ruta `/caja` exclusiva de `CAJA`; lista pedidos `ENTREGADO`/mesa `PENDIENTE_PAGO`. | No existe caja física ni sesión/turno, apertura, cierre o arqueo. |
| Pago | `pago(pedido_id, importe, medio, usuario_id, pagado_en)`; `UNIQUE(pedido_id)`; medios `EFECTIVO`, `YAPE`, `PLIN`, `TARJETA`. | Sólo admite un pago total por pedido; no relaciona sesión, propina ni división. |
| Cobro | RPC `registrar_pago_pedido` valida contexto `CAJA`, bloquea pedido/mesa, calcula detalles, inserta un pago, marca `PAGADO` y libera mesa atómicamente. | Debe evolucionar sin aceptar importes autoritativos del frontend y sin perder protección contra doble cobro. |
| Pedido/entrega | `PAGADO` y `ANULADO` son terminales. `ENTREGADO` puede reabrirse sólo antes del pago. | No hay descuentos ni anulación supervisada; la división requiere definir cuándo se alcanza el pago completo. |
| Auditoría | `historial_estado` registra sólo transiciones de estado de `pedido`. | No representa aperturas, arqueos, movimientos, autorizaciones ni valores financieros anteriores/nuevos. |
| Notificaciones | No existe infraestructura persistente reutilizable para avisos internos ni lectura individual por administrador. | Apertura/cierre requieren entrega local, contador no leído y estado de lectura persistente sin convertirse en un sistema genérico. |
| Reportes | Resumen diario por medio desde `pago`; ventas pagadas para CSV; fecha Lima. | No muestra sesiones, efectivo esperado, diferencias, movimientos, descuentos, anulaciones, propinas o pagos parciales. |
| Realtime | Señales `INSERT`/`UPDATE` de `detalle_pedido`, `pedido`, `mesa`; resync autoritativo; `pago` no publicado. | Caja necesitará refrescar sesión/movimientos sin convertir eventos Realtime en autoridad. |
| Seguridad | Contexto autenticado, mínimo privilegio, RLS, RPC `SECURITY DEFINER`, `search_path` fijo. | Nuevas operaciones y lecturas requieren autorización por rol/local y pruebas negativas. |

## 3. Requisitos funcionales

| ID | Requisito | Prioridad |
|---|---|---|
| E1-R01 | La solución distinguirá una **caja física** de una **sesión de caja**. La sesión pertenece operativamente a la caja física, no al usuario que la abre. Para el alcance de un solo local se habilitará al menos una caja identificable y cada apertura originará una sesión inmutable vinculada a local y caja, con `abierta_por` como trazabilidad del actor de apertura. | Must |
| E1-R02 | Un usuario `CAJA` podrá abrir una sesión registrando monto inicial no negativo. Fecha/hora, `abierta_por` y local procederán del servidor. Existirá como máximo una sesión `ABIERTA` por caja física. Si ya existe, no se creará otra: cualquier usuario `CAJA` activo del mismo local podrá recuperar y continuar operando esa sesión sin cierre ni arqueo. | Must |
| E1-R03 | Una sesión tendrá estado `ABIERTA` o `CERRADA`. El cambio de cajero no exigirá cierre ni arqueo. No se editarán apertura, `abierta_por` ni monto inicial; cada cobro y sus medios, entrada, salida y cierre registrarán su actor real, y el cierre conservará `cerrada_por` además de `abierta_por`. | Must |
| E1-R04 | Cualquier usuario `CAJA` activo del mismo local podrá registrar **entradas manuales** y, explícitamente, **salidas de caja** sobre la sesión abierta de la caja, con tipo, importe positivo, motivo no vacío, actor y hora servidor. Se rechazarán importes cero/negativos, sesión cerrada, otra caja/local y edición o borrado posterior. | Must |
| E1-R05 | El efectivo esperado será calculado en PostgreSQL como monto inicial + cobros en efectivo + propinas en efectivo + entradas − salidas, considerando exclusivamente operaciones confirmadas de la sesión. El frontend no enviará ni decidirá el saldo. | Must |
| E1-R06 | Cualquier usuario `CAJA` activo del mismo local podrá cerrar la sesión abierta de la caja ingresando el efectivo contado, aunque otro cajero la haya abierto. PostgreSQL devolverá/resguardará resumen por medio, entradas, salidas, esperado, contado y diferencia. El cierre será atómico y conservará `abierta_por`, `cerrada_por` y sus fechas servidor. | Must |
| E1-R07 | El cierre se bloqueará si existe una operación de cobro/movimiento en curso sobre la sesión o si la sesión ya cerró. Se permite cerrar con pedidos `ENTREGADO` pendientes. Se permite diferencia de cierre y, cuando sea distinta de cero, el motivo será obligatorio. | Must |
| E1-R08 | `CAJA` y `ADMINISTRADOR` podrán consultar el historial de sesiones de su local. `CAJA` verá lo necesario para operar y revisar sus cierres; `ADMINISTRADOR` tendrá vista supervisora. No se confiará en un `local_id` del cliente. | Must |
| E1-R09 | El descuento se aplicará al **total del pedido**, no a líneas, como importe o porcentaje mutuamente exclusivo. `CAJA` lo solicitará con motivo y `ADMINISTRADOR` lo autorizará; sólo podrá aplicarse a un pedido `ENTREGADO` y antes del primer pago. Su base, valor y resultado neto quedarán como snapshot. No existirá un límite porcentual arbitrario: todo descuento requerirá autorización de `ADMINISTRADOR`. | Must |
| E1-R10 | `descuento_pedido` será el snapshot autoritativo del descuento. `pedido` no duplicará `subtotal_snapshot`, `descuento_snapshot` ni `total_neto_snapshot`. Una función autoritativa PostgreSQL resolverá el subtotal, descuento y total neto aplicable al cobro. El descuento no podrá volver negativo el total ni cambiar después del primer pago confirmado; los reintentos no crearán descuentos/autorizaciones duplicados. | Must |
| E1-R11 | `ADMINISTRADOR` ejecutará directamente la anulación con motivo obligatorio; no existirá solicitante ni autorizador separados para esta operación. Sin pagos confirmados, serán anulables `ABIERTO`, `ENVIADO`, `RECIBIDO_COCINA`, `EN_PREPARACION`, `LISTO` y `ENTREGADO`; `PAGADO` y `ANULADO` no serán anulables. La función bloqueará pedido/mesa y registrará actor administrador, fecha/hora servidor y estado anterior/nuevo. Para `EN_PREPARACION`, `LISTO` y `ENTREGADO`, la futura UI mostrará una advertencia operativa previa que no modifica la autorización PostgreSQL. | Must |
| E1-R12 | Si existe cualquier pago confirmado, incluso parcial, la anulación se bloqueará. La anulación completa del pedido por `ADMINISTRADOR` es distinta de la cancelación individual de productos por `MOZO` prevista para Evolución 7. No se implementarán reversos ni devoluciones como parte de esta regla. | Must |
| E1-R13 | La solución distinguirá un **acto de cobro** de los **medios de pago que lo componen**. Un cobro aplicará un importe total a un único `pedido` y contendrá N líneas monetarias con medios distintos o repetidos; son válidos, entre otros, `EFECTIVO + YAPE`, `YAPE + YAPE` y combinaciones de tres o más medios. Un cobro normal cubrirá todo el saldo, se confirmará una sola vez, será atómico y producirá un único documento interno que detalle sus medios. La selección de productos continuará siendo sólo ayuda de cálculo, sin subpedidos, `pago_detalle` ni asignación histórica por líneas. | Must |
| E1-R14 | `Cobrar una parte` será un acto de cobro explícitamente distinto cuyo total será mayor que cero y menor que el saldo vigente. Cada acto parcial podrá contener uno o varios medios si todos sus importes son positivos y suman exactamente el total del cobro. El pedido conservará `ENTREGADO` y la mesa seguirá pendiente mientras exista saldo; sólo un cobro que deje saldo exactamente cero cambiará el pedido a `PAGADO` y liberará la mesa. Dos cobros parciales separados producirán dos documentos internos separados. | Must |
| E1-R15 | Cada cobro tendrá sesión abierta, pedido, actor real, hora servidor e idempotencia a nivel de cobro. PostgreSQL bloqueará `sesion_caja → pedido → mesa`, recalculará el saldo y registrará en una sola transacción su cabecera lógica, todas las líneas de medio, auditoría y transición/documento lógico aplicable; ante cualquier error no persistirá ninguna línea. Un reintento devolverá el mismo cobro completo sin duplicar cabecera, pagos, auditoría, historial ni documento. | Must |
| E1-R16 | Antes del primer cobro confirmado se mantiene la reapertura H5 de `ENTREGADO`; después del primer acto parcial no se podrá agregar, editar, retirar, reenviar ni volver a entregar detalles. La UX mostrará que la cuenta está parcialmente pagada. | Must |
| E1-R17 | La propina será opcional y no negativa, permanecerá separada del importe aplicado a la venta y se asociará al medio que la recauda dentro del cobro. No alterará el total autoritativo del pedido; sólo las líneas `EFECTIVO` —importe de venta y propina— afectarán el efectivo esperado. | Must |
| E1-R18 | Cada acto de cobro producirá un único documento interno. Un cobro parcial producirá su propio recibo; el cobro que complete el saldo producirá un ticket consolidado del pedido y detallará todas las líneas de medio del acto final y los cobros previos. Los documentos separarán venta y propina, no serán comprobantes fiscales ni definirán tratamiento tributario. | Must |
| E1-R19 | Una auditoría específica permitirá reconstruir apertura, movimientos, descuentos, autorización, anulación, cobros y sus medios, cierre y valores relevantes anteriores/nuevos, con local, sesión, pedido/cobro cuando aplique, actor, autorizador sólo cuando corresponda y hora servidor. Un cobro con N medios constituirá un único evento lógico de auditoría con detalle complementario de sus líneas. Para anulación registrará únicamente al `ADMINISTRADOR` que la ejecutó. No se forzará esta semántica dentro de `historial_estado`. | Must |
| E1-R20 | Los registros financieros y de auditoría no admitirán `UPDATE`/`DELETE` desde cliente. Correcciones futuras deberán ser eventos compensatorios explícitos. Se conservarán FKs `ON DELETE RESTRICT` y trazabilidad histórica. | Must |
| E1-R21 | Los reportes mínimos mostrarán por sesión: apertura/cierre, totales por medio, efectivo esperado, contado/diferencia, entradas, salidas, descuentos, anulaciones, propinas, cobros y parciales, sin duplicar la venta por agrupar varios medios y sin convertirse en libro contable ni conciliación bancaria. | Must |
| E1-R22 | La estación PC de Caja mostrará permanentemente estado de caja, quién abrió, monto inicial y esperado, sin presentar la sesión como exclusiva de esa persona; priorizará cobro rápido. El cobro normal preparará el saldo completo, permitirá agregar N líneas de medio y sólo habilitará una confirmación única cuando su suma coincida exactamente. `Cobrar una parte` será una acción secundaria diferenciada. Todo cobro mostrará antes de ejecutar pedido/mesa, total, medios, propina, saldo posterior y liberación de mesa cuando corresponda; un resync invalidará una confirmación obsoleta. Apertura, cierre, salidas, descuento y anulación mantendrán confirmación clara y estados de carga/error/reintento. | Must |
| E1-R23 | Cada apertura y cada cierre de caja generarán exactamente una notificación interna para cada `ADMINISTRADOR` activo del mismo local en el momento del evento. La apertura informará caja, actor, fecha/hora y monto inicial. El cierre informará caja, actor, fecha/hora, efectivo esperado, contado y diferencia; si la diferencia es distinta de cero incluirá el motivo y tendrá prioridad visual de alerta. Cada destinatario conservará su estado leído/no leído entre sesiones y podrá marcar la notificación como leída. No habrá acceso cruzado entre locales ni flujo de aprobación: una diferencia continúa permitida con motivo obligatorio y sólo modifica la prioridad visual de la notificación. | Must |

## 4. Seguridad, roles e invariantes

- `CAJA`: cualquier usuario activo del local puede continuar la sesión abierta de una caja del mismo local, registrar entradas/salidas, cobrar y cerrar; cada operación conserva su actor. También solicita/aplica únicamente descuentos ya autorizados y consulta operación de caja de su local.
- `ADMINISTRADOR`: autoriza descuentos, ejecuta directamente anulaciones, consulta sesiones/reportes y las notificaciones de apertura/cierre destinadas a él dentro de su local, y puede ejecutar cierre supervisor con motivo y auditoría. Puede marcar sus notificaciones como leídas. No hereda cobro operativo por defecto.
- `MOZO`: conserva pedido/entrega y no cobra, mueve efectivo ni autoriza.
- `COCINA`: conserva transiciones de cocina y no accede a datos financieros.
- No se crea un rol `SUPERVISOR`: `ADMINISTRADOR` cubre la capacidad aprobada de cierre supervisor con motivo y auditoría.
- `anon` no lee ni ejecuta operación financiera; `authenticated` sólo ejecuta RPC que revalidan `auth.uid()`, perfil/rol/local activos y pertenencia.
- Apertura, movimiento, descuento, anulación, cobro parcial/final y cierre serán transacciones PostgreSQL con orden de bloqueos documentado.
- Montos, saldos, autorización, timestamps y pertenencia nunca se aceptarán como autoridad desde React.

## 5. Decisiones

### Cerradas por evidencia del repositorio

| ID | Decisión |
|---|---|
| EC-01 | Mantener un solo local y los cuatro roles actuales; no crear rol nuevo. |
| EC-02 | Mantener `PAGADO` y `ANULADO` terminales y la reapertura H5 sólo antes de cualquier pago. |
| EC-03 | Mantener `EFECTIVO`, `YAPE`, `PLIN`, `TARJETA`, moneda/locale `es-PE` y fecha operativa `America/Lima`. |
| EC-04 | PostgreSQL/RPC es autoridad; Realtime sólo dispara resync; `pago` no necesita publicarse. |
| EC-05 | `historial_estado` sólo sirve para estados de pedido y no cubre auditoría financiera. |
| EC-06 | La sesión pertenece a la caja física; `abierta_por` no la hace exclusiva. Otro `CAJA` activo del mismo local puede operar y cerrar, con actor propio por operación. |
| EC-07 | `ADMINISTRADOR` anula directamente con motivo; cualquier pago confirmado bloquea la anulación. |
| EC-08 | Un pedido admite N actos de cobro; cada cobro admite N medios distintos o repetidos y sólo llega a `PAGADO` cuando un acto deja el saldo exactamente en cero. |

### Propuestas técnicas del spec

| ID | Propuesta |
|---|---|
| PT-01 | Introducir caja física, sesión, movimientos inmutables y auditoría específica. |
| PT-02 | Implementar la división como múltiples actos de cobro sobre un pedido; cada acto agrupa sus N medios, sin subpedidos ni asignación por productos. |
| PT-03 | Modelar propina separada del importe de venta dentro del evento de pago. |
| PT-04 | Aplicar antes del primer pago el snapshot de descuento asociado al pedido, persistido exclusivamente en `descuento_pedido`. |
| PT-05 | Persistir una notificación mínima por evento `APERTURA`/`CIERRE` y una fila destinataria por `ADMINISTRADOR` activo del mismo local, reutilizando `auditoria_caja` y los snapshots de sesión como fuente de contenido financiero. |

### Decisión técnica aprobada

| ID | Decisión | Comportamiento cerrado |
|---|---|---|
| DT-01 | Fuente autoritativa del descuento. | `descuento_pedido` conserva el snapshot; `pedido` no duplica subtotal, descuento ni total neto; una función PostgreSQL obtiene los tres importes aplicables al cobro. |
| DT-02 | Identidad persistente del acto de cobro. | Crear una cabecera mínima `cobro` y asociar mediante `pago.cobro_id` las N filas de medio. La cabecera concentra pedido, sesión, actor, hora, total aplicado, saldo anterior/posterior e idempotencia; `pago` conserva medio, importe y propina. Pagos legacy permanecen identificables sin fabricar cabeceras. |
| DT-03 | Persistencia específica de notificaciones de caja. | Crear `notificacion_caja` como referencia inmutable y única al evento de `auditoria_caja`, y `notificacion_caja_destinatario` como relación única por administrador con `leida_en`. No se duplican importes ni reglas financieras: las lecturas componen el contenido desde auditoría, sesión, caja y snapshots de cierre. |

### Decisiones funcionales aprobadas

| ID | Decisión aprobada | Comportamiento cerrado |
|---|---|---|
| DF-01 | Cierre con pedidos pendientes. | Se permite; los pedidos pertenecen a la sesión que finalmente los cobra, no a aquella en que se crearon. |
| DF-02 | Diferencia de cierre. | Se permite; motivo obligatorio cuando diferencia ≠ 0 y visibilidad para `ADMINISTRADOR`. |
| DF-03 | Solicitud, autorización y momento del descuento. | `CAJA` solicita; `ADMINISTRADOR` autoriza; sólo en `ENTREGADO` y antes del primer pago. |
| DF-04 | Límite comercial del descuento. | No se fija porcentaje arbitrario; todo descuento requiere autorización de `ADMINISTRADOR`. |
| DF-06 | Documentos por acto de cobro. | Un documento interno por cobro: recibo para cada acto parcial y ticket consolidado cuando el acto completa el saldo; un cobro con N medios se confirma y documenta una sola vez, detallando sus líneas. |
| DF-07 | Cierre supervisor. | `ADMINISTRADOR` puede ejecutarlo con motivo y auditoría. |
| DF-08 | Caja física operativa en E1. | `/caja` usa automáticamente la única caja activa/configurada del local. No muestra selector ni elige arbitrariamente si existen varias; la selección explícita por el usuario `CAJA` se difiere a una evolución posterior. El modelo conserva soporte backend para múltiples cajas. |
| DF-09 | División mediante selección de productos. | La selección sólo ayuda a calcular; se persiste importe, no asignación histórica por líneas. |
| DF-10 | Notificaciones administrativas de apertura y cierre. | Toda apertura/cierre notifica una vez a cada `ADMINISTRADOR` activo del mismo local. Apertura y cierre sin diferencia son informativos; cierre con diferencia se destaca como alerta e incluye el motivo. La notificación no solicita ni registra aprobación. |

No quedan decisiones funcionales ni técnicas abiertas para construir los ajustes aprobados durante TP62. EC-06, EC-07 y EC-08 permanecen cerradas; DT-02 y DT-03 definen las representaciones mínimas elegidas. La construcción y revalidación del delta de notificaciones aún no se han ejecutado.

## 6. Fuera de alcance

Inventario, recetas, compras/proveedores, SUNAT, Yape/Plin directo, pasarela bancaria, multiempresa/multilocal, usuarios multirol/multilocal, cancelación de productos por mozo, métricas NoSQL, replicación DEV/PROD, cambios de PM-002, contabilidad, conciliación bancaria completa, recepción de cocina completa, impresión de comandas y funcionalidades de otras evoluciones. La impresión opcional como apoyo al flujo digital de cocina se definirá en el Spec Mode de Evolución 7.

## 7. Criterios de salida de construcción futura

Requisitos y decisiones sensibles aprobados; migraciones aditivas/reversibles revisadas; RPC/RLS/grants y concurrencia aprobados; regresión H1–H6/PM-001 sin fallos; pruebas humanas de Caja ejecutadas; documentación actualizada; cero defectos financieros bloqueantes. La aceptación será un acto posterior y no forma parte de este Spec Mode.

## 8. Trazabilidad resumida

La matriz detallada se mantiene en `test-plan.md`. Agrupación: R01–R08 → D02–D05, T02–T05, TP01–TP18; R09–R12 → D06–D07, T06–T07, TP19–TP30; R13–R18 → D08–D09, T08–T10, TP31–TP48; R19–R20 → D10, T11, TP49–TP55; R21–R22 → D11–D12, T12–T14, TP56–TP64; R23 → D02–D05/D10–D13, T15, TP02/TP06/TP10/TP17–TP18/TP51–TP52/TP55/TP59–TP60/TP62.
