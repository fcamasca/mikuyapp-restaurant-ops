# MikuyApp — H3 Flujo del mozo: diseño

## H3-D01 — Modelo vigente y cambio mínimo

El modelo real usa `mesa`, `pedido`, `detalle_pedido` e `historial_estado`. H2 dejó las tablas transaccionales sin acceso para `authenticated`. H3 añade a `detalle_pedido` un campo `estado text not null default 'ABIERTO'`, restringido a `ABIERTO`, `ENVIADO`, `RECIBIDO_COCINA`, `EN_PREPARACION` y `LISTO`, y un índice `(pedido_id, estado)`. No se incorpora `ANULADO` como estado de detalle.

PostgreSQL garantiza un único pedido vigente por mesa mediante un índice único parcial sobre `pedido(mesa_id)` para `ABIERTO`, `ENVIADO`, `RECIBIDO_COCINA`, `EN_PREPARACION`, `LISTO` y `ENTREGADO`. `PAGADO` y `ANULADO` quedan fuera por ser terminales. `PENDIENTE_PAGO` pertenece a `mesa` y no participa como estado de pedido.

## H3-D02 — Tablero y navegación táctil

`/mozo/mesas` presenta cards de mesas activas con estado, total del pedido vigente, filtro por estado y orden ascendente/descendente. Una mesa `LIBRE` ofrece “Tomar pedido”; una mesa con pedido vigente ofrece “Ver pedido”. La carta usa cards de productos activos, agrupadas y filtrables por categoría. En celular se usa una columna y barra de revisión accesible; en tablet, grillas y revisión lateral cuando exista espacio.

## H3-D03 — Creación y recuperación del pedido

Una operación transaccional de servidor valida `auth.uid()`, contexto `MOZO`, local, mesa activa/libre y ausencia de otro pedido vigente; crea la cabecera `ABIERTO`, registra el historial inicial y cambia la mesa a `OCUPADA`. La restricción única resuelve carreras entre dispositivos. Para una mesa ocupada, el servicio recupera el único pedido vigente y todos sus detalles; nunca crea otro pedido para agregados posteriores.

## H3-D04 — Alta segura de detalles

Se incorpora una única función `SECURITY DEFINER`, por ejemplo `public.h3_agregar_detalle(p_pedido_id, p_producto_id, p_cantidad, p_observacion)`. La función obtiene internamente `auth.uid()`, valida rol `MOZO`, local, pedido vigente, producto y categoría activos, cantidad positiva y observación válida. Consulta `producto.precio` en PostgreSQL, copia ese valor a `precio_unitario` e inserta el detalle forzando `estado = 'ABIERTO'`.

El cliente no envía `precio_unitario` ni `estado` como parte del contrato. `authenticated` no recibe privilegio `INSERT` directo sobre `detalle_pedido`; solo `EXECUTE` sobre esta función. Así, un payload alternativo no puede falsear precio ni crear un detalle `ENVIADO`.

## H3-D05 — Modificación y retiro seguro de detalles abiertos

Para evitar funciones innecesarias, cantidad y observación se modifican con `UPDATE` directo limitado por privilegios de columna exclusivamente a `(cantidad, observacion)`. La política RLS `USING` exige que el detalle existente sea `ABIERTO`, pertenezca a un pedido vigente del mismo local y que el actor sea `MOZO`; `WITH CHECK` conserva esas condiciones y valida cantidad/observación mediante constraints. No se concede `UPDATE` sobre `precio_unitario`, `estado`, `pedido_id` ni `producto_id`.

El retiro usa `DELETE` directo con una política equivalente y solo para detalles `ABIERTO`. No representa anulación histórica. Los detalles `ENVIADO` o posteriores no pueden modificarse ni retirarse. La seguridad reside en privilegios, RLS y constraints de PostgreSQL, no en controles del frontend.

## H3-D06 — Total y revisión

El total se calcula desde persistencia como `sum(cantidad * precio_unitario)` de todos los detalles existentes del pedido; no se guarda una segunda fuente de verdad. La revisión separa visualmente detalles `ABIERTO` (“por enviar”) y los demás (“ya solicitados”), manteniendo un único total.

## H3-D07 — Envío transaccional e idempotencia

`public.h3_enviar_pedido(p_pedido_id bigint)` es `SECURITY DEFINER`, propiedad de `postgres`, con `search_path` fijo y `EXECUTE` solo para `authenticated`. Valida identidad, rol `MOZO`, local y pedido vigente; bloquea la cabecera con `FOR UPDATE`; selecciona exclusivamente sus detalles `ABIERTO`; y, en la misma transacción, cambia únicamente esos detalles `ABIERTO → ENVIADO`.

Si la cabecera está `ABIERTO`, por tratarse del primer envío, la función la cambia a `ENVIADO`, fija `pedido.enviado_en` con la fecha del primer envío e inserta el cambio de cabecera en `historial_estado`. Si la cabecera ya está `ENVIADO`, `RECIBIDO_COCINA`, `EN_PREPARACION`, `LISTO` o `ENTREGADO`, la función no modifica ni retrocede su estado y no sobrescribe `enviado_en`; solo envía los nuevos detalles abiertos. El envío de detalles posteriores no genera un cambio ficticio de cabecera en `historial_estado`.

El cliente no tiene privilegio directo para actualizar `detalle_pedido.estado`. Si no existen detalles `ABIERTO`, la función devuelve un resultado sin cambios y no crea historial duplicado. Un error revierte cabecera, detalles e historial conjuntamente.

## H3-D08 — Agregados posteriores

Al volver a un pedido vigente se muestran primero sus detalles persistidos. “Agregar productos” llama nuevamente a `h3_agregar_detalle`; las nuevas líneas pertenecen al mismo pedido, nacen `ABIERTO` y no se envían automáticamente. Un nuevo llamado a `h3_enviar_pedido` modifica solo esas líneas abiertas y conserva intactos el estado actual de la cabecera y la fecha de su primer envío. La cabecera y los detalles no tienen que compartir el mismo estado.

## H3-D09 — Autorización, RLS y privilegios

Las lecturas de pedidos y detalles se limitan al local del contexto autenticado y al rol `MOZO`. Las mutaciones de cabecera/mesa se encapsulan en operaciones transaccionales. Historial se expone solo para lectura necesaria y sus inserciones se realizan desde funciones autorizadas. Las funciones revocan ejecución a `PUBLIC` y `anon`, fijan propietario/search path y no aceptan identidad/local/precio/estado suministrados por el cliente.

La UI deshabilita temporalmente acciones durante solicitudes, pero los índices, bloqueos, privilegios y RLS son la autoridad ante doble clic, reintentos o dos dispositivos.

## H3-D10 — Límites y aprobación

H3 no implementa cocina, Realtime, entrega, caja, impresión ni modificación/anulación de detalles enviados. Los estados posteriores del detalle preparan la evolución de H4: cocina deberá detectar trabajo nuevo por detalles y no asumir que una cabecera avanzada implica ausencia de líneas `ABIERTO` o recién `ENVIADO`. La construcción empieza únicamente tras aprobación humana de los cuatro documentos del Spec. La aceptación de H3 ocurre después de construir, ejecutar las pruebas humanas y recibir aprobación explícita; recién entonces corresponde crear `acceptance.md`.
