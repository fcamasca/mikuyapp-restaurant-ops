# MikuyApp — H5 Entrega, caja, cobro e impresión: diseño

## H5-D01 — Baseline y transición de entrega

Reutilizar `pedido`, `detalle_pedido`, `mesa` e `historial_estado`. `entregar_pedido(p_pedido_id)` será una función `SECURITY DEFINER`: obtiene actor/contexto, exige `MOZO` y mismo local, bloquea pedido y mesa en orden determinista, exige pedido `LISTO`, al menos un detalle y que todos los detalles del pedido estén `LISTO`, y cambia `LISTO → ENTREGADO` y `PEDIDO_LISTO → PENDIENTE_PAGO` en una transacción. Los detalles permanecen `LISTO`; no se inventa estado de entrega de detalle. Inserta un único `historial_estado`.

La segunda sesión espera el lock y luego ve `ENTREGADO`; falla sin cambios. Un snapshot obsoleto recibe conflicto/estado no válido. La UI puede bloquear el botón, pero no es la garantía.

## H5-D02 — Restricción posterior a entrega

Las operaciones H3 de alta/envío deben rechazar `ENTREGADO` aunque hoy algunas lecturas lo consideren pedido vigente. Proponer ajustar la regla funcional de alta para permitir solo `ABIERTO`, `ENVIADO`, `RECIBIDO_COCINA`, `EN_PREPARACION` y `LISTO`; `ENTREGADO` y `PAGADO` son terminales comerciales. No modificar H3 en este Spec: queda como tarea de compatibilidad H5 y pendiente de implementación.

## H5-D03 — Vista de caja

Agregar la ruta protegida `/caja`, con listado de mesas `PENDIENTE_PAGO`, número de pedido, estado `ENTREGADO` y selección de detalle. El servicio de lectura devuelve solo el local autorizado y líneas persistidas, incluyendo `producto.nombre` resoluble aunque el producto esté inactivo, cantidad, `precio_unitario`, importe de línea y total. El nombre no es un snapshot histórico: si cambia posteriormente, el MVP mostrará el nombre vigente. Debe funcionar en PC y tablet; la operación primaria se optimiza para PC de caja.

## H5-D04 — Total autoritativo

El total se calcula en PostgreSQL con `sum(cantidad * precio_unitario)`, preferiblemente mediante función/consulta de lectura reutilizable. El frontend muestra el resultado, pero no lo envía como autoridad. `precio_unitario` es el único valor histórico del importe y no se vuelve a consultar en `producto.precio`. `producto.nombre` se obtiene de la fila actual; un producto inactivo debe seguir siendo resoluble para el consumo, pero una modificación posterior de su nombre no constituye snapshot histórico.

## H5-D05 — Función transaccional de cobro

Proponer `registrar_pago_pedido(p_pedido_id, p_medio)` como función `SECURITY DEFINER`, propietaria de `postgres`, `search_path` fijo, `PUBLIC`/`anon` revocados y `EXECUTE` solo a `authenticated`. Debe: obtener `auth.uid()` y contexto; exigir usuario activo, `CAJA`, local y medio permitido; bloquear pedido y mesa en orden determinista; exigir `ENTREGADO`; comprobar que no existe pago; calcular total desde detalles; insertar un pago con el total y actor servidor; cambiar `ENTREGADO → PAGADO`; insertar historial; cambiar `PENDIENTE_PAGO → LIBRE`; devolver total, pago y estados. Cualquier error revierte todo.

`UNIQUE(pago.pedido_id)`, pago único, aislamiento por local y protección mediante RLS/privilegios son contratos requeridos. Durante la construcción se verificará el estado real y, solo si falta algo, se aplicará el ajuste técnico mínimo. La inserción y el lock resuelven doble cobro concurrente: una sesión confirma y la otra observa `PAGADO`/pago existente y falla sin segunda fila. No se acepta importe del cliente.

## H5-D06 — Lecturas, RLS y administrador

Las lecturas transaccionales deben cubrir `CAJA` por local para pedidos `ENTREGADO`/`PAGADO`, detalles y mesa asociada; la lectura de `pago` se limita al mismo local y a función/consulta de caja. `MOZO` no necesita leer `pago`; puede leer la mesa libre después del cobro. `COCINA` y `ADMINISTRADOR` no reciben ejecución de entrega/cobro ni acceso operativo de caja.

## H5-D07 — Precuenta y ticket

Ambas vistas consumen el mismo snapshot autoritativo de líneas y total. La precuenta muestra restaurante, pedido, mesa, fecha/hora, productos, cantidades, precios y total, y está disponible con `ENTREGADO` antes del pago. El ticket muestra esos datos más forma de pago y solo se habilita tras `PAGADO`. El nombre del restaurante proviene de `local.nombre`; presentación e impresión usan locale `es-PE` y zona horaria `America/Lima`.

## H5-D08 — Impresión

Crear componentes/vistas de documento con clases de impresión. `@media print` oculta menú, encabezados de aplicación, botones y navegación; conserva solo el documento, usa ancho de 80 mm, tipografía legible, márgenes mínimos, saltos controlados y contraste monocromo. La acción llama impresión estándar del navegador desde caja. Si falla la impresora, el documento permanece visible.

## H5-D09 — Realtime mínimo

Reutilizar la publicación existente de `detalle_pedido`, `pedido` y `mesa`. Mozo resincro cuando `pedido` pasa a `LISTO` y cuando la mesa cambia a `PENDIENTE_PAGO`; caja resincro cuando aparece `PENDIENTE_PAGO`/`ENTREGADO` y después de cobro; mozo resincro cuando la mesa vuelve a `LIBRE`. Eventos son señales: snapshot posterior, conciliación por ID y recuperación tras reconexión, siguiendo H4. No agregar `pago` a Realtime.

## H5-D10 — Auditoría e idempotencia

La entrega y el cobro escriben `historial_estado` solo ante cambios reales, con actor servidor y timestamps de PostgreSQL. No se crea historial de detalle porque los detalles permanecen `LISTO`. Las funciones devuelven resultado persistido; un error nunca se muestra como éxito.

## H5-D11 — Dependencias y compatibilidad

Antes de construir se debe verificar en la base desplegada constraints, privilegios, políticas y funciones vigentes, especialmente que la restricción única de `pago` no sea solo histórica. Si existe contradicción entre migraciones y base, se documenta y no se corrige silenciosamente.

## H5-D12 — Decisiones y límites

No se agregan estados, tablas de Realtime ni infraestructura. La ruta, firmas, roles, estados, locale, zona horaria, Realtime e impresión quedan fijados por este Spec. Durante la construcción solo se verificará el estado real y se aplicará el ajuste técnico mínimo de los contratos ya definidos. Reportes/CSV/respaldo corresponden a H6/posterior según plan.
