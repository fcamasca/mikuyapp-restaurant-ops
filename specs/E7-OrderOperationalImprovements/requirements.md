# MikuyApp — Evolución 7 — Mejoras operativas de pedidos: requisitos

## 1. Estado, objetivo y fuente de verdad

**Estado: SPEC MODE — BORRADOR PENDIENTE DE APROBACIÓN HUMANA (23/09/2026).** No se ha iniciado la construcción. Este paquete no contiene `acceptance.md`, no autoriza migraciones, cambios de RPC productivas, cambios de componentes React ni despliegues. Las decisiones DH-01–DH-04 fueron tomadas y se registran en la sección 10. La construcción sólo podrá comenzar después de la aprobación explícita de `requirements.md`, `design.md`, `tasks.md` y `test-plan.md`.

Fuente principal de alcance: `docs/PLAN_MVP.md`, sección 15, **Evolución 7 — Mejoras operativas de pedidos**. Baseline verificada en la rama `main` (`d1f0517`), sin cambios locales al iniciar el Spec Mode, con H1–H6, PM-001 y E1 (incluido el correctivo E1-T18) cerrados y aceptados. PM-002 permanece `TRANSITIONING`: construcción y verificación se realizan en local/DEV; este spec no toca PROD.

Objetivo: mejorar la operación diaria de pedidos sin alterar las reglas aprobadas de H3, H4, H5 y E1, incorporando:

1. productos que no requieren cocina;
2. recepción completa de un pedido en cocina con una sola acción;
3. cancelación de productos por el mozo antes de iniciar preparación;
4. trazabilidad de cancelaciones y cambios de estado de detalle;
5. consistencia entre detalle, pedido y mesa, incluida la corrección de HZ-01 (edición y retiro de detalles `ABIERTO` con el mismo orden transaccional, conservando las capacidades H3);
6. impresión opcional de comandas como apoyo al flujo digital.

PostgreSQL permanece como autoridad de estados, totales, permisos y trazabilidad. Supabase Realtime sólo transporta señales para recargar snapshots autoritativos.

## 2. Baseline verificable y brechas

| Área | Estado actual verificado en el repositorio | Brecha de E7 |
|---|---|---|
| `producto` | `id, local_id, categoria_id, codigo, nombre, precio, activo, creado_en`. `authenticated` tiene `INSERT/UPDATE` por columna sólo para `codigo, nombre, precio, categoria_id, activo` (y `local_id` al insertar); RLS limita mutaciones a `ADMINISTRADOR` del local. | No existe forma de indicar si un producto requiere cocina. |
| `detalle_pedido` | `estado ∈ {ABIERTO, ENVIADO, RECIBIDO_COCINA, EN_PREPARACION, LISTO}`; `enviado_en` obligatorio fuera de `ABIERTO`; `precio_unitario` es snapshot; auditoría `creado_*`/`modificado_*` por trigger; no existe estado `ANULADO`/`CANCELADO` de detalle. | No existe snapshot de tratamiento de cocina ni cancelación trazable de detalles enviados. |
| Alta/consolidación | `agregar_detalle_pedido` (versión E1-T18) copia precio, crea `ABIERTO` y consolida sólo `ABIERTO` con mismo producto y observación equivalente. | Debe copiar también la condición de cocina y no consolidar tratamientos distintos. |
| Envío | `enviar_pedido_cocina` (versión H5-T02) cambia todos los `ABIERTO → ENVIADO` con un mismo `enviado_en`, fija `pedido.enviado_en` en el primer envío y deriva cabecera/mesa. | Todo detalle enviado entra hoy a la cola de cocina. |
| Cocina | `obtener_tablero_cocina()` devuelve detalles `ENVIADO…LISTO` de pedidos `ABIERTO…LISTO`; `actualizar_estado_detalle_cocina` procesa un detalle por llamada con estado esperado y locks `pedido → detalle`. | No hay recepción completa; los productos sin cocina aparecerían en el tablero. |
| Estado agregado | `sincronizar_estado_operativo_pedido` deriva `pedido.estado` por prioridad `ABIERTO > ENVIADO > RECIBIDO_COCINA > EN_PREPARACION > LISTO` y mesa `OCUPADA`/`PEDIDO_LISTO`; rechaza pedidos sin detalles. | Debe cubrir la cancelación, incluido el caso en que no queden detalles. |
| Edición y retiro H3 | El mozo edita cantidad/observación de un detalle `ABIERTO` mediante `UPDATE` directo (grant por columna + RLS, con verificación optimista de valores esperados en el cliente) y lo retira mediante `DELETE` directo; ninguno invoca la derivación de estado ni bloquea primero el pedido. | Hallazgo **HZ-01** (sección 11), corrección aprobada (DH-01). |
| Historial | `historial_estado` registra sólo transiciones de cabecera de `pedido`. `detalle_pedido.modificado_*` conserva únicamente el último cambio. | No existe historial por detalle ni registro de cancelaciones. |
| Impresión | Sólo caja imprime precuenta/ticket/cierre con `window.print()` y CSS de 80 mm (`print-overlay`/`print-document`). No existe comanda ni objeto de impresión en base de datos. | Comanda opcional de cocina. |
| Realtime | Publicación limitada a `detalle_pedido`, `pedido`, `mesa`; el frontend escucha `INSERT`/`UPDATE` como señal y recarga snapshots. | Nuevas tablas no requieren publicarse (ver diseño). |
| Errores | Convención E1-R25: conflictos funcionales con `PT409`; `40001` reservado. | Toda RPC nueva o modificada debe respetarla. |

## 3. Actores y permisos

| Actor | Capacidades en E7 | Restricciones |
|---|---|---|
| `ADMINISTRADOR` | Define y modifica si un producto de su local requiere cocina (alta, edición). | No cancela detalles, no recibe en cocina, no imprime comandas en E7. No hereda capacidades de `MOZO` ni `COCINA`. |
| `MOZO` | Agrega productos (con snapshot automático), edita y retira detalles `ABIERTO` con las mismas capacidades de H3, envía, visualiza qué productos no requieren cocina, cancela detalles permitidos con motivo y consulta cancelaciones de su pedido. | Sólo pedidos vigentes de su local. No modifica el estado de detalles, precio ni la condición de cocina. |
| `COCINA` | Visualiza sólo trabajo de cocina, recibe un pedido completo, continúa el procesamiento individual, visualiza cancelaciones de su cola y registra la impresión o reimpresión de comandas. | No cancela, no cambia precios, cantidades ni condición de cocina; no cobra. |
| `CAJA` | Sin cambios funcionales. Continúa viendo consumo/total autoritativo, que ya excluye líneas canceladas. | No interviene en cancelación, recepción ni comandas. |
| `anon` / otro local | Ninguna. | Sin lectura ni ejecución. |

## 4. Requisitos funcionales

### 4.1 Productos que no requieren cocina

| ID | Requisito | Prioridad |
|---|---|---|
| E7-R01 | El `ADMINISTRADOR` podrá definir, al crear o editar un producto de su local, si **requiere preparación en cocina**. El valor por defecto será *requiere cocina*, de modo que todo producto existente y todo producto creado sin indicación explícita conserve el comportamiento aprobado. La carta administrativa mostrará la condición de cada producto. | Must |
| E7-R02 | Cada detalle de pedido conservará como snapshot la condición de cocina vigente del producto en el momento en que el detalle se crea. Un cambio posterior en el catálogo no alterará el tratamiento de detalles ya registrados, cualquiera sea su estado. Los detalles existentes antes de E7 se tratarán como *requiere cocina*. | Must |
| E7-R03 | La consolidación de detalles `ABIERTO` aprobada en H3 sólo agrupará líneas con mismo producto, observación equivalente **y misma condición de cocina**. | Must |
| E7-R04 | Al enviar un pedido, en la misma operación atómica: los detalles `ABIERTO` que requieren cocina pasarán a `ENVIADO` (comportamiento vigente) y los detalles `ABIERTO` que no requieren cocina pasarán directamente a `LISTO`. Ambos grupos registrarán el mismo instante de envío. No se crea ningún estado nuevo. | Must |
| E7-R05 | Un detalle que no requiere cocina nunca aparecerá en el tablero de cocina, nunca formará parte de una recepción completa, nunca generará comanda y nunca admitirá transiciones de cocina. | Must |
| E7-R06 | El mozo verá identificados los productos que no requieren cocina en la carta y en el pedido; tras el envío los verá como listos para servir. | Must |

### 4.2 Pedidos mixtos y estado agregado

| ID | Requisito | Prioridad |
|---|---|---|
| E7-R07 | Un pedido podrá contener simultáneamente detalles que requieren cocina y detalles que no la requieren. Cada detalle conservará su propio estado. | Must |
| E7-R08 | El estado agregado de `pedido` y el estado de `mesa` seguirán la regla aprobada en H4/H5 aplicada sobre **todos** los detalles existentes: el pedido sólo será `LISTO` y la mesa `PEDIDO_LISTO` cuando exista al menos un detalle y todos estén `LISTO`. Un pedido compuesto sólo por productos sin cocina quedará `LISTO` al enviarse y podrá entregarse con el flujo H5 vigente. | Must |

### 4.3 Recepción completa en cocina

| ID | Requisito | Prioridad |
|---|---|---|
| E7-R09 | `COCINA` podrá recibir un pedido completo con una sola acción. La operación procesará únicamente los detalles del pedido que en ese momento estén `ENVIADO` y requieran cocina, cambiándolos a `RECIBIDO_COCINA`. Detalles `RECIBIDO_COCINA`, `EN_PREPARACION`, `LISTO` y los que no requieren cocina no se modificarán. | Must |
| E7-R10 | La recepción completa es una facilidad adicional: el procesamiento individual por detalle de H4 se conserva sin cambios y, después de la recepción completa, cada detalle continuará su avance individual. | Must |
| E7-R11 | La recepción completa será segura ante doble clic, reintentos y dos sesiones de cocina: una repetición sin detalles `ENVIADO` aplicables terminará sin cambios y sin error; dos ejecuciones concurrentes no producirán transiciones ni historial duplicados; un conflicto no dejará efectos parciales. | Must |

### 4.4 Cancelación de productos por el mozo

| ID | Requisito | Prioridad |
|---|---|---|
| E7-R12 | El `MOZO` podrá cancelar un detalle de un pedido vigente de su local mientras la preparación no haya iniciado. **Estados que permiten cancelar:** `ENVIADO` y `RECIBIDO_COCINA`. **Estados que impiden cancelar:** `EN_PREPARACION` y `LISTO`. Un detalle `ABIERTO` no se cancela: conserva el retiro aprobado en H3. Un producto que no requiere cocina queda `LISTO` al enviarse y, por tanto, no puede cancelarse una vez enviado (DH-03); mientras permanezca `ABIERTO` se retira con el retiro H3. Pedidos `PAGADO`, `ANULADO` o con cualquier pago registrado no admiten cancelación. | Must |
| E7-R13 | La cancelación afectará siempre la línea completa: si la cantidad es mayor a uno se cancelan todas sus unidades; no existe cancelación parcial ni división de detalles (DH-04). Exigirá un motivo no vacío; la interfaz podrá ofrecer motivos frecuentes y texto libre. | Must |
| E7-R14 | Tras la cancelación, en la misma transacción: la línea dejará de formar parte del pedido y del total autoritativo; el estado de `pedido` y de `mesa` se recalculará con la regla vigente; si el pedido queda sin detalles volverá a `ABIERTO` vacío con la mesa `OCUPADA`, habilitando las acciones H3 existentes (agregar productos o liberar mesa). | Must |
| E7-R15 | La decisión de permitir o bloquear se tomará sobre el estado persistido en PostgreSQL al momento de ejecutar, no sobre la pantalla del mozo. Ante una acción simultánea de cocina, sólo una operación confirmará: si cocina inicia preparación primero, la cancelación se rechaza como conflicto; si la cancelación confirma primero, la acción de cocina se rechaza como conflicto y cocina recarga su tablero. | Must |
| E7-R16 | Un reintento de una cancelación ya confirmada devolverá el mismo resultado sin duplicar trazabilidad ni recálculos. | Must |
| E7-R17 | Cocina visualizará, mientras el pedido permanezca en su flujo, las cancelaciones de productos que ya había recibido en su cola, para no preparar productos cancelados. El mozo visualizará las líneas canceladas de su pedido como información de sólo lectura. | Must |
| E7-R18 | La cancelación por mozo es distinta de la anulación completa de pedidos por `ADMINISTRADOR` aprobada en E1 y no la modifica. | Must |

### 4.5 Trazabilidad y consistencia

| ID | Requisito | Prioridad |
|---|---|---|
| E7-R19 | Toda transición de estado de un detalle (envío a cocina, envío directo a `LISTO` sin cocina, transición individual de cocina y recepción completa) y toda cancelación quedarán registradas de forma inmutable con pedido, detalle, producto, estado anterior, estado nuevo (o cancelación), tipo de operación, actor y fecha/hora de servidor. La cancelación conservará además cantidad, precio unitario, observación y motivo. | Must |
| E7-R20 | `historial_estado` continuará registrando sólo cambios reales de cabecera de pedido, incluidos los originados por productos sin cocina y por cancelaciones. | Must |
| E7-R21 | Las invariantes de estado, condición de cocina, totales, permisos y trazabilidad se garantizarán en PostgreSQL. El cliente no podrá modificar directamente `estado`, `requiere_cocina` de detalle, ni el historial. | Must |
| E7-R22 | Los conflictos funcionales de las operaciones nuevas o modificadas usarán `PT409`; ninguna operación de E7 usará `40001` (E1-R25). | Must |
| E7-R32 | **Corrección HZ-01.** Al retirar un detalle `ABIERTO`, en la misma transacción se recalcularán el estado de `pedido` y de `mesa` con la regla vigente. Un pedido nunca quedará con cabecera o mesa distintas de las derivadas de sus detalles después de un retiro; en particular, un pedido `ENTREGADO` reabierto cuyo producto nuevo se retira volverá a `LISTO`/`PEDIDO_LISTO` y podrá entregarse otra vez. | Must |
| E7-R33 | La edición de cantidad/observación y el retiro de detalles `ABIERTO` se ejecutarán mediante operaciones de servidor con el mismo orden transaccional que el envío, la cocina y la cancelación, y el cliente dejará de modificarlos o eliminarlos directamente. Se conservan exactamente las capacidades aprobadas en H3: cantidad entera ≥ 1, observación opcional (vacía equivale a sin observación), rechazo como conflicto si el detalle ya no está `ABIERTO` o si sus valores cambiaron desde que el mozo los vio, sin consolidación por edición y sin cambios sobre detalles enviados. No se agrega funcionalidad nueva. | Must |

### 4.6 Impresión opcional de comandas

| ID | Requisito | Prioridad |
|---|---|---|
| E7-R23 | Cada envío que incluya al menos un detalle que requiere cocina generará, en la misma transacción del envío, **una comanda** inmutable asociada al pedido, con número correlativo por pedido, mesa, mozo que envió, fecha/hora y las líneas enviadas a cocina en ese envío (producto, cantidad, observación). Un envío sin detalles de cocina no genera comanda. | Must |
| E7-R24 | Los productos agregados y enviados posteriormente generarán una nueva comanda que contendrá sólo esas líneas nuevas; nunca se reimprimen automáticamente líneas de comandas anteriores. | Must |
| E7-R25 | Cocina dispondrá de cada comanda con las acciones manuales `Imprimir` y `Reimprimir` desde una sesión `COCINA`. La impresión usará la impresión estándar del navegador (`window.print()`) en formato de 80 mm hacia cualquier impresora accesible y configurada en el sistema operativo del dispositivo. Es opcional porque ninguna operación depende de imprimir, no porque exista una configuración; no reemplaza la tablet ni las transiciones digitales. | Must |
| E7-R26 | Sólo podrá registrarse una primera solicitud de impresión por comanda; toda solicitud posterior será una reimpresión. Si otra sesión ya registró la primera solicitud, un nuevo intento de primera impresión se rechaza como conflicto y se ofrece reimpresión explícita. El sistema registra solicitudes de impresión, no confirma la salida física del papel, que el navegador no puede verificar. La reimpresión estará disponible mientras el pedido siga en el flujo de cocina y se identificará en el papel como copia. | Must |
| E7-R27 | Se registrará quién y cuándo realizó la primera solicitud de impresión, la cantidad de solicitudes de impresión y quién y cuándo solicitó la última reimpresión. | Must |
| E7-R28 | Imprimir o reimprimir no cambiará el estado de detalles, pedido ni mesa. Si la impresora no está disponible o la impresión falla, el flujo digital continúa sin bloqueo y el usuario podrá reimprimir cuando la impresora vuelva a estar disponible. | Must |

### 4.7 Seguridad, Realtime y regresión

| ID | Requisito | Prioridad |
|---|---|---|
| E7-R29 | Toda operación y lectura nueva validará en servidor identidad, perfil activo, rol y `local_id`; `anon` no leerá ni ejecutará nada de E7; no se confiará en `local_id`, actor, estado, precio ni condición de cocina enviados por el cliente. | Must |
| E7-R30 | Los cambios de E7 se reflejarán entre dispositivos mediante las señales Realtime existentes y la recarga de snapshots autoritativos, tolerando eventos duplicados, desordenados y reconexiones. | Must |
| E7-R31 | Los flujos aprobados de H3, H4, H5 y E1 continuarán funcionando para productos que requieren cocina y para pedidos sin cancelaciones exactamente como fueron aceptados. | Must |

## 5. Estados y transiciones

No se agregan estados. Dominios vigentes:

- `detalle_pedido.estado`: `ABIERTO`, `ENVIADO`, `RECIBIDO_COCINA`, `EN_PREPARACION`, `LISTO`.
- `pedido.estado`: `ABIERTO`, `ENVIADO`, `RECIBIDO_COCINA`, `EN_PREPARACION`, `LISTO`, `ENTREGADO`, `PAGADO`, `ANULADO`.
- `mesa.estado`: `LIBRE`, `OCUPADA`, `PEDIDO_LISTO`, `PENDIENTE_PAGO`.

### 5.1 Transiciones de detalle permitidas

| Condición de cocina (snapshot) | Transición | Actor | Operación |
|---|---|---|---|
| Requiere cocina | `ABIERTO → ENVIADO` | `MOZO` | Envío (vigente) |
| Requiere cocina | `ENVIADO → RECIBIDO_COCINA` | `COCINA` | Individual (vigente) o recepción completa (nueva) |
| Requiere cocina | `RECIBIDO_COCINA → EN_PREPARACION → LISTO` | `COCINA` | Individual (vigente) |
| Requiere cocina | `ENVIADO` o `RECIBIDO_COCINA` → *cancelado* (la línea deja de existir en el pedido) | `MOZO` | Cancelación (nueva) |
| No requiere cocina | `ABIERTO → LISTO` | `MOZO` | Envío (nuevo comportamiento) |
| Cualquiera | `ABIERTO` → `ABIERTO` (cantidad/observación) | `MOZO` | Edición H3 (misma capacidad; ahora vía operación de servidor, E7-R33) |
| Cualquiera | `ABIERTO` → retirado | `MOZO` | Retiro H3 (misma capacidad; ahora vía operación de servidor con recálculo, E7-R32/R33) |

Toda otra transición, en particular hacia atrás, omitida, sobre detalles sin cocina en estados de cocina o sobre pedidos terminales, queda prohibida.

### 5.2 Matriz de cancelación

| Estado del detalle | ¿Cancelable por mozo? | Motivo |
|---|---|---|
| `ABIERTO` | No aplica | Se usa el retiro H3; todavía no se envió. |
| `ENVIADO` | Sí | Cocina aún no lo recibió. |
| `RECIBIDO_COCINA` | Sí | Cocina lo conoce, pero no inició preparación. Cocina verá la cancelación (E7-R17). |
| `EN_PREPARACION` | No | La preparación inició. |
| `LISTO` | No | El producto está listo; incluye productos sin cocina ya enviados (DH-03). |

En todos los casos permitidos se cancela la línea completa, cualquiera sea su cantidad (DH-04).

## 6. Reglas de negocio de pedidos mixtos (ejemplos verificables)

| Caso | Detalles tras el envío | Pedido | Mesa |
|---|---|---|---|
| Sólo ceviche | ceviche `ENVIADO` | `ENVIADO` | `OCUPADA` |
| Sólo bebida | bebida `LISTO` | `LISTO` | `PEDIDO_LISTO` |
| Ceviche + bebida | ceviche `ENVIADO`, bebida `LISTO` | `ENVIADO` | `OCUPADA` |
| Ceviche pasa a `LISTO` | ambos `LISTO` | `LISTO` | `PEDIDO_LISTO` |
| Pedido `ENTREGADO` + nueva bebida enviada | anteriores `LISTO`, bebida `LISTO` | `LISTO` (requiere nueva entrega H5) | `PEDIDO_LISTO` |
| Ceviche `ENVIADO` cancelado, bebida `LISTO` | bebida `LISTO` | `LISTO` | `PEDIDO_LISTO` |
| Único ceviche `RECIBIDO_COCINA` cancelado | ninguno | `ABIERTO` vacío | `OCUPADA` |

## 7. Concurrencia y reintentos relevantes

- Recepción completa vs recepción completa, vs transición individual, vs nuevo envío del mozo y vs cancelación: serialización por pedido; el resultado final es coherente y sin duplicados.
- Cancelación vs `EN_PREPARACION`: exactamente uno gana (E7-R15).
- Cancelación vs anulación administrativa E1: si la anulación confirma primero, la cancelación se rechaza.
- Cancelación repetida o reintentada: idempotente (E7-R16).
- Edición o retiro de un detalle `ABIERTO` vs envío del mozo desde otro dispositivo: serialización por pedido sin interbloqueos; si el envío confirma primero, la edición/retiro se rechaza como conflicto; si la edición/retiro confirma primero, el envío procesa el estado resultante.
- Primera solicitud de impresión simultánea desde dos sesiones: sólo una se registra como primera; la otra se rechaza y puede solicitarse como reimpresión (E7-R26).
- Doble envío del mozo: una sola comanda por lote enviado; el segundo envío sin detalles `ABIERTO` no genera comanda.

## 8. Restricciones

- No crear estados nuevos de detalle, pedido ni mesa.
- No incorporar backend adicional, servidor/agente/bridge de impresión, servicios de impresión específicos, ESC/POS directo, impresión silenciosa, hardware adicional ni integraciones externas.
- No agregar configuración por dispositivo ni almacenamiento del navegador para la impresión.
- No modificar reglas aceptadas de H3, H4, H5 y E1 fuera de lo estrictamente necesario para E7 y de las decisiones aprobadas de la sección 10.
- No cambiar el formato de exportaciones H6 ni la carga inicial de maestras.
- No incorporar nuevas tablas a la publicación Realtime salvo necesidad demostrada durante construcción, documentada para aprobación.

## 9. Alcance y fuera de alcance

**Dentro:** requisitos E7-R01–E7-R33, incluida la corrección aprobada de HZ-01.

**Fuera:** solicitud de cuenta del mozo a caja y su atención por caja (se analizará por separado); nuevos mecanismos de división de cuenta; inventario, recetas e insumos; facturación electrónica; cancelación administrativa u otras anulaciones de detalle; cancelación parcial de unidades o división de líneas enviadas (DH-04); cancelación de productos en preparación o listos, incluidos productos sin cocina ya enviados (DH-03); nuevas capacidades de edición o retiro distintas de las aprobadas en H3; aviso impreso de cancelación; comandas para caja o bar; métricas y analítica (E8); jornada operativa (E9); multirol/multilocal (E6); cambios de PM-002; cambios de arquitectura.

## 10. Decisiones tomadas

Las decisiones DH-01–DH-04 quedaron resueltas por el responsable del proyecto el 23/09/2026 y forman parte del alcance de este spec. No quedan decisiones funcionales pendientes para iniciar la construcción una vez aprobado el Spec.

| ID | Decisión | Resultado |
|---|---|---|
| DH-01 | Corrección de HZ-01. | **Aprobada e incluida en E7.** Además del retiro, la edición de detalles `ABIERTO` se normaliza mediante operación de servidor para mantener un único orden transaccional de locks. Se conservan exactamente las capacidades H3 (editar cantidad/observación y retirar un borrador `ABIERTO`); el objetivo es consistencia y concurrencia, no funcionalidad nueva (E7-R32, E7-R33). |
| DH-02 | Impresión de comandas. | **Resuelta sin infraestructura nueva.** Impresión manual desde una sesión `COCINA` con `window.print()` hacia cualquier impresora accesible y configurada por el sistema operativo del dispositivo. No se definen servicios Android, bridges, agentes locales, ESC/POS directo ni hardware adicional. La compatibilidad física se comprueba en la validación humana. |
| DH-03 | Cancelación de productos sin cocina ya enviados. | **No se permite.** Pasan a `LISTO` al enviarse y el mozo no puede cancelarlos; mientras están `ABIERTO` se usa el retiro H3. |
| DH-04 | Cancelación parcial de unidades. | **No se permite.** La cancelación afecta la línea completa aunque su cantidad sea mayor a uno; no se dividen detalles ni se agregan estados. |

## 11. Hallazgos y contradicciones detectados en la inspección

| ID | Hallazgo | Tratamiento |
|---|---|---|
| HZ-01 | Inspección estática: el retiro de un detalle `ABIERTO` (H3-D05) es un `DELETE` directo sin derivación posterior. Si un pedido `ENTREGADO` se reabre con un producto (cabecera `ABIERTO`, mesa `OCUPADA`) y luego ese producto se retira, todos los detalles quedan `LISTO` pero la cabecera permanece `ABIERTO` y la mesa `OCUPADA`: no puede entregarse ni cobrarse hasta otra operación que derive estados. | **Corrección aprobada (DH-01)** e incluida como E7-R32/E7-R33. La construcción debe reproducirlo primero (E7-T05B). La misma causa (mutación directa del detalle sin bloquear primero el pedido) aplica a la edición: su trigger de auditoría actualiza `pedido` después de bloquear la fila del detalle, orden inverso al de `enviar_pedido_cocina`. |
| HZ-02 | Interacción E1/H5 fuera de E7: `fn_resolver_total_pedido` usa el `total_neto` del snapshot de un descuento `AUTORIZADO`; si un pedido con descuento autorizado se reabre y recibe productos antes del primer pago, esos productos no incrementarían el neto cobrable. | Fuera de alcance. Se informa para análisis independiente; E7 no lo modifica. La cancelación sólo actúa sobre detalles no `LISTO`, por lo que no agrava el caso. |
| HZ-03 | `docs/PLAN_MVP.md` §4.8 y §5 declaran fuera del MVP la “impresión automática de comandas en cocina”. | No es contradicción: son secciones históricas del MVP; E7 incorpora impresión **opcional y manual** sólo en su propia sección. |
| HZ-04 | El plan y el README indican que E1 está aceptada pero pendiente de despliegue a producción. | Dependencia: E7 se construye sobre las migraciones E1 (incluida E1-T18) y no podrá desplegarse antes que E1. |

## 12. Condición de construcción y cierre

- La construcción avanza con **pruebas focalizadas por tarea** y concentra la validación integral en la fase final (ver `tasks.md` y `test-plan.md`).
- E7 sólo podrá considerarse cerrada después de construcción, ejecución completa del plan de pruebas final, pruebas humanas y creación/aprobación posterior de `acceptance.md`. Pruebas automatizadas exitosas no sustituyen la validación humana.

## 13. Trazabilidad

La matriz `Requirement → Design → Task → Test` se mantiene en `tasks.md` (sección 5). Cada requisito E7-R01–E7-R33 tiene al menos una decisión E7-Dxx, una tarea E7-Txx y un escenario E7-TPxx/E7-THxx.
