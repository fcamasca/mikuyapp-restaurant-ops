# MikuyApp — Evolución 1 — Operación de caja: requisitos

## 1. Estado, objetivo y fuente de verdad

Este documento inicia el Spec Mode de **Evolución 1 — Operación de caja**. La evolución está **especificada, no construida ni aceptada**. La referencia histórica del plan es **30–40 horas**; no representa autorización de construcción ni tiempo consumido.

El checkout verificado corresponde a `main`/`origin/main` en `f76c190`, sin cambios locales. El MVP v1.0.0 y PM-001 están aceptados. PM-002 permanece `TRANSITIONING`; esta evolución no lo modifica y cualquier construcción futura deberá respetar su matriz de ambientes.

El objetivo es ampliar la estación de Caja para controlar turnos, efectivo, descuentos, anulaciones, pagos divididos, propinas y auditoría, preservando PostgreSQL como autoridad financiera y sin convertir MikuyApp en un sistema contable o fiscal. La impresión de comandas pertenece a Evolución 7 y queda fuera de este spec.

## 2. Baseline verificable y brechas

| Área | Estado actual verificable | Brecha de Evolución 1 |
|---|---|---|
| Caja | Ruta `/caja` exclusiva de `CAJA`; lista pedidos `ENTREGADO`/mesa `PENDIENTE_PAGO`. | No existe caja física ni sesión/turno, apertura, cierre o arqueo. |
| Pago | `pago(pedido_id, importe, medio, usuario_id, pagado_en)`; `UNIQUE(pedido_id)`; medios `EFECTIVO`, `YAPE`, `PLIN`, `TARJETA`. | Sólo admite un pago total por pedido; no relaciona sesión, propina ni división. |
| Cobro | RPC `registrar_pago_pedido` valida contexto `CAJA`, bloquea pedido/mesa, calcula detalles, inserta un pago, marca `PAGADO` y libera mesa atómicamente. | Debe evolucionar sin aceptar importes autoritativos del frontend y sin perder protección contra doble cobro. |
| Pedido/entrega | `PAGADO` y `ANULADO` son terminales. `ENTREGADO` puede reabrirse sólo antes del pago. | No hay descuentos ni anulación supervisada; la división requiere definir cuándo se alcanza el pago completo. |
| Auditoría | `historial_estado` registra sólo transiciones de estado de `pedido`. | No representa aperturas, arqueos, movimientos, autorizaciones ni valores financieros anteriores/nuevos. |
| Reportes | Resumen diario por medio desde `pago`; ventas pagadas para CSV; fecha Lima. | No muestra sesiones, efectivo esperado, diferencias, movimientos, descuentos, anulaciones, propinas o pagos parciales. |
| Realtime | Señales `INSERT`/`UPDATE` de `detalle_pedido`, `pedido`, `mesa`; resync autoritativo; `pago` no publicado. | Caja necesitará refrescar sesión/movimientos sin convertir eventos Realtime en autoridad. |
| Seguridad | Contexto autenticado, mínimo privilegio, RLS, RPC `SECURITY DEFINER`, `search_path` fijo. | Nuevas operaciones y lecturas requieren autorización por rol/local y pruebas negativas. |

## 3. Requisitos funcionales

| ID | Requisito | Prioridad |
|---|---|---|
| E1-R01 | La solución distinguirá una **caja física** de una **sesión de caja**. La sesión pertenece operativamente a la caja física, no al usuario que la abre. Para el alcance de un solo local se habilitará al menos una caja identificable y cada apertura originará una sesión inmutable vinculada a local y caja, con `abierta_por` como trazabilidad del actor de apertura. | Must |
| E1-R02 | Un usuario `CAJA` podrá abrir una sesión registrando monto inicial no negativo. Fecha/hora, `abierta_por` y local procederán del servidor. Existirá como máximo una sesión `ABIERTA` por caja física. Si ya existe, no se creará otra: cualquier usuario `CAJA` activo del mismo local podrá recuperar y continuar operando esa sesión sin cierre ni arqueo. | Must |
| E1-R03 | Una sesión tendrá estado `ABIERTA` o `CERRADA`. El cambio de cajero no exigirá cierre ni arqueo. No se editarán apertura, `abierta_por` ni monto inicial; cada pago, entrada, salida y cierre registrará su propio actor, y el cierre conservará `cerrada_por` además de `abierta_por`. | Must |
| E1-R04 | Cualquier usuario `CAJA` activo del mismo local podrá registrar **entradas manuales** y, explícitamente, **salidas de caja** sobre la sesión abierta de la caja, con tipo, importe positivo, motivo no vacío, actor y hora servidor. Se rechazarán importes cero/negativos, sesión cerrada, otra caja/local y edición o borrado posterior. | Must |
| E1-R05 | El efectivo esperado será calculado en PostgreSQL como monto inicial + cobros en efectivo + propinas en efectivo + entradas − salidas, considerando exclusivamente operaciones confirmadas de la sesión. El frontend no enviará ni decidirá el saldo. | Must |
| E1-R06 | Cualquier usuario `CAJA` activo del mismo local podrá cerrar la sesión abierta de la caja ingresando el efectivo contado, aunque otro cajero la haya abierto. PostgreSQL devolverá/resguardará resumen por medio, entradas, salidas, esperado, contado y diferencia. El cierre será atómico y conservará `abierta_por`, `cerrada_por` y sus fechas servidor. | Must |
| E1-R07 | El cierre se bloqueará si existe una operación de cobro/movimiento en curso sobre la sesión o si la sesión ya cerró. Se permite cerrar con pedidos `ENTREGADO` pendientes. Se permite diferencia de cierre y, cuando sea distinta de cero, el motivo será obligatorio. | Must |
| E1-R08 | `CAJA` y `ADMINISTRADOR` podrán consultar el historial de sesiones de su local. `CAJA` verá lo necesario para operar y revisar sus cierres; `ADMINISTRADOR` tendrá vista supervisora. No se confiará en un `local_id` del cliente. | Must |
| E1-R09 | El descuento se aplicará al **total del pedido**, no a líneas, como importe o porcentaje mutuamente exclusivo. `CAJA` lo solicitará con motivo y `ADMINISTRADOR` lo autorizará; sólo podrá aplicarse a un pedido `ENTREGADO` y antes del primer pago. Su base, valor y resultado neto quedarán como snapshot. No existirá un límite porcentual arbitrario: todo descuento requerirá autorización de `ADMINISTRADOR`. | Must |
| E1-R10 | `descuento_pedido` será el snapshot autoritativo del descuento. `pedido` no duplicará `subtotal_snapshot`, `descuento_snapshot` ni `total_neto_snapshot`. Una función autoritativa PostgreSQL resolverá el subtotal, descuento y total neto aplicable al cobro. El descuento no podrá volver negativo el total ni cambiar después del primer pago confirmado; los reintentos no crearán descuentos/autorizaciones duplicados. | Must |
| E1-R11 | `ADMINISTRADOR` ejecutará directamente la anulación con motivo obligatorio; no existirá solicitante ni autorizador separados para esta operación. La función bloqueará pedido/mesa y registrará actor administrador, fecha/hora servidor y estado anterior/nuevo. Mantendrá `PAGADO`/`ANULADO` terminales. | Must |
| E1-R12 | Si existe cualquier pago confirmado, incluso parcial, la anulación se bloqueará. No se implementarán reversos ni devoluciones como parte de esta regla. | Must |
| E1-R13 | La división de cuenta permitirá **N pagos monetarios sobre un único `pedido`**, sin crear subpedidos ni cambiar la pertenencia de detalles. Los medios podrán ser distintos o repetidos; son válidos, entre otros, `EFECTIVO + YAPE`, `TARJETA + TARJETA` y `EFECTIVO + YAPE + TARJETA + TARJETA`. La selección de detalles será sólo ayuda de cálculo y la autoridad será el monto aplicado acumulado. | Must |
| E1-R14 | Cada pago parcial tendrá importe positivo, medio permitido, sesión, actor y hora servidor. La suma aplicada no excederá el total neto. El pedido sólo pasará `ENTREGADO → PAGADO` y la mesa sólo se liberará cuando el saldo llegue exactamente a cero. | Must |
| E1-R15 | Dos cobros simultáneos bloquearán el mismo pedido; el segundo recalculará saldo dentro de la transacción. Los reintentos usarán una clave idempotente o contrato equivalente y nunca duplicarán el pago. La regla actual `UNIQUE(pago.pedido_id)` deberá reemplazarse por una garantía compatible con múltiples pagos. | Must |
| E1-R16 | Antes del primer pago se mantiene la reapertura H5 de `ENTREGADO`; después del primer pago parcial no se podrá agregar, editar, retirar, reenviar ni volver a entregar detalles. La UX mostrará que la cuenta está parcialmente pagada. | Must |
| E1-R17 | La propina será opcional, no negativa, se registrará con el pago que la recauda y tendrá medio de pago. Se mantendrá separada del importe aplicado a la venta y no alterará el total autoritativo del pedido; sí afectará la caja si su medio es efectivo. | Must |
| E1-R18 | Se emitirá un recibo interno por cada pago parcial y un ticket consolidado al completar exactamente el total neto. Ambos reflejarán pagos y propinas separadas, no constituirán comprobante fiscal ni definirán tratamiento tributario. | Must |
| E1-R19 | Una auditoría específica permitirá reconstruir apertura, movimientos, descuentos, autorización, anulación, pagos, cierre y valores relevantes anteriores/nuevos, con local, sesión, pedido cuando aplique, actor, autorizador sólo cuando corresponda y hora servidor. Para anulación registrará únicamente al `ADMINISTRADOR` que la ejecutó. No se forzará esta semántica dentro de `historial_estado`. | Must |
| E1-R20 | Los registros financieros y de auditoría no admitirán `UPDATE`/`DELETE` desde cliente. Correcciones futuras deberán ser eventos compensatorios explícitos. Se conservarán FKs `ON DELETE RESTRICT` y trazabilidad histórica. | Must |
| E1-R21 | Los reportes mínimos mostrarán por sesión: apertura/cierre, totales por medio, efectivo esperado, contado/diferencia, entradas, salidas, descuentos, anulaciones, propinas y pagos divididos, sin convertirse en libro contable ni conciliación bancaria. | Must |
| E1-R22 | La estación PC de Caja mostrará permanentemente estado de caja, quién abrió, monto inicial y esperado, sin presentar la sesión como exclusiva de esa persona; priorizará cobro rápido. Apertura, cierre, salidas, descuento y anulación requerirán confirmación clara y estados de carga/error/reintento. | Must |

## 4. Seguridad, roles e invariantes

- `CAJA`: cualquier usuario activo del local puede continuar la sesión abierta de una caja del mismo local, registrar entradas/salidas, cobrar y cerrar; cada operación conserva su actor. También solicita/aplica únicamente descuentos ya autorizados y consulta operación de caja de su local.
- `ADMINISTRADOR`: autoriza descuentos, ejecuta directamente anulaciones, consulta sesiones/reportes del local y puede ejecutar cierre supervisor con motivo y auditoría. No hereda cobro operativo por defecto.
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
| EC-08 | Un pedido admite N pagos y los medios pueden repetirse; sólo llega a `PAGADO` al completar exactamente el total neto. |

### Propuestas técnicas del spec

| ID | Propuesta |
|---|---|
| PT-01 | Introducir caja física, sesión, movimientos inmutables y auditoría específica. |
| PT-02 | Implementar división como múltiples pagos sobre un pedido, sin subpedidos. |
| PT-03 | Modelar propina separada del importe de venta dentro del evento de pago. |
| PT-04 | Aplicar antes del primer pago el snapshot de descuento asociado al pedido, persistido exclusivamente en `descuento_pedido`. |

### Decisión técnica aprobada

| ID | Decisión | Comportamiento cerrado |
|---|---|---|
| DT-01 | Fuente autoritativa del descuento. | `descuento_pedido` conserva el snapshot; `pedido` no duplica subtotal, descuento ni total neto; una función PostgreSQL obtiene los tres importes aplicables al cobro. |

### Decisiones funcionales aprobadas

| ID | Decisión aprobada | Comportamiento cerrado |
|---|---|---|
| DF-01 | Cierre con pedidos pendientes. | Se permite; los pedidos pertenecen a la sesión que finalmente los cobra, no a aquella en que se crearon. |
| DF-02 | Diferencia de cierre. | Se permite; motivo obligatorio cuando diferencia ≠ 0 y visibilidad para `ADMINISTRADOR`. |
| DF-03 | Solicitud, autorización y momento del descuento. | `CAJA` solicita; `ADMINISTRADOR` autoriza; sólo en `ENTREGADO` y antes del primer pago. |
| DF-04 | Límite comercial del descuento. | No se fija porcentaje arbitrario; todo descuento requiere autorización de `ADMINISTRADOR`. |
| DF-06 | Documentos de pagos parciales. | Recibo interno por cada pago parcial y ticket consolidado al completar. |
| DF-07 | Cierre supervisor. | `ADMINISTRADOR` puede ejecutarlo con motivo y auditoría. |
| DF-08 | Selección de caja física. | Caja configurable/seleccionable; no queda vinculada permanentemente al navegador. |
| DF-09 | División mediante selección de productos. | La selección sólo ayuda a calcular; se persiste importe, no asignación histórica por líneas. |

No quedan decisiones funcionales ni técnicas pendientes para iniciar construcción. EC-06, EC-07 y EC-08 permanecen cerradas.

## 6. Fuera de alcance

Inventario, recetas, compras/proveedores, SUNAT, Yape/Plin directo, pasarela bancaria, multiempresa/multilocal, usuarios multirol/multilocal, cancelación de productos por mozo, métricas NoSQL, replicación DEV/PROD, cambios de PM-002, contabilidad, conciliación bancaria completa, recepción de cocina completa, impresión de comandas y funcionalidades de otras evoluciones. La impresión opcional como apoyo al flujo digital de cocina se definirá en el Spec Mode de Evolución 7.

## 7. Criterios de salida de construcción futura

Requisitos y decisiones sensibles aprobados; migraciones aditivas/reversibles revisadas; RPC/RLS/grants y concurrencia aprobados; regresión H1–H6/PM-001 sin fallos; pruebas humanas de Caja ejecutadas; documentación actualizada; cero defectos financieros bloqueantes. La aceptación será un acto posterior y no forma parte de este Spec Mode.

## 8. Trazabilidad resumida

La matriz detallada se mantiene en `test-plan.md`. Agrupación: R01–R08 → D02–D05, T02–T05, TP01–TP18; R09–R12 → D06–D07, T06–T07, TP19–TP30; R13–R18 → D08–D09, T08–T10, TP31–TP48; R19–R20 → D10, T11, TP49–TP55; R21–R22 → D11–D12, T12–T14, TP56–TP64.
