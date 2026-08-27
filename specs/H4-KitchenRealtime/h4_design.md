# MikuyApp — H4 Cocina en tiempo real: diseño

## H4-D01 — Baseline y cambio mínimo de modelo

H4 reutiliza `pedido`, `detalle_pedido`, `mesa`, `producto`, `historial_estado`, `obtener_contexto_autenticado()`, la auditoría vigente y el cliente `@supabase/supabase-js`. No se agrega responsable a `mesa`, una tabla de historial de detalle ni un backend adicional.

Se añadirá `detalle_pedido.enviado_en timestamptz null`. La función existente `enviar_pedido_cocina` debe fijarlo únicamente al cambiar ese detalle `ABIERTO → ENVIADO`, usando un mismo timestamp PostgreSQL para las líneas del envío. El valor es individual, inmutable y no se sobrescribe durante recepción/preparación. Debe existir un check coherente entre estado y timestamp: `ABIERTO` conserva `NULL`; los estados de cocina requieren valor. La migración debe resolver datos existentes compatibles antes de validar el constraint.

Índice propuesto para la cola: `(estado, enviado_en, pedido_id)` o su variante parcial equivalente para estados de cocina, validado con el plan real de consulta.

## H4-D02 — Lectura autoritativa del tablero

Una operación de lectura funcional, por ejemplo `obtener_tablero_cocina()`, devuelve exclusivamente datos del local autenticado para rol `COCINA`: pedido, mesa, detalle, producto, cantidad, observación, estado, `enviado_en` y `modificado_en`. Excluye pedidos terminales `ENTREGADO`, `PAGADO` y `ANULADO`. La lectura segura permite conservar el nombre histórico del producto aunque después quede inactivo, sin abrir el catálogo completo ni confiar en joins construidos por React.

La carga se agrupa por `pedido_id`/mesa. Los grupos se ordenan por el menor `enviado_en` de sus detalles todavía no listos; si el grupo solo contiene `LISTO`, usa el menor `enviado_en`. Dentro del grupo se ordena por `enviado_en`, luego por `detalle_id`, para estabilidad.

El tablero presenta columnas o secciones equivalentes a “Recibidos”, “En preparación” y “Listos”. `ENVIADO` aparece como “Nuevo/por recibir”; `RECIBIDO_COCINA`, “Recibido”; `EN_PREPARACION`, “En preparación”; y `LISTO`, “Listo”. Texto e iconografía acompañan al color.

## H4-D03 — Transición individual de cocina

Se diseña una única operación permanente `actualizar_estado_detalle_cocina(p_detalle_id bigint, p_estado_esperado text, p_estado_nuevo text)`. Es `SECURITY DEFINER`, propiedad de `postgres`, con `search_path = pg_catalog`; obtiene `auth.uid()` y valida `obtener_contexto_autenticado()`.

La función:

1. exige rol `COCINA` y local autorizado;
2. bloquea el detalle y su pedido en orden determinista;
3. exige pedido vigente y detalle del mismo local;
4. compara el estado persistido con `p_estado_esperado`;
5. permite solo una transición adyacente de la matriz aprobada;
6. actualiza exclusivamente el estado del detalle;
7. recalcula cabecera y mesa según H4-D04;
8. devuelve el estado persistido resultante.

Una repetición con estado esperado obsoleto se rechaza como conflicto; la UI recarga el snapshot. No se concede `UPDATE(estado)` a `authenticated`, `COCINA` no puede cambiar precio, cantidad, observación, pedido ni producto, y `PUBLIC`/`anon` no pueden ejecutar la función.

## H4-D04 — Derivación de pedido y mesa

PostgreSQL aplica la derivación dentro de la misma transacción de la transición de cocina.

### Cabecera agregada actual

PostgreSQL obtiene el estado agregado aplicando la primera condición verdadera:

| Prioridad | Condición | Estado resultante |
|---:|---|---|
| 1 | Existe al menos un detalle `ABIERTO` | `ABIERTO` |
| 2 | No hay `ABIERTO` y existe al menos un `ENVIADO` | `ENVIADO` |
| 3 | No hay estados anteriores y existe al menos un `RECIBIDO_COCINA` | `RECIBIDO_COCINA` |
| 4 | No hay estados anteriores y existe al menos un `EN_PREPARACION` | `EN_PREPARACION` |
| 5 | Existe al menos un detalle y todos están `LISTO` | `LISTO` |

La cabecera se actualiza siempre que el resultado sea distinto de su estado persistido, incluso si el agregado posterior exige volver de `LISTO`, `EN_PREPARACION` o `RECIBIDO_COCINA` a `ABIERTO`/`ENVIADO`. Ese recálculo no modifica los estados individuales: un detalle `LISTO` permanece `LISTO` y uno `EN_PREPARACION` permanece en preparación. Cada cambio real de cabecera inserta `historial_estado` con el actor de la operación; si el resultado no cambia, no se crea historial ficticio.

La misma derivación debe ejecutarse dentro de las operaciones que alteran la composición o estado del pedido: alta de detalle posterior, envío selectivo y transición de cocina. La UI continúa consultando detalles para representar estados mixtos.

### Mesa

Para un pedido vigente dentro del flujo de cocina:

- todos los detalles `LISTO` y al menos uno existente → `PEDIDO_LISTO`;
- cualquier `ABIERTO`, `ENVIADO`, `RECIBIDO_COCINA` o `EN_PREPARACION` → `OCUPADA`.

Si un mozo agrega un detalle a un pedido cuya mesa estaba `PEDIDO_LISTO`, la operación de alta debe devolver la mesa a `OCUPADA` y recalcular la cabecera a `ABIERTO` en la misma transacción. H4 no toca `PENDIENTE_PAGO` ni `LIBRE` y rechaza estados incompatibles.

## H4-D05 — Auditoría

La auditoría vigente sigue siendo la autoridad:

- el trigger de detalle obtiene el actor desde `auth.uid()`;
- la transición actualiza `detalle_pedido.modificado_por/modificado_en`;
- `creado_por/creado_en` y `enviado_en` permanecen inmutables;
- un cambio exclusivamente de estado no modifica `pedido.modificado_por/modificado_en`;
- un cambio real de cabecera genera `historial_estado`, pero no transforma esa transición operativa en modificación comercial;
- todas las FK de usuario continúan `ON DELETE RESTRICT`.

React no envía UUID de auditoría. No se propone una nueva tabla de historial de detalle: para H4 basta el estado actual, el timestamp estable de envío y la auditoría del último cambio.

## H4-D06 — Realtime y consistencia de cliente

Se habilitan en la publicación `supabase_realtime`, de forma idempotente, las tablas estrictamente necesarias: `detalle_pedido`, `pedido` y `mesa`. Se usan eventos `INSERT` y `UPDATE`; H4 no requiere `DELETE` de detalles enviados. RLS debe permitir que cada sesión reciba únicamente filas visibles de su local y rol.

Secuencia de inicio y recuperación:

1. cargar un snapshot autoritativo;
2. abrir el canal Realtime;
3. al quedar `SUBSCRIBED`, ejecutar una segunda carga para cerrar la ventana entre snapshot y suscripción;
4. reemplazar/conciliar el estado local por ID con el snapshot más reciente;
5. ante reconexión, canal caído, error o evento no conciliable, repetir la resincronización completa.

Los eventos son señales de cambio, no evidencia final de éxito. Ante cada `INSERT` o `UPDATE` relevante se solicita nuevamente el snapshot autoritativo; señales próximas pueden agruparse/debouncearse para evitar consultas redundantes. El snapshot sustituye el estado derivado local y nunca se hace append ciego, por lo que eventos repetidos o fuera de orden no duplican cards ni exigen versionamiento temporal homogéneo entre pedido, mesa y detalle. No se implementa polling.

## H4-D07 — Reflejo en cocina y mozo

Se crea un servicio funcional de cocina que encapsula snapshot, transición y ciclo de suscripción. La ruta protegida `/cocina` reemplaza `/tecnica` como destino operativo de `COCINA`, conservando el menú autenticado transversal.

La vista del mozo reutiliza su lectura persistida e incorpora una suscripción mínima a cambios de `detalle_pedido`, `pedido` y `mesa` del pedido/mesa mostrados. Ante señal relevante recarga desde PostgreSQL. Así, un detalle que avanza aparece en “Ya solicitado” con su estado vigente y el tablero de mesas refleja `PEDIDO_LISTO` sin que React escriba estados directamente.

## H4-D08 — Autorización, RLS y privilegios

- `COCINA` recibe lectura mínima de pedidos, mesas y detalles de cocina de su local.
- La mutación de estado solo ocurre por `actualizar_estado_detalle_cocina`.
- Las funciones validan usuario activo, rol y local mediante contexto servidor.
- `MOZO` conserva sus permisos H3 y solo observa los estados actualizados.
- `ADMINISTRADOR`, `CAJA`, `anon` y otro local no pueden ejecutar transiciones de cocina.
- Las políticas necesarias para Realtime se diseñan como `SELECT` por rol/local; no se amplían escrituras directas.
- La función de snapshot evita exponer perfiles ajenos y no usa un responsable persistido en `mesa`.

## H4-D09 — Concurrencia, errores e idempotencia

El bloqueo y el parámetro `p_estado_esperado` implementan concurrencia optimista con autoridad PostgreSQL. Dos cocineros que actúan sobre el mismo detalle no pueden saltar ni duplicar una transición: uno confirma y el otro recibe conflicto, resincroniza y muestra el estado ganador.

Los guards de UI son por detalle. Durante una operación se bloquean únicamente sus acciones y se muestra feedback como “Actualizando…”. En error se libera siempre el guard, no se muestra falso éxito y se recupera el snapshot. Dos detalles distintos pueden procesarse simultáneamente.

## H4-D10 — Responsive, límites y aprobación

El tablero es mobile-first y optimizado para tablet: tarjetas táctiles, encabezado compacto, tiempo legible y secciones que se apilan en vertical o usan columnas en anchos mayores. Los controles principales tienen al menos 44 px y no existe scroll horizontal crítico.

H4 no implementa entrega, caja, pago, impresión, reportes ni inventario. No se crea `acceptance.md`. La construcción queda bloqueada hasta la aprobación humana explícita de los cuatro documentos del Spec.

## Riesgos de diseño

| Riesgo | Mitigación prevista |
|---|---|
| Cabecera avanzada con nuevo detalle pendiente | Recálculo agregado transaccional sin modificar estados individuales. |
| Ventana entre carga y suscripción | Segunda carga inmediata tras `SUBSCRIBED`. |
| Eventos duplicados/fuera de orden | Eventos usados como señal y reemplazo por snapshot autoritativo. |
| Antigüedad incorrecta para agregados posteriores | Timestamp individual e inmutable `detalle_pedido.enviado_en`. |
| Producto desactivado después de pedir | Snapshot seguro devuelve nombre histórico sin ampliar catálogo operativo. |
| Dos cocineros sobre la misma línea | Lock, estado esperado y recuperación del ganador. |
