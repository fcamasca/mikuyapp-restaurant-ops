# MikuyApp — H3 Flujo del mozo: requisitos

## 1. Objetivo y alcance

H3 permite al rol `MOZO` seleccionar una mesa activa, crear o recuperar un único pedido vigente, agregar productos con cantidad y observación, revisar el total, persistir incrementalmente el pedido y enviar a cocina solo los detalles todavía `ABIERTO`. No incluye cocina operativa, Realtime, entrega, caja, impresión ni modificación o anulación de detalles ya enviados.

## 2. Requisitos funcionales

| ID | Requisito | Prioridad |
|---|---|---|
| H3-R01 | Mostrar las mesas activas del local mediante cards táctiles, con estado visual, total vigente cuando exista consumo, filtro por estado y orden por número/código ascendente o descendente. | Must |
| H3-R02 | Al elegir una mesa libre, crear inmediatamente un pedido persistido en estado `ABIERTO`, asociarlo a la mesa y cambiar la mesa a `OCUPADA`; no usar únicamente un carrito en memoria. | Must |
| H3-R03 | Al elegir una mesa con pedido vigente, recuperar su cabecera y todos sus detalles persistidos, distinguiendo los detalles `ABIERTO` de los ya enviados. | Must |
| H3-R04 | Presentar productos activos de categorías activas mediante cards táctiles agrupadas y filtrables por categoría. | Must |
| H3-R05 | Agregar productos mediante una operación de servidor que obtenga `producto.precio` y controle obligatoriamente el estado `ABIERTO`, sin aceptar precio ni estado decididos por el cliente. Si ya existe un detalle `ABIERTO` del mismo producto y observación equivalente, incrementa su cantidad; observaciones diferentes permanecen separadas y detalles enviados nunca se consolidan. | Must |
| H3-R06 | Permitir modificar cantidad y observación, o retirar un producto, únicamente mientras el detalle permanezca `ABIERTO`; persistir cada cambio y recalcular el total desde los datos guardados. | Must |
| H3-R07 | Permitir observaciones frecuentes como opciones de UI y observación libre; almacenar el resultado en `detalle_pedido.observacion`, sin catálogo persistente de observaciones. | Must |
| H3-R08 | Mostrar una revisión con productos ya enviados, productos por enviar, cantidades, observaciones, total y acción explícita de envío. | Must |
| H3-R09 | Enviar atómicamente: siempre pasan únicamente los detalles `ABIERTO → ENVIADO`; en el primer envío la cabecera pasa `ABIERTO → ENVIADO`, mientras que en envíos posteriores conserva su estado actual; `pedido.enviado_en` conserva la fecha del primer envío y se evitan envíos duplicados. | Must |
| H3-R10 | Permitir agregar productos posteriormente al mismo pedido vigente; los nuevos detalles nacen `ABIERTO`, se persisten y requieren una nueva acción de envío selectivo. | Must |
| H3-R11 | Restringir lectura y mutaciones al local y rol `MOZO` autenticados; impedir que el cliente manipule `precio_unitario`, `estado`, pedido, producto, creador o estado de mesa fuera de las operaciones autorizadas. | Must |

## 3. Estados y reglas

Un pedido está vigente cuando su estado es `ABIERTO`, `ENVIADO`, `RECIBIDO_COCINA`, `EN_PREPARACION`, `LISTO` o `ENTREGADO`. `PAGADO` y `ANULADO` son terminales. `PENDIENTE_PAGO` es exclusivamente un estado de `mesa`, no de `pedido`.

H3 implementa `ABIERTO → ENVIADO` en la cabecera únicamente durante el primer envío. En todo envío, inicial o posterior, `enviar_pedido_cocina` cambia exclusivamente detalles `ABIERTO → ENVIADO`. Un envío posterior nunca retrocede ni sobrescribe el estado más avanzado de la cabecera, y `pedido.enviado_en` conserva la fecha del primer envío. Por ello, un pedido vigente puede tener una cabecera más avanzada y, al mismo tiempo, detalles anteriores enviados y agregados nuevos `ABIERTO`.

Los estados posteriores del detalle quedan contemplados para H4, que deberá consultar el estado individual de los detalles para detectar nuevos platos aunque la cabecera ya esté en `RECIBIDO_COCINA`, `EN_PREPARACION`, `LISTO` o `ENTREGADO`; H3 no implementa operativa de cocina. Cuando `cantidad > 1`, el estado sigue correspondiendo al detalle completo, no a cada unidad.

## 4. Requisitos no funcionales

- Mobile-first, sin desbordamiento horizontal, con objetivos táctiles de al menos 44 px y uso cómodo en celular y tablet.
- La UI confirma éxito solo después de la persistencia en servidor; un error no debe presentar como guardado un cambio que no se confirmó.
- El total es la suma de `cantidad * precio_unitario` de todos los detalles existentes del pedido. H3 no introduce descuentos, impuestos ni estado `ANULADO` en el detalle.
- Una mesa no puede tener más de un pedido vigente; la regla se garantiza en PostgreSQL.
- En concurrencia, una única operación de envío modifica cada detalle; repetirla no duplica transiciones ni historial.

## 5. Condición para iniciar construcción

La construcción de H3 solo puede comenzar después de la aprobación humana explícita de `requirements.md`, `design.md`, `tasks.md` y `test-plan.md`. Esta aprobación autoriza el Spec; no constituye aceptación del hito construido. `acceptance.md` se elaborará únicamente después de construcción, pruebas humanas y aprobación explícita.

## 6. Trazabilidad

La matriz completa y verificable se encuentra en `tasks.md`. Cada fila relaciona un requisito con decisiones de diseño, tareas y casos de prueba existentes.
