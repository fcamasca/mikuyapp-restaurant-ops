# MikuyApp — H5 Entrega, caja, cobro e impresión: plan de pruebas

Este plan separa pruebas automatizadas/SQL-técnicas de pruebas humanas. La reapertura de `ENTREGADO` aprobada durante TH01 fue implementada y verificada; TH01–TH09 y la consolidación técnica T10 quedaron aprobadas. H5 fue cerrado, validado y aceptado el 2026-08-30.

## Pruebas automatizadas y SQL/técnicas

| ID | Caso | Resultado esperado | Req./tarea |
|---|---|---|---|
| H5-TA01 | Pedido con al menos un detalle y todos sus detalles `LISTO`. | Se ofrece entrega; cabecera `ENTREGADO`, mesa `PENDIENTE_PAGO`, detalles siguen `LISTO`. | R01-R04/T02 |
| H5-TA02 | Un detalle `EN_PREPARACION`, `ABIERTO` o agregado no listo. | Entrega rechazada, cero cambios e historial. | R02/T02 |
| H5-TA03 | Doble entrega secuencial, doble clic, snapshot obsoleto y dos sesiones sobre el mismo ciclo. | Como máximo una transición `LISTO→ENTREGADO` por ciclo; segundo intento falla sin duplicado. Una nueva entrega solo es válida después de una reapertura real y un nuevo ciclo completo de cocina. | R03/T02 |
| H5-TA04 | Leer mesas/pedidos pendientes como `CAJA`; intentar entrega/cobro como `MOZO`, `COCINA`, `ADMINISTRADOR` y anon. | `CAJA` solo cobra y `MOZO` solo entrega; cocina, administrador y demás roles no ejecutan operaciones H5 no autorizadas. | R05,R08/T02-T04 |
| H5-TA05 | Usuario válido de otro local y rol no autorizado. | Sin filas transaccionales y sin ejecución de funciones. | R03,R08/T01,T03 |
| H5-TA06 | Consumo con varias líneas/cantidades, producto inactivo y cambio posterior de precio/nombre. | Producto inactivo sigue siendo visible/resoluble; `precio_unitario` histórico y total son correctos; el nombre se obtiene de `producto.nombre` vigente y no se afirma snapshot histórico. | R05,R10/T03 |
| H5-TA07 | Cada medio `EFECTIVO`, `YAPE`, `PLIN`, `TARJETA`. | Un cobro válido por medio; medio persistido exactamente. | R07/T04 |
| H5-TA08 | Cobro correcto de `ENTREGADO`. | Exactamente un `pago`, importe autoritativo, `PAGADO`, historial y mesa `LIBRE` en una transacción. | R08-R10/T04 |
| H5-TA09 | Cobro de `LISTO`, `PAGADO`, `ANULADO`, pedido inexistente o medio inválido. | Rechazo sin cambios ni pago. | R08/T04 |
| H5-TA10 | Doble cobro secuencial. | Segundo intento falla; `count(pago)=1`. | R09/T04 |
| H5-TA11 | Dos cobros concurrentes sobre el mismo pedido. | Un commit, un pago, un historial `ENTREGADO→PAGADO`; otra sesión falla tras lock/conflicto. | R03,R09/T04,T08 |
| H5-TA12 | Error inducido después de insertar pago o antes de liberar mesa. | Rollback completo: sin pago, pedido sigue `ENTREGADO`, mesa `PENDIENTE_PAGO`, sin historial parcial. | R08/T04,T08 |
| H5-TA13 | Pedido `ENTREGADO`/mesa `PENDIENTE_PAGO`: agregar un producto como `MOZO`; después intentar las mismas operaciones sobre `PAGADO` y `ANULADO`. | En `ENTREGADO`, el nuevo detalle nace `ABIERTO`, anteriores siguen `LISTO`, pedido vuelve al estado derivado y mesa a `OCUPADA`; modificación/retiro/envío aplican solo al nuevo detalle según H3/H4. En `PAGADO`/`ANULADO`, alta, modificación, retiro, envío, cocina, recuperación y entrega se rechazan sin cambios. | R04/T02,T08 |
| H5-TA14 | Ver precuenta antes de pago y ticket antes/después, con locale/zona horaria definidos. | Precuenta sí para `ENTREGADO`; ticket solo para `PAGADO`; campos, `local.nombre`, `es-PE` y `America/Lima` coinciden. | R06/T05 |
| H5-TA15 | Publicación y RLS Realtime. | Solo `detalle_pedido`, `pedido`, `mesa`; señales actualizan mozo/caja sin refresh y resync maneja reconexión/duplicados. | R12/T06 |
| H5-TA16 | Inspección de impresión. | CSS oculta navegación/acciones y produce ancho razonable de 80 mm; documento sigue visible si impresora falla. | R11/T07 |
| H5-TA17 | Suite regresiva H1–H4. | Auth, roles, catálogos, mesa, creación/envío, estados mixtos, cocina, Realtime y liberación de pedido vacío siguen pasando. | R01-R12/T09 |
| H5-TA18 | Ciclo completo posterior a entrega: `ENTREGADO/PENDIENTE_PAGO`, alta nueva, cocina, nueva entrega y bloqueo postpago. | Nuevo detalle `ABIERTO`; anteriores `LISTO`; pedido vuelve al flujo y mesa `OCUPADA`; detalle recorre cocina; todos `LISTO` permiten nueva entrega y mesa `PENDIENTE_PAGO`; después de `PAGADO` todo queda bloqueado. | R02-R04,R08/T02,T08,T09 |

### Evidencia H5-TA11 — 2026-08-29

H5-TA11 queda satisfecha. Dos solicitudes concurrentes alcanzaron backends PostgreSQL distintos sobre el mismo pedido inicialmente `ENTREGADO`, con su mesa `PENDIENTE_PAGO`. Una sesión confirmó el cobro y la otra terminó con su transacción PostgreSQL abortada después de competir por el lock. La verificación persistida confirmó pedido `PAGADO`, mesa `LIBRE`, detalles aún `LISTO`, exactamente una fila en `pago` y exactamente un historial `ENTREGADO → PAGADO`. Los fixtures se limpiaron al finalizar.

Limitación del entorno: PostgREST no devolvió al segundo cliente el código ni el mensaje del conflicto antes del timeout, aunque PostgreSQL mostró la transacción perdedora abortada. La validación del mensaje visible para el segundo cliente corresponde a H5-TH03 y no bloquea H5-T04 ni la propiedad funcional de pago único.

### Evidencia H5-T08 — 2026-08-30

La validación técnica integral quedó aprobada: cuatro pruebas SQL H5 remotas pasaron, la regresión SQL H1–H4 pasó 14/14 y la suite automatizada pasó 284/284. `supabase db lint --linked --level error`, typecheck, build y `git diff --check` finalizaron correctamente. Las 25 migraciones locales y remotas están alineadas y la auditoría posterior confirmó cero fixtures residuales H5/TP10.

Se actualizaron únicamente pruebas históricas: H3-T01 valida el rechazo CHECK por SQLSTATE `23514` sin depender del orden entre constraints vigentes; TP10 crea contexto MOZO autorizado para alcanzar los constraints objetivo y reconoce el índice H4 `idx_detalle_pedido_cocina_enviado_en`. No se modificaron funciones, RLS, constraints, migraciones ni comportamiento productivo.

Se conserva la limitación ya documentada del entorno concurrente: las sesiones ganadoras y el estado persistido único se comprobaron, pero el canal Management API agotó el timeout antes de devolver al cliente perdedor su código/mensaje. No afecta las propiedades verificadas de transición, historial y pago únicos; la evidencia visible para el cliente continúa asignada a H5-TH03.

## Pruebas humanas finales

| ID | Escenario | Evidencia |
|---|---|---|
| H5-TH01 | **APROBADA (2026-08-30).** Mozo observa un pedido completamente listo, confirma la entrega desde celular y la vista resincroniza `ENTREGADO`/mesa `PENDIENTE_PAGO`; durante la validación se aprobó que `ENTREGADO` pueda reabrirse por nuevos productos antes del pago. | Validación humana confirmada; la nueva regla fue implementada y verificada técnicamente antes de TH02. |
| H5-TH02 | **APROBADA (2026-08-30).** Mozo intenta entregar con una línea no lista y luego reintenta con estado actualizado. | Validación humana confirmó rechazo comprensible sin falso éxito y entrega posterior correcta. |
| H5-TH03 | **APROBADA (2026-08-30).** Dos dispositivos intentan entregar/cobrar el mismo pedido. | Validación humana confirmó una sola operación ganadora y conflicto/estado ya procesado en el segundo cliente. |
| H5-TH04 | **APROBADA (2026-08-30).** Caja en PC consulta mesas pendientes, abre consumo, verifica total y estado `ENTREGADO`. | Flujo validado humanamente sin navegación insegura. |
| H5-TH05 | **APROBADA (2026-08-30).** Caja abre precuenta, cobra con un medio representativo y abre ticket interno. | Flujo y documentos validados humanamente con un medio representativo; los cuatro medios (`EFECTIVO`, `YAPE`, `PLIN`, `TARJETA`) están cubiertos por H5-TA07. |
| H5-TH06 | **APROBADA (2026-08-30).** Imprimir/vista previa en 80 mm desde navegador. | Hubo un bloqueo temporal externo por respuesta 504 de Supabase; posteriormente se repitió la prueba y se aprobó ancho, legibilidad, ocultamiento de acciones y corte razonable. |
| H5-TH07 | **APROBADA (2026-08-30).** Caja en tablet y PC; mozo ve `PENDIENTE_PAGO` y luego `LIBRE` sin refresh. | Realtime y presentación responsive aprobados humanamente. |
| H5-TH08 | **APROBADA (2026-08-30).** Roles no autorizados y `CAJA` de un segundo local intentan entrar, leer y operar pedidos ajenos. | Acceso por rol denegado; el segundo local obtuvo cero pedidos ajenos y el cobro directo fue rechazado con `42501`. Fixtures temporales eliminados y residuos en cero. |
| H5-TH09 | **APROBADA (2026-08-30).** Regresión manual H1–H4 y flujo completo cocina→entrega→cobro. | Validación humana final confirmada. |

### Evidencia final H5-T10 — 2026-08-30

- Suite automatizada completa: **289/289 aprobadas**, sin fallos ni omisiones.
- SQL remoto final: **5/5 pruebas H5** y **14/14 regresiones H1–H4**, total **19/19**.
- `npm run typecheck`, `npm run build` y `git diff --check`: aprobados. El build conserva únicamente el aviso no bloqueante ya conocido por tamaño de bundle.
- `supabase db lint --linked --level error`: sin errores de esquema.
- Migraciones: **26/26 local/remoto alineadas**, última `20260830000200_h5_reopen_delivered_order.sql`.
- Auditoría final de fixtures H5, incluido el escenario temporal TH08: **0 residuos**.
- Concurrencia y rollback conservan la evidencia técnica aprobada en T04/T08; no fue necesario modificar funciones productivas durante T10.
- TH01–TH09: **9/9 aprobadas humanamente**.
- T10 consolidó la evidencia que sustentó la aceptación formal registrada en `acceptance.md`.

## Datos y controles

Usar al menos dos locales, usuarios de cada rol, pedido con múltiples detalles y estados mixtos, producto desactivado después de pedido, cantidades mayores que uno, cambio posterior de precio y nombre, los cuatro medios y fallos inducidos en transacción. Incluir obligatoriamente el ciclo: pedido entregado, mesa `PENDIENTE_PAGO`, alta de nuevo producto, detalle nuevo `ABIERTO`, pedido operativo/mesa `OCUPADA`, cocina normal, nueva entrega y retorno a `PENDIENTE_PAGO`; luego cobrar y demostrar bloqueo total post-`PAGADO`. Verificar que el producto inactivo siga resolviendo por `producto.nombre`, que solo `precio_unitario` sea histórico, además de conteos, historial, actor, timestamps, estados de mesa, aislamiento y ausencia de filas parciales directamente en PostgreSQL.

## Trazabilidad de cobertura

H5-R01–R04: TA01–TA03, TA13, TA18, TH01–TH03. H5-R05–R07: TA04–TA07, TA14, TH04–TH05. H5-R08–R10: TA08–TA13, TA18, TH03/TH05. H5-R11: TA16, TH06. H5-R12: TA15, TA18, TH07. Seguridad, aislamiento y regresión: TA04–TA05, TA17, TH08–TH09.
