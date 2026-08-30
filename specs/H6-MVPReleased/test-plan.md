# MikuyApp — H6 MVP liberado: plan de pruebas

## Pruebas automatizadas y SQL/técnicas

| ID | Caso | Resultado esperado |
|---|---|---|
| H6-TP01 | Resumen con pagos de hoy, otro día y estados no pagados. | Solo `PAGADO` del día Lima cuenta; total y conteos coinciden. |
| H6-TP02 | Cuatro medios de pago. | Cada medio aparece con cantidad e importe persistido correctos. |
| H6-TP03 | Cruce UTC/Lima en medianoche. | La fecha se evalúa en `America/Lima`, no UTC. |
| H6-TP04 | Roles en resumen. | Admin y caja autorizados; mozo/cocina y anon rechazados. |
| H6-TP05 | CSV de ventas. | Encabezados, escape, filas pagadas y campos mínimos correctos. |
| H6-TP06 | CSV de productos. | Categoría/códigos/precio/activo y solo local autenticado. |
| H6-TP07 | Dos locales y parámetros manipulados. | Cero filas del local ajeno en resumen y exportaciones. |
| H6-TP08 | Ejecución inicial del procedimiento de respaldo. | Exportaciones generadas y no vacías, copia en equipo administrativo, segunda copia fuera de él y procedimiento documentado con conservación mínima de cuatro semanas; no se exige disponer ya de cuatro semanas reales. |
| H6-TP09 | Privilegios, RLS y funciones. | `anon` sin ejecución; funciones validan rol/local y `search_path`. |
| H6-TP10 | Doble cobro y operaciones duplicadas. | Un solo pago/transición; segundo intento falla sin efectos parciales. |
| H6-TP11 | Pedido `PAGADO`/`ANULADO`. | No puede reabrirse, modificarse ni cobrarse. |
| H6-TP12 | Regresión H1–H5. | Suite existente, typecheck y build pasan; aviso de bundle >500 kB es no bloqueante si no afecta operación. |
| H6-TP13 | Manifest, iconos y título. | Navegador ofrece instalación como MikuyApp. |
| H6-TP14 | Cloudflare Pages/dominio. | Candidato desplegado; dominio propio validado si está disponible. Si no está disponible, `pages.dev` permite las pruebas funcionales y el dominio queda registrado como pendiente operativo no bloqueante. |

## Pruebas humanas

| ID | Escenario | Evidencia requerida |
|---|---|---|
| H6-TP15 | Android de mozo: login, mesa, pedido, envío, seguimiento y reapertura. | Capturas/registro de ejecución sin fallos. |
| H6-TP16 | Tablet cocina: recepción Realtime, observaciones, estados y nuevos detalles sin refresh. | Pedido cambia en vivo y nuevo detalle vuelve a cocina. |
| H6-TP17 | PC caja: pendientes, precuenta, cobro, ticket, resumen e impresión 80 mm; repetir con router 4G. | Ticket legible, mesa libre, venta visible y operación con 4G. |
| H6-TP18 | **Dos escenarios separados:** (A) flujo normal `MOZO → COCINA → MOZO → CAJA → PAGO → MESA LIBRE`; (B) regresión H5: llegar a `ENTREGADO`, antes de pagar agregar nuevo detalle `ABIERTO`, verificar mesa `OCUPADA` y retorno al flujo operativo, pasar por cocina hasta `LISTO`, realizar nueva entrega y recién después cobrar. | En B los detalles anteriores permanecen `LISTO`, el nuevo detalle recorre cocina, la mesa vuelve a `PENDIENTE_PAGO`, se cobra una sola vez y queda `LIBRE`; después de `PAGADO` cualquier reapertura es rechazada. |

## Criterio humano de aceptación

Las pruebas TP15–TP18 deben ser ejecutadas con el equipamiento real previsto y aprobadas explícitamente por el usuario. Cualquier defecto que impida un criterio obligatorio bloquea H6; mejoras no obligatorias se registran como evoluciones. Solo después de esa aprobación puede crearse `acceptance.md`.
