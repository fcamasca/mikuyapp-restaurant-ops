# MikuyApp — Evolución 1 — Operación de caja: diseño

## D01. Principios y alcance de arquitectura

Se conserva la arquitectura React/Vite → Supabase Data API/RPC → PostgreSQL/RLS. No se incorpora backend general. Las invariantes financieras viven en PostgreSQL y las pantallas sólo presentan snapshots autorizados y solicitan comandos.

La evolución es aditiva salvo el contrato de pago único, que debe transformarse deliberadamente. No se edita una migración aplicada: una migración futura cambia el modelo y preserva todas las filas históricas. PM-002 sigue `TRANSITIONING`; la construcción se hará primero en DEV/Preview y no autoriza cutover ni cambios PROD.

## D02. Modelo mínimo propuesto

| Entidad/cambio | Propósito y campos conceptuales mínimos |
|---|---|
| `caja` | Caja física: `id`, `local_id`, `codigo`, `nombre`, `activo`, timestamps; única por `(local_id,codigo)`. No representa un turno. |
| `sesion_caja` | Un turno perteneciente a caja/local: `abierta_por`, `abierta_en`, `monto_inicial`, estado, y snapshots de cierre (`cerrada_por/en`, esperado, contado, diferencia, motivo_diferencia`). `abierta_por` es trazabilidad, no titularidad. Índice único parcial para una sesión `ABIERTA` por caja. |
| `movimiento_caja` | Evento inmutable `ENTRADA`/`SALIDA`, sesión, importe positivo, motivo, actor, hora e idempotencia. No incluye cobros, que permanecen en `pago`. |
| `descuento_pedido` | Snapshot único vigente por pedido para esta evolución: tipo `IMPORTE`/`PORCENTAJE`, valor solicitado, subtotal base, importe aplicado, total neto, motivo, solicitante, autorizador y timestamps. |
| `auditoria_caja` | Evento append-only específico: tipo, local, sesión/pedido/pago/movimiento opcionales, actor/autorizador, valores anteriores/nuevos acotados y hora. No reemplaza `historial_estado`. |
| `pago` evolucionado | Eliminar unicidad por pedido; agregar `sesion_caja_id`, `idempotency_key`, `propina`, y mantener `importe` como monto aplicado a venta. Restricciones positivas/no negativas y unicidad idempotente por sesión/actor. |

No se propone una tabla genérica de “autorizaciones”: los únicos casos actuales son descuento y anulación, con semánticas diferentes. La autorización de descuento vive en `descuento_pedido`; la anulación se registra como evento de auditoría y transición de pedido. Tampoco se crea `cuenta`, `subcuenta`, `pago_detalle` ni contabilidad de doble partida.

Conforme a DT-01, `descuento_pedido` es el único snapshot autoritativo del descuento. `pedido` no incorpora ni duplica `subtotal_snapshot`, `descuento_snapshot` o `total_neto_snapshot`. Una función autoritativa PostgreSQL calcula el subtotal desde los detalles persistidos, aplica el snapshot vigente de `descuento_pedido` y devuelve subtotal, descuento y total neto para el cobro y sus lecturas relacionadas.

## D03. Apertura

RPC conceptual `abrir_sesion_caja(p_caja_id, p_monto_inicial, p_idempotency_key)`:

1. Obtiene `auth.uid()` y contexto; exige `CAJA`, mismo local, caja activa e importe no negativo.
2. Bloquea la caja y consulta sesión abierta.
3. Si ya existe una sesión abierta, no crea otra y devuelve su snapshot autorizado para que cualquier `CAJA` activo del mismo local continúe operándola; un reintento con igual clave retorna el resultado original.
4. Inserta sesión `ABIERTA`, evento de auditoría y devuelve snapshot.

La restricción única parcial es la defensa final ante doble apertura por caja física. La sesión no pertenece exclusivamente a `abierta_por`: un cambio de cajero no provoca cierre ni arqueo. Toda operación posterior valida un actor `CAJA` activo del mismo local y lo registra independientemente.

## D04. Movimientos y saldo esperado

RPC `registrar_movimiento_caja(p_sesion_id, p_tipo, p_importe, p_motivo, p_idempotency_key)` bloquea sesión, exige que continúe abierta, corresponda a la caja indicada y pertenezca al local del actor `CAJA` activo. No exige que el actor sea `abierta_por`. Inserta movimiento con su actor y auditoría en la misma transacción. No hay edición/borrado.

Una función de lectura calcula:

`esperado = inicial + pagos EFECTIVO + propinas EFECTIVO + entradas - salidas`

Los pagos se asignan a la sesión vigente en el instante de cobro. Yape, Plin y tarjeta aparecen en el resumen por medio, pero no afectan efectivo esperado. No se infieren salidas desde valores negativos: toda salida es `SALIDA` con importe positivo.

## D05. Cierre y consulta histórica

RPC `cerrar_sesion_caja(p_sesion_id, p_efectivo_contado, p_motivo_diferencia, p_idempotency_key)`:

1. Valida actor `CAJA` activo, local y caja; no exige que sea `abierta_por`; bloquea caja y sesión.
2. Impide nuevos pagos/movimientos tomando locks compatibles; las RPC de cobro/movimiento bloquean primero sesión y luego pedido cuando aplique.
3. Calcula dentro de la transacción los snapshots por medio, movimientos, esperado y diferencia.
4. Aplica DF-01/DF-02, guarda valores de cierre y `cerrada_por`, conserva `abierta_por`, marca `CERRADA` e inserta auditoría.
5. Los reportes leen snapshots de cierre; nunca los recalculan para alterar historia. Pueden mostrar un recálculo diagnóstico, sin sustituir lo guardado.

La operación de cierre supervisor aprobada en DF-07 será separada, exigirá `ADMINISTRADOR`, motivo y auditoría, y conservará `abierta_por`, `cerrada_por` y el actor supervisor.

## D06. Descuentos autorizados

El descuento se aplicará a nivel pedido porque minimiza cambios y evita reasignar importes a detalles. Flujo aprobado:

1. `CAJA` solicita sobre pedido `ENTREGADO`, sin pagos, indicando tipo/valor/motivo.
2. `ADMINISTRADOR` autoriza o rechaza desde una bandeja del mismo local.
3. La autorización bloquea pedido, recalcula subtotal desde snapshots de detalles, valida valor y persiste subtotal/importe/total neto.
4. Cobro consume ese snapshot. El descuento no cambia por modificaciones posteriores; esas modificaciones quedan prohibidas después de autorización salvo revocación auditada previa al primer pago.

La solicitud de `CAJA` y la decisión de `ADMINISTRADOR` deben quedar trazadas. Sólo se admite sobre `ENTREGADO` y antes del primer pago. No se fija un porcentaje máximo arbitrario: todo descuento requiere autorización administrativa.

## D07. Anulación supervisada

RPC `anular_pedido_supervisado(p_pedido_id, p_motivo, p_idempotency_key)` exige `ADMINISTRADOR`, mismo local y motivo. El administrador ejecuta directamente: no existe solicitante ni autorizador separado. Bloquea pedido y mesa. Sin pagos, cambia a `ANULADO`, registra en `historial_estado` y auditoría el actor administrador, fecha/hora y estado anterior/nuevo, y libera o deriva la mesa de forma consistente con el modelo vigente.

No modifica detalles ni elimina filas. Si existe cualquier pago confirmado, incluso parcial, rechaza la anulación. Para estados avanzados (`ENVIADO` a `ENTREGADO`) la UI advierte el impacto operativo; la función mantiene una política explícita de estados anulables aprobada. La cancelación granular por mozo sigue fuera de alcance.

## D08. División y cobro transaccional

La mínima definición útil de “dividir cuenta” es permitir varios pagos sobre un pedido. RPC conceptual `registrar_pago_pedido_v2(p_pedido_id, p_importe_aplicar, p_medio, p_propina, p_idempotency_key)`:

1. Valida `CAJA` activo y una sesión abierta de la caja en su mismo local; no exige que el actor sea `abierta_por`.
2. Bloquea sesión y pedido en orden estable; valida `ENTREGADO` o estado interno equivalente de saldo pendiente, mesa `PENDIENTE_PAGO` y ausencia de anulación.
3. Calcula subtotal, descuento, total neto, suma ya pagada y saldo.
4. Exige `0 < importe_aplicar <= saldo`, propina `>= 0` y medio válido; nunca toma total/saldo del cliente.
5. Inserta el pago con sesión e idempotencia.
6. Si queda saldo, conserva pedido `ENTREGADO` y mesa pendiente; sólo si la suma de N pagos alcanza exactamente el total neto cambia a `PAGADO`, inserta `historial_estado` y libera mesa.

Los medios de los N pagos son independientes y pueden repetirse. El modelo y la RPC deben aceptar tanto combinaciones mixtas (`EFECTIVO + YAPE`) como repetidas (`TARJETA + TARJETA`) y combinaciones de tres o más pagos (`EFECTIVO + YAPE + TARJETA + TARJETA`), manteniendo un actor propio por fila.

La selección de productos o división por persona es sólo una calculadora en frontend que produce un importe sugerido; PostgreSQL acepta, valida y persiste únicamente el importe aplicado. No se persiste asignación histórica por líneas ni se crea `pago_detalle`. Esto cubre división por detalles, importe y múltiples medios sin subcuentas.

La antigua `UNIQUE(pago.pedido_id)` se reemplaza por índices de consulta y unicidad de idempotencia. La garantía de no sobrepago queda en lock + suma transaccional + validación. El pago histórico existente se migra con propina cero y una asociación de sesión sólo si existe evidencia; no se inventará una sesión retroactiva. Puede mantenerse `sesion_caja_id NULL` únicamente para filas legacy y exigir `NOT NULL` a nuevas inserciones vía RPC/constraint aplicable.

## D09. Propina y documentos

`pago.importe` continúa significando importe aplicado a venta; `propina` es columna separada. El desembolso total del cliente es `importe + propina`. La propina no reduce saldo ni aparece como venta; aparece separada por medio y se suma al efectivo esperado sólo cuando `medio='EFECTIVO'`.

Cada pago parcial devuelve un recibo interno con aplicado, propina, medio y saldo. Al completar exactamente el total neto, el ticket consolidado lista subtotal, descuento, total neto, pagos, propinas y saldo cero. No se formula tratamiento fiscal.

## D10. Auditoría

`historial_estado` se conserva para transiciones de pedido. `auditoria_caja` registra eventos de negocio financieros con un catálogo cerrado: apertura, entrada, salida, solicitud/autorización/rechazo/revocación de descuento, pago, anulación directa por administrador, cierre y cierre supervisor. Apertura, cada movimiento, cada pago, anulación y cierre conservan su actor propio; `abierta_por` y `cerrada_por` pueden ser distintos.

Los IDs, actores e importes principales se almacenan en columnas normalizadas; JSONB se usa únicamente para snapshots complementarios acotados por tipo de evento. La inserción ocurre dentro de cada RPC; los clientes no reciben privilegio de escritura. RLS permite lectura local según rol y jamás acceso cruzado.

## D11. Lecturas, reportes y Realtime

Crear snapshots RPC de sesión activa, cierre/histórico y reporte. Derivan local desde contexto servidor. El reporte separa venta, propina, medios y efectivo; pagos parciales cuentan como pedido pagado sólo cuando el pedido llega a `PAGADO`, evitando inflar conteos.

No publicar payload financiero como verdad. La opción mínima es conservar `pago` fuera de Realtime y hacer resync explícito después de comandos; para cambios de sesión/movimientos entre terminales, se pueden publicar tablas con RLS si la verificación confirma filtrado suficiente o usar una tabla de señales sin montos. La decisión técnica debe privilegiar no exponer importes por eventos. `pedido`/`mesa` siguen anunciando pago final.

## D12. UX de Caja

La cabecera fija indica caja, sesión, quién abrió, apertura, inicial y esperado; no presenta al abridor como propietario exclusivo. Sin sesión abierta, cobro y movimientos quedan deshabilitados y el foco es “Abrir caja”. Con sesión abierta, cualquier `CAJA` activo del local puede continuar y se priorizan pedidos pendientes/cobro; movimientos e historial quedan secundarios. Cierre presenta resumen y diferencia antes de confirmar y conserva quién cerró.

Descuento muestra solicitante, autorización y motivo. Anulación muestra el administrador que la ejecutó, fecha/hora y motivo, sin solicitante/autorizador separados. Pago dividido muestra total neto, acumulado, N pagos y saldo, con protección doble clic y medios repetibles. La selección por detalles es una ayuda visual sin reasignar el modelo. Todos los conflictos refrescan el snapshot autoritativo y explican si otro usuario cerró, cobró o modificó la operación.

## D13. Concurrencia y orden de bloqueos

Orden recomendado: `caja` → `sesion_caja` → `pedido` → `mesa`; operaciones que no necesitan todos omiten los posteriores. Descuento/anulación/cobro bloquean pedido; cierre bloquea sesión antes de agregar totales; cobro bloquea sesión antes de pedido. Restricciones únicas/idempotencia complementan locks.

Casos obligatorios: doble apertura/cierre/cobro, cobro vs cierre, cobro vs anulación, descuento vs cobro, reapertura vs primer pago, dos parciales sobre el mismo saldo y reintento después de timeout. Todo error revierte evento, auditoría y estados juntos.

## D14. Riesgos y compatibilidad

| Riesgo | Tratamiento |
|---|---|
| Cambiar pago único afecta H5/H6/reportes/tests. | Migración explícita, RPC v2, regresión completa y conservación de semántica histórica. |
| Cierre concurrente con cobro. | Locks de sesión y precondición abierta en toda operación financiera. |
| Auditoría genérica difícil de consultar. | Eventos cerrados y campos principales normalizados. |
| PM-002 aún en transición. | DEV/Preview primero; ningún cambio remoto o cutover implícito. |
| Histórico sin sesión. | Permitir legacy identificable; nunca fabricar asociación retroactiva. |

## D15. Trazabilidad

R01–R08 → D02–D05/D13; R09–R12 → D06–D07/D13; R13–R18 → D08–D09/D13; R19–R20 → D10; R21–R22 → D11–D12. Las tareas y pruebas conservan estos IDs.
