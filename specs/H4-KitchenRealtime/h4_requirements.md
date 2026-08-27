# MikuyApp — H4 Cocina en tiempo real: requisitos

## Estado del documento

**BORRADOR PARA REVISIÓN HUMANA.** H4 no ha iniciado construcción. Este documento, `design.md`, `tasks.md` y `test-plan.md` deben aprobarse explícitamente antes de implementar código o migraciones.

## Objetivo

Permitir que el rol `COCINA` reciba y procese en tiempo real los detalles enviados por los mozos, manteniendo PostgreSQL como fuente de verdad y reflejando los cambios en las pantallas del mozo sin recarga manual.

## Baseline heredado

- H1, H2 y H3 están cerrados, validados y aceptados.
- Un pedido vigente puede contener detalles simultáneamente en estados distintos y recibir nuevos detalles después del primer envío.
- `detalle_pedido.estado` admite `ABIERTO`, `ENVIADO`, `RECIBIDO_COCINA`, `EN_PREPARACION` y `LISTO`.
- La cabecera representa el estado agregado actual de todos sus detalles y puede recalcularse hacia un estado anterior cuando llegan agregados posteriores; ningún detalle ya procesado retrocede por ese recálculo.
- `pedido` y `detalle_pedido` poseen auditoría de creación/modificación obtenida desde `auth.uid()`.
- Un cambio exclusivamente operativo de cocina actualiza la auditoría del detalle, no la auditoría comercial `pedido.modificado_*`.
- No se agrega responsable a `mesa`; el creador se deriva por `mesa → pedido vigente → pedido.creado_por`.

## Requisitos funcionales y de calidad

| ID | Requisito | Prioridad |
|---|---|---|
| H4-R01 | Proveer `/cocina` como pantalla principal del rol `COCINA`, protegida por sesión, contexto válido, rol y local. | Must |
| H4-R02 | Mostrar en el tablero los detalles del local cuyo estado sea `ENVIADO`, `RECIBIDO_COCINA`, `EN_PREPARACION` o `LISTO`, agrupados por pedido/mesa, con producto, cantidad, observación, estado y antigüedad. Los detalles `ABIERTO` y los pedidos `ENTREGADO`, `PAGADO` o `ANULADO` no son visibles para cocina. | Must |
| H4-R03 | Ordenar el trabajo por la fecha/hora individual en que cada detalle pasó por primera vez a `ENVIADO`; el pedido/grupo más antiguo se presenta primero y los detalles conservan orden estable. | Must |
| H4-R04 | Permitir exclusivamente a `COCINA` las transiciones adyacentes y hacia adelante `ENVIADO → RECIBIDO_COCINA → EN_PREPARACION → LISTO`, aplicadas al detalle completo aunque `cantidad > 1`. | Must |
| H4-R05 | Ejecutar cada transición mediante una operación PostgreSQL transaccional que valide identidad, contexto, rol, local, estado esperado y pedido vigente; el cliente no recibe permiso directo para modificar `detalle_pedido.estado`. | Must |
| H4-R06 | Rechazar transiciones omitidas, inversas, de detalles `ABIERTO`, de otro local, de pedidos terminales o basadas en estado obsoleto, sin cambios parciales ni falso éxito. | Must |
| H4-R07 | Representar pedidos mixtos sin forzar todos sus detalles al mismo estado. Un detalle nuevo de un pedido ya visible se incorpora como trabajo independiente y nunca reabre ni retrocede detalles anteriores. | Must |
| H4-R08 | Derivar `pedido.estado` como el estado agregado actual de sus detalles: prevalece, en este orden, `ABIERTO`, `ENVIADO`, `RECIBIDO_COCINA`, `EN_PREPARACION` y, cuando todos están listos, `LISTO`. La cabecera puede volver a un estado anterior por agregados posteriores sin retroceder detalles ya procesados. | Must |
| H4-R09 | Establecer `mesa.estado = 'PEDIDO_LISTO'` solo cuando el pedido vigente tenga al menos un detalle y todos sus detalles estén `LISTO`; si se incorpora posteriormente cualquier detalle no listo, devolver la mesa a `OCUPADA`. | Must |
| H4-R10 | Actualizar `detalle_pedido.modificado_por/modificado_en` con el actor de cocina; conservar los campos de creación y `pedido.modificado_por/modificado_en` ante cambios exclusivamente operativos. Registrar historial únicamente cuando la cabecera cambie realmente. | Must |
| H4-R11 | Recibir por Supabase Realtime inserciones y actualizaciones relevantes sin refresh, tanto en cocina como en la vista del mozo; evitar duplicados y conservar PostgreSQL como fuente autoritativa. | Must |
| H4-R12 | Realizar carga inicial, escucha, resincro posterior, recuperación de conexión y resincro completo ante reconexión o duda sobre el orden de eventos. | Must |
| H4-R13 | Mantener la UI segura ante latencia, doble tap y dos sesiones: bloqueo local por detalle durante la mutación, feedback visible, recuperación del estado confirmado y aviso comprensible ante conflicto. | Must |
| H4-R14 | Ofrecer una experiencia táctil y responsive, priorizando tablet de cocina en vertical y horizontal, sin depender únicamente del color y con objetivos principales de al menos 44 px. | Must |

## Reglas de negocio

### Visibilidad y estados

- Cocina ve únicamente `ENVIADO`, `RECIBIDO_COCINA`, `EN_PREPARACION` y `LISTO` del mismo local.
- `ABIERTO` pertenece a la preparación comercial del mozo y permanece fuera del tablero de cocina hasta ser enviado.
- `LISTO` permanece visible en una sección de solo lectura durante H4; la entrega pertenece al hito posterior.
- No existen estados por unidad: una transición afecta la cantidad completa de la línea.

### Antigüedad

Para distinguir correctamente el primer envío de los agregados posteriores, queda aprobada la incorporación de `detalle_pedido.enviado_en timestamptz`, que conserva el instante individual e inmutable de su primera transición a `ENVIADO`, obtenido desde PostgreSQL. No se usa `pedido.enviado_en` para ordenar detalles posteriores ni `detalle_pedido.modificado_en`, porque este último cambia en cada avance de cocina.

### Cabecera y mesa

- El estado de la cabecera es el resumen agregado actual, no una sustitución de los estados individuales.
- Si existe algún `ABIERTO`, la cabecera es `ABIERTO`; sin abiertos, si existe algún `ENVIADO`, es `ENVIADO`; sin anteriores, si existe algún `RECIBIDO_COCINA`, es `RECIBIDO_COCINA`; sin anteriores, si existe algún `EN_PREPARACION`, es `EN_PREPARACION`; y solo es `LISTO` cuando todos los detalles existentes están `LISTO` y existe al menos uno.
- La cabecera puede volver a un estado anterior cuando se agrega un nuevo detalle. Ese recálculo no cambia ni reabre detalles previamente procesados y cada cambio real continúa generando `historial_estado`.
- La mesa está `PEDIDO_LISTO` únicamente mientras todos los detalles existentes estén `LISTO`; de otro modo permanece o vuelve a `OCUPADA` dentro del flujo vigente.

## Fuera de alcance

- Entrega y transición a `ENTREGADO`.
- Caja, pago, impresión, reportes, inventario y administración.
- Modificación o anulación de platos enviados.
- Historial completo por transición de detalle mediante una tabla adicional.
- Realtime como sustituto de PostgreSQL o polling periódico.
- Notificaciones push, sonido obligatorio, impresoras o nuevas librerías de infraestructura.

## Criterios de aprobación del Spec

La construcción solo puede comenzar después de aprobar humanamente los cuatro documentos. Dentro del borrador ya quedan resueltas las decisiones sobre timestamp individual de envío, derivación agregada de cabecera, retorno `PEDIDO_LISTO → OCUPADA` ante agregados posteriores y permanencia visual de detalles `LISTO`; la aprobación pendiente corresponde al Spec completo, no a redefinir esas cuatro reglas.
