# MikuyApp — Evolución 1 — Operación de caja: diseño

## D01. Principios y alcance de arquitectura

Se conserva la arquitectura React/Vite → Supabase Data API/RPC → PostgreSQL/RLS. No se incorpora backend general. Las invariantes financieras viven en PostgreSQL y las pantallas sólo presentan snapshots autorizados y solicitan comandos.

La evolución es aditiva salvo el contrato de pago único, que debe transformarse deliberadamente. No se edita una migración aplicada: una migración futura cambia el modelo y preserva todas las filas históricas. PM-002 sigue `TRANSITIONING`; la construcción se hará primero en DEV/Preview y no autoriza cutover ni cambios PROD.

## D02. Modelo mínimo propuesto

| Entidad/cambio | Propósito y campos conceptuales mínimos |
|---|---|
| `caja` | Caja física: `id`, `local_id`, `codigo`, `nombre`, `activo`, timestamps; única por `(local_id,codigo)`. No representa un turno. |
| `sesion_caja` | Un turno perteneciente a caja/local: `abierta_por`, `abierta_en`, `monto_inicial`, estado, y snapshots de cierre (`cerrada_por/en`, esperado, contado, diferencia, motivo_diferencia`). `abierta_por` es trazabilidad, no titularidad. Índice único parcial para una sesión `ABIERTA` por caja. |
| `movimiento_caja` | Evento inmutable `ENTRADA`/`SALIDA`, sesión, importe positivo, motivo, actor, hora e idempotencia. No incluye cobros, que permanecen en `cobro` + `pago`. |
| `descuento_pedido` | Snapshot único vigente por pedido para esta evolución: tipo `IMPORTE`/`PORCENTAJE`, valor solicitado, subtotal base, importe aplicado, total neto, motivo, solicitante, autorizador y timestamps. |
| `cobro` | Cabecera mínima e inmutable de un acto de cobro: `id`, pedido, sesión, actor, total aplicado, propina total derivable, saldo anterior/posterior, hora servidor e idempotencia única en su contexto. Agrupa uno o varios medios y origina un único documento/evento lógico. |
| `auditoria_caja` | Evento append-only específico: tipo, local, sesión/pedido/cobro/pago/movimiento opcionales, actor/autorizador, valores anteriores/nuevos acotados y hora. No reemplaza `historial_estado`. |
| `notificacion_caja` | Evento interno mínimo `APERTURA`/`CIERRE`: `id`, `local_id`, `sesion_caja_id`, `auditoria_caja_id`, tipo, prioridad `INFORMATIVA`/`ALERTA` y hora servidor. `auditoria_caja_id` es único y evita duplicación ante reintentos. No copia importes ni snapshots financieros. |
| `notificacion_caja_destinatario` | Entrega por administrador: `notificacion_caja_id`, `administrador_id`, `leida_en`; clave única por notificación/destinatario. Materializa únicamente los `ADMINISTRADOR` activos del mismo local al producirse el evento y conserva lectura individual entre sesiones. |
| `pago` evolucionado | Cada fila representa un medio dentro de un acto: agregar `cobro_id`, conservar sesión/actor/hora por compatibilidad y trazabilidad, `medio`, `importe` aplicado a venta y `propina` separada. Para filas nuevas `cobro_id` es obligatorio; las legacy pueden permanecer sin cabecera identificadas explícitamente. |

No se propone una tabla genérica de “autorizaciones”: los únicos casos actuales son descuento y anulación, con semánticas diferentes. La autorización de descuento vive en `descuento_pedido`; la anulación se registra como evento de auditoría y transición de pedido. Tampoco se crea `cuenta`, `subcuenta`, `pago_detalle` ni contabilidad de doble partida.

Conforme a DT-01, `descuento_pedido` es el único snapshot autoritativo del descuento. `pedido` no incorpora ni duplica `subtotal_snapshot`, `descuento_snapshot` o `total_neto_snapshot`. Una función autoritativa PostgreSQL calcula el subtotal desde los detalles persistidos, aplica el snapshot vigente de `descuento_pedido` y devuelve subtotal, descuento y total neto para el cobro y sus lecturas relacionadas.

## D03. Apertura

RPC conceptual `abrir_sesion_caja(p_caja_id, p_monto_inicial, p_idempotency_key)`:

1. Obtiene `auth.uid()` y contexto; exige `CAJA`, mismo local, caja activa e importe no negativo.
2. Bloquea la caja y consulta sesión abierta.
3. Si ya existe una sesión abierta, no crea otra y devuelve su snapshot autorizado para que cualquier `CAJA` activo del mismo local continúe operándola; un reintento con igual clave retorna el resultado original.
4. Inserta sesión `ABIERTA`, evento de auditoría, notificación y destinatarios administrativos del mismo local, y devuelve snapshot.

La restricción única parcial es la defensa final ante doble apertura por caja física. La sesión no pertenece exclusivamente a `abierta_por`: un cambio de cajero no provoca cierre ni arqueo. Toda operación posterior valida un actor `CAJA` activo del mismo local y lo registra independientemente.

Homologación TP03/TP04: recuperar una sesión ya abierta no es un error funcional y no altera `abierta_por`. En aperturas concurrentes ambas llamadas devuelven el mismo `sesion_caja.id`; sólo una crea la sesión. La RPC resuelve de forma segura un eventual conflicto interno `23505`, sin exponerlo como respuesta funcional normal.

## D04. Movimientos y saldo esperado

RPC `registrar_movimiento_caja(p_sesion_id, p_tipo, p_importe, p_motivo, p_idempotency_key)` bloquea sesión, exige que continúe abierta, corresponda a la caja indicada y pertenezca al local del actor `CAJA` activo. No exige que el actor sea `abierta_por`. Inserta movimiento con su actor y auditoría en la misma transacción. No hay edición/borrado.

Se conserva esa RPC individual por compatibilidad. La operación de Caja usa `registrar_movimientos_caja(p_sesion_id, p_movimientos jsonb, p_idempotency_key)`: recibe únicamente una lista acotada de `{tipo, importe, motivo}`, deriva actor/local/hora en servidor, aplica las mismas validaciones y locks, y registra todo el lote o nada. La idempotencia pertenece al lote; cada fila conserva su movimiento y evento de auditoría propios. Un elemento inválido revierte cabecera de idempotencia, movimientos y auditorías del lote completo.

Una función de lectura calcula:

`esperado = inicial + pagos EFECTIVO + propinas EFECTIVO + entradas - salidas`

Los pagos se asignan a la sesión vigente en el instante de cobro. Yape, Plin y tarjeta aparecen en el resumen por medio, pero no afectan efectivo esperado. No se infieren salidas desde valores negativos: toda salida es `SALIDA` con importe positivo.

## D05. Cierre y consulta histórica

RPC `cerrar_sesion_caja(p_sesion_id, p_efectivo_contado, p_motivo_diferencia, p_idempotency_key)`:

1. Valida actor `CAJA` activo, local y caja; no exige que sea `abierta_por`; bloquea caja y sesión.
2. Impide nuevos pagos/movimientos tomando locks compatibles; las RPC de cobro/movimiento bloquean primero sesión y luego pedido cuando aplique.
3. Calcula dentro de la transacción los snapshots por medio, movimientos, esperado y diferencia.
4. Aplica DF-01/DF-02, guarda valores de cierre y `cerrada_por`, conserva `abierta_por`, marca `CERRADA` e inserta auditoría, notificación y destinatarios administrativos del mismo local.
5. Los reportes leen snapshots de cierre; nunca los recalculan para alterar historia. Pueden mostrar un recálculo diagnóstico, sin sustituir lo guardado.

La UI no ejecuta el cierre desde el primer clic. Primero presenta caja, inicial, cobros/propinas en efectivo, entradas, salidas, esperado, contado y la diferencia `contado - esperado`; exige motivo cuando esa diferencia no es cero y ofrece únicamente `Confirmar cierre`/`Volver`. Sólo la confirmación invoca la RPC y queda protegida contra doble envío. Después del éxito muestra el snapshot persistido como `REPORTE INTERNO DE CIERRE`, imprimible manualmente en formato térmico de 80 mm, no fiscal y sin recalcular la historia.

Si la diferencia es distinta de cero, el resumen previo informa: `Se registrará la diferencia y se notificará al administrador.` Esto no introduce autorización ni espera administrativa. Tras el éxito, la UI puede confirmar: `Caja cerrada con diferencia. El administrador ha sido notificado.`

La operación de cierre supervisor aprobada en DF-07 será separada, exigirá `ADMINISTRADOR`, motivo y auditoría, y conservará `abierta_por`, `cerrada_por` y el actor supervisor. Como todo cierre, genera la misma notificación idempotente para los administradores activos del local, sin crear un flujo de aprobación.

## D06. Descuentos autorizados

El descuento se aplicará a nivel pedido porque minimiza cambios y evita reasignar importes a detalles. Flujo aprobado:

1. `CAJA` solicita sobre pedido `ENTREGADO`, sin pagos, indicando tipo/valor/motivo.
2. `ADMINISTRADOR` autoriza o rechaza desde una bandeja del mismo local.
3. La autorización bloquea pedido, recalcula subtotal desde snapshots de detalles, valida valor y persiste subtotal/importe/total neto.
4. Cobro consume ese snapshot. Una solicitud que alcanza `AUTORIZADO` o `RECHAZADO` queda inmutable; E1 no incluye revocación, modificación ni reversión de descuentos decididos.

La solicitud de `CAJA` y la decisión de `ADMINISTRADOR` deben quedar trazadas. Sólo se admite sobre `ENTREGADO` y antes del primer pago. No se fija un porcentaje máximo arbitrario: todo descuento requiere autorización administrativa.

## D07. Anulación supervisada

RPC `anular_pedido_supervisado(p_pedido_id, p_motivo, p_idempotency_key)` exige `ADMINISTRADOR`, mismo local y motivo. El administrador ejecuta directamente: no existe solicitante ni autorizador separado. Bloquea pedido y mesa. Sin pagos, cambia a `ANULADO`, registra en `historial_estado` y auditoría el actor administrador, fecha/hora y estado anterior/nuevo, y libera o deriva la mesa de forma consistente con el modelo vigente.

No modifica detalles ni elimina filas. Si existe cualquier pago confirmado, incluso parcial, rechaza la anulación. Sin pagos confirmados, la matriz definitiva permite `ABIERTO`, `ENVIADO`, `RECIBIDO_COCINA`, `EN_PREPARACION`, `LISTO` y `ENTREGADO`; bloquea `PAGADO` y `ANULADO`. Para `EN_PREPARACION`, `LISTO` y `ENTREGADO`, la futura UI advertirá el impacto operativo antes de confirmar, sin cambiar la autorización PostgreSQL. La anulación completa por `ADMINISTRADOR` es distinta de la cancelación individual de productos por `MOZO` de Evolución 7. No se implementan reversos ni devoluciones.

## D08. Acto de cobro, medios y parciales

La alternativa aprobada a partir de TP62 es una cabecera mínima `cobro` con N filas `pago`. Una cabecera representa una sola decisión/confirmación/documento; sus filas representan exclusivamente los medios utilizados. Es el menor cambio que ofrece agrupación persistente, atomicidad e idempotencia de todo el acto sin introducir `pago_detalle`, subcuentas ni asignación de productos.

RPC conceptual sustituta de `registrar_pago_pedido_v2`:

`registrar_cobro_pedido(p_pedido_id, p_sesion_caja_id, p_tipo_cobro, p_medios jsonb, p_idempotency_key)`

`p_tipo_cobro` admite `TOTAL` o `PARCIAL`. `p_medios` es una lista acotada de objetos `{medio, importe, propina}`; el cliente no envía actor, local, saldo, total neto, timestamps ni estados. El contrato devuelve cabecera de cobro, líneas persistidas, subtotal/descuento/neto, saldo anterior/posterior, estado de pedido/mesa e información necesaria para el único documento interno.

1. Obtiene `auth.uid()`; exige `CAJA` activo, sesión abierta y pertenencia al mismo local.
2. Bloquea exactamente `sesion_caja → pedido → mesa`; valida pedido `ENTREGADO`, mesa `PENDIENTE_PAGO` y ausencia de anulación.
3. Resuelve subtotal/descuento/total neto, cobros anteriores y saldo vigente dentro de la transacción.
4. Valida lista no vacía, medio permitido, cada `importe > 0`, cada `propina >= 0` y suma monetaria exacta con precisión de moneda. Medios repetidos son válidos.
5. Para `TOTAL`, exige suma de importes igual al saldo. Para `PARCIAL`, exige `0 < suma < saldo`. Un faltante impide confirmar en UI y también es rechazado por servidor para `TOTAL`; exceso siempre se rechaza.
6. Inserta una cabecera `cobro`, todas sus filas `pago` y un único evento lógico `PAGO` de auditoría. Cualquier fallo en una línea revierte el conjunto.
7. Si el saldo posterior es positivo conserva pedido `ENTREGADO` y mesa pendiente. Si es cero cambia a `PAGADO`, registra una sola transición en `historial_estado` y libera mesa.

Un cobro normal puede contener `EFECTIVO 20 + YAPE 24 + YAPE 20` y se confirma una sola vez por 64. `Cobrar una parte` crea otra cabecera independiente, aunque use uno o varios medios. Dos actos parciales producen dos documentos; varias líneas dentro de un mismo acto producen uno solo.

La selección de productos o división por persona es sólo una calculadora en frontend que produce un importe sugerido; PostgreSQL acepta, valida y persiste únicamente el importe aplicado. No se persiste asignación histórica por líneas ni se crea `pago_detalle`. Esto cubre división por detalles, importe y múltiples medios sin subcuentas.

La idempotencia reside en `cobro`, no por línea: una clave repetida en el mismo contexto retorna la cabecera y el conjunto original. La antigua `UNIQUE(pago.pedido_id)` permanece reemplazada por índices de consulta; la garantía de no sobrepago queda en lock + suma transaccional + validación. Los pagos históricos se conservan exactamente, sin fabricar cabeceras ni sesiones; `cobro_id`/`sesion_caja_id NULL` sólo identifican legacy, mientras toda escritura nueva ocurre mediante la RPC y exige ambos vínculos.

## D09. Propina y documentos

`pago.importe` continúa significando la parte de venta aportada por ese medio; `propina` es columna separada en la misma línea. El total del acto es la suma de importes y la propina total es la suma separada de sus líneas. La propina no reduce saldo ni aparece como venta; sólo importe y propina de líneas `EFECTIVO` incrementan el efectivo esperado.

Cada cabecera `cobro` origina un único documento. Un acto parcial devuelve un recibo interno con resumen financiero del pedido, total neto, importe pagado anteriormente, medios y propina exclusivos de ese acto, importe cobrado y saldo posterior; no atribuye productos al pago. El acto que completa el saldo devuelve un ticket consolidado que lista los productos completos del pedido, subtotal, descuento, total neto, cobros anteriores, cobro final, detalle de medios/propinas y saldo cero. No se formula tratamiento fiscal.

## D10. Auditoría

`historial_estado` se conserva para transiciones de pedido. `auditoria_caja` registra eventos de negocio financieros con un catálogo cerrado: apertura, entrada, salida, solicitud/autorización/rechazo de descuento, pago, anulación directa por administrador, cierre y cierre supervisor. No existe evento ni flujo de revocación de descuento en E1. Cada acto de cobro produce un solo evento `PAGO`, referenciado a `cobro`, con total/saldo anterior/saldo posterior en columnas o snapshot acotado y detalle complementario de medios; no se generan N eventos lógicos por sus N líneas. Apertura, cada movimiento, cada cobro, anulación y cierre conservan su actor propio; `abierta_por` y `cerrada_por` pueden ser distintos.

Los IDs, actores e importes principales se almacenan en columnas normalizadas; JSONB se usa únicamente para snapshots complementarios acotados por tipo de evento. La inserción ocurre dentro de cada RPC; los clientes no reciben privilegio de escritura. RLS permite lectura local según rol y jamás acceso cruzado.

Las notificaciones no sustituyen ni duplican la auditoría. La apertura o cierre crea `notificacion_caja` en la misma transacción que su evento de `auditoria_caja`; una unicidad sobre `auditoria_caja_id` hace idempotente la generación. Por cada `ADMINISTRADOR` activo del local se inserta una relación destinataria, protegida además por unicidad `(notificacion_caja_id, administrador_id)`. El cierre usa prioridad `ALERTA` sólo cuando el snapshot persistido de diferencia es distinto de cero; los demás eventos usan `INFORMATIVA`. No existe estado de aprobación, decisión o revisión.

## D11. Lecturas, reportes y Realtime

Crear snapshots RPC de sesión activa, cierre/histórico y reporte. Derivan local desde contexto servidor. El reporte suma las filas por medio, separa venta y propina, calcula efectivo sólo desde líneas `EFECTIVO` y cuenta el pedido una sola vez al llegar a `PAGADO`; `cobro` evita confundir N medios con N actos o duplicar venta.

Como soporte técnico aditivo de T10, `obtener_pedidos_pendientes_pago_caja()` conserva sus campos H5 y añade `subtotal`, `descuento`, `total_neto`, `pagado_acumulado` y `saldo`, resueltos en PostgreSQL. Una lectura CAJA por pedido agrupa los cobros confirmados y expone para cada acto actor/hora/total/saldo posterior y sus líneas de medio/importe/propina. Una lectura operacional separada para `ADMINISTRADOR` presenta pedidos del mismo local en los estados relevantes para descuento/anulación, existencia de cobros y totales autoritativos; no concede capacidad de cobro.

`rpc_obtener_movimientos_sesion_caja(p_sesion_id)` devuelve `id`, sesión, tipo, importe, motivo, actor ID/nombre y hora en orden cronológico. Sólo `CAJA` o `ADMINISTRADOR` activos pueden leer sesiones de su propio local; el local deriva del contexto servidor y la función resuelve el nombre sin ampliar el `SELECT` directo de `perfil_usuario`.

Las lecturas conceptuales `rpc_obtener_notificaciones_caja()`, `rpc_marcar_notificacion_caja_leida(p_notificacion_id)` y `rpc_marcar_notificaciones_caja_leidas()` exigen `ADMINISTRADOR` activo y derivan usuario/local de `auth.uid()`. La primera devuelve únicamente las 50 entregas más recientes del administrador autenticado, junto con el contador total de no leídas, y compone caja, actor legible, hora e importes desde `auditoria_caja`, `caja` y snapshots de `sesion_caja`. El nombre del actor de apertura/cierre se resuelve dentro de esta RPC autorizada, sin ampliar el `SELECT` directo sobre `perfil_usuario`. Las otras RPC actualizan de forma idempotente `leida_en` de una entrega propia o de todas las pendientes del administrador autenticado, sin afectar a otros destinatarios. `CAJA`, `MOZO`, `COCINA`, `anon`, otros locales y escritura directa quedan denegados.

No publicar payload financiero como verdad. La opción mínima es conservar `pago` fuera de Realtime y hacer resync explícito después de comandos; para cambios de sesión/movimientos entre terminales, se pueden publicar tablas con RLS si la verificación confirma filtrado suficiente o usar una tabla de señales sin montos. La decisión técnica debe privilegiar no exponer importes por eventos. `pedido`/`mesa` siguen anunciando pago final.

## D12. UX de Caja y Administración

La cabecera fija usa automáticamente la única caja activa/configurada del local y muestra, en una fila cuando el ancho lo permite, código/nombre de caja, estado de sesión, inicial, esperado y acciones de movimientos/cierre. No repite el usuario conectado ni presenta selector de caja. Si existen cero o varias cajas activas, la UI informa la configuración inválida y no elige una arbitrariamente; la selección explícita se difiere a una evolución posterior sin eliminar el soporte backend para múltiples cajas. Sin sesión abierta, cobro y movimientos quedan deshabilitados y el foco es “Abrir caja”. Con sesión abierta, cualquier `CAJA` activo del local puede continuar y se priorizan pedidos pendientes/cobro; movimientos e historial quedan secundarios. La lista lateral de pedidos puede colapsarse: conserva una barra angosta con el control de expansión y etiquetas seleccionables por código de mesa, resaltando la selección vigente y permitiendo cambiar de pedido sin expandirla; admite desplazamiento vertical para listas largas, sin desplazamiento horizontal. Cierre presenta el resumen previo y la diferencia `contado - esperado` antes de habilitar la única confirmación mutante; `Volver` no cambia la sesión. Tras cerrar, la UI consume el snapshot persistido, permite imprimir manualmente el reporte interno de 80 mm y luego continuar sin sesión abierta.

Movimientos se presenta como una única grilla `Hora | Tipo | Importe | Motivo | Registrado por`. Las filas históricas quedan bloqueadas con fondo gris; el último histórico —o el estado vacío— ofrece `+`. Las filas nuevas muestran hora `—`, actor actual no editable y controles `+`/`−` al extremo derecho sin columna Acción. `Guardar` usa siempre la RPC batch, refresca histórico y efectivo esperado, limpia la edición y confirma el éxito; `Cancelar` descarta sólo filas nuevas. No existe aprobación administrativa para entradas/salidas.

Descuento muestra solicitante, autorización y motivo. Anulación muestra el administrador que la ejecutó, fecha/hora y motivo, sin solicitante/autorizador separados. En cobro normal, el objetivo es todo el saldo: se inicia con una línea de medio y `Agregar medio de pago` añade líneas con medio e importe, incluidos medios repetidos. La UI presenta los mismos conceptos en cobro total y parcial: saldo pendiente, importe a cobrar, importe distribuido entre medios y faltante/exceso; sólo habilita confirmación cuando la distribución coincide exactamente. `Cobrar una parte` abre un modo explícito con total menor al saldo y puede usar la misma composición de medios.

La confirmación única presenta pedido/mesa, total del acto, detalle de medios, propina, saldo posterior y aviso de liberación cuando corresponda. Sólo confirmar invoca la RPC; `Volver` no muta. Doble clic/request en curso queda bloqueado. Todo resync/Realtime invalida el borrador/modal y obliga a revisar el snapshot autoritativo. PRECUENTA, RECIBO INTERNO parcial y TICKET INTERNO final reutilizan la misma base visual térmica, identidad local, aviso no fiscal, acciones e impresión, conservando el contenido propio definido para cada documento. En el panel del pedido se priorizan, en este orden, encabezado, resumen financiero compacto sin repetir el saldo del bloque de cobro, cobro, historial de pagos y productos. Los productos permanecen colapsados por defecto y se expanden al activar la división; su selección sigue siendo una calculadora separada y nunca representa medios ni persistencia por líneas.

La interfaz de `ADMINISTRADOR` incorpora una campana visible con contador de entregas no leídas y una lista de hasta 50 notificaciones recientes. Aperturas y cierres con diferencia cero usan tratamiento informativo; los cierres con diferencia usan tratamiento de alerta ámbar o rojo y muestran diferencia y motivo. El administrador puede marcar una entrega o todas sus pendientes como leídas; ambas acciones actualizan únicamente su propio estado y persisten entre sesiones. No se muestran acciones de borrar/limpiar, `Aprobar`/`Rechazar` ni estado de aprobación.

## D13. Concurrencia y orden de bloqueos

Orden recomendado: `caja` → `sesion_caja` → `pedido` → `mesa`; operaciones que no necesitan todos omiten los posteriores. Descuento/anulación/cobro bloquean pedido; cierre bloquea sesión antes de agregar totales; cobro bloquea sesión antes de pedido. Restricciones únicas/idempotencia complementan locks.

Casos obligatorios: doble apertura/cierre/cobro, dos cobros sobre el mismo saldo, cobro vs cierre, cobro vs anulación, descuento vs cobro, reapertura vs primer cobro, dos parciales sobre el mismo saldo, error en una línea y reintento del cobro completo después de timeout. Todo error revierte cabecera, todas las líneas, auditoría, historial y estados juntos.

La generación de notificación y destinatarios participa en la misma transacción que apertura/cierre. Un fallo revierte dominio, auditoría y notificación; un reintento idempotente recupera el resultado existente y no vuelve a entregar el evento.

## D14. Riesgos y compatibilidad

| Riesgo | Tratamiento |
|---|---|
| Cambiar pago único afecta H5/H6/reportes/tests. | Migración explícita, RPC v2, regresión completa y conservación de semántica histórica. |
| Cierre concurrente con cobro. | Locks de sesión y precondición abierta en toda operación financiera. |
| Auditoría genérica difícil de consultar. | Eventos cerrados y campos principales normalizados. |
| PM-002 aún en transición. | DEV/Preview primero; ningún cambio remoto o cutover implícito. |
| Histórico sin sesión. | Permitir legacy identificable; nunca fabricar asociación retroactiva. |
| Confundir N medios con N cobros/documentos. | Cabecera `cobro` obligatoria para nuevas filas; lecturas y documentos agrupan por ella. |
| Migración de idempotencia por fila a idempotencia de cobro. | Nueva unicidad en cabecera; RPC anterior deja de ser vía de escritura una vez migrados consumidores. |
| Duplicar datos financieros o convertir avisos en un sistema genérico. | Referenciar auditoría/snapshots, persistir sólo evento/destinatario/lectura y limitar tipos a `APERTURA`/`CIERRE`. |

## D15. Trazabilidad

R01–R08 → D02–D05/D13; R09–R12 → D06–D07/D13; R13–R18 → D08–D09/D13; R19–R20 → D10; R21–R22 → D11–D12; R23 → D02–D05/D10–D13. Las tareas y pruebas conservan estos IDs.
