# MikuyApp — H6 MVP liberado: requisitos

## 1. Objetivo

Cerrar el MVP con ventas del día, exportaciones, respaldo manual, revisión final de seguridad y validación de instalación y operación en celular, tablet y PC. H6 conserva las reglas aprobadas en H1–H5; `ENTREGADO` solo es cobrable mientras no exista pago y `PAGADO`/`ANULADO` son terminales.

## 2. Resultado verificable

El flujo **MOZO → COCINA → MOZO → CAJA → PAGO → MESA LIBRE** funciona en los dispositivos previstos; el administrador consulta y exporta ventas/productos, caja consulta el resumen diario, la impresión mediante navegador genera un formato térmico correcto de 80 mm y la aplicación opera con Internet principal y una conexión móvil 4G de respaldo mediante router 4G o hotspot móvil 4G autorizado. Si no hay impresora térmica disponible, la vista previa o impresión a PDF en 80 mm constituye evidencia funcional suficiente y la prueba física queda pendiente operativa no bloqueante.

## 3. Requerimientos funcionales

| ID | Requisito | Tipo |
|---|---|---|
| H6-R01 | Mostrar total vendido, pedidos pagados y totales por `EFECTIVO`, `YAPE`, `PLIN`, `TARJETA`. Solo cuentan pagos de pedidos `PAGADO`, agrupados por `pago.pagado_en` en `America/Lima`. | Construcción |
| H6-R02 | `ADMINISTRADOR` y `CAJA` consultan el resumen usando el local obtenido del contexto autenticado en servidor; ningún identificador de local enviado por frontend es confiable. `MOZO`/`COCINA` no acceden. | Construcción/regresión |
| H6-R03 | `ADMINISTRADOR` descarga CSV de ventas del local autenticado, solo pagadas, con pedido, mesa, pago, medio e importe persistido. | Construcción |
| H6-R04 | `ADMINISTRADOR` descarga CSV de productos del local con categoría, códigos, nombre, precio vigente y activo/inactivo. | Construcción |
| H6-R05 | Documentar respaldo semanal: exportar, comprobar, guardar copia local y segunda copia externa, indicar conservación mínima de cuatro semanas y respaldar antes de publicar. La aceptación valida el procedimiento y las copias iniciales, sin esperar cuatro semanas reales. | Construcción humana |
| H6-R06 | Mantener autenticación, rutas, privilegios, RLS, RPC, aislamiento, idempotencia, bloqueo postpago y protección contra doble cobro. | Regresión |
| H6-R07 | PWA instalable con nombre/iconos/metadatos de MikuyApp y conexión requerida. | Configuración/validación |
| H6-R08 | Validar celular de mozo, tablet de cocina, PC de caja, generación/impresión mediante navegador en formato térmico de 80 mm y el cambio desde la conexión principal hacia una conexión móvil 4G de respaldo mediante router 4G o hotspot móvil 4G autorizado. Si existe impresora térmica, validar además la salida física; si no existe, aceptar vista previa o impresión a PDF correctamente formateada y registrar la prueba física como pendiente operativa no bloqueante. La evidencia debe incluir acceso al deployment publicado y operación real de caja; Wi-Fi doméstico no constituye respaldo 4G. | Humano |
| H6-R09 | Validar operación integral y reapertura H5: `ENTREGADO → detalle ABIERTO → cocina → LISTO → nueva entrega → pago`; detalles previos permanecen `LISTO`. | Regresión humana/técnica |

## 4. Requerimientos técnicos y seguridad

Usar React + TypeScript, Supabase/PostgreSQL, Realtime existente y Cloudflare Pages. Las consultas de ventas/exportación deben derivar el local y rol desde `auth.uid()` en PostgreSQL, usar funciones `SECURITY DEFINER` con `search_path` fijo, privilegios mínimos y `EXECUTE` solo a `authenticated`. El frontend no es frontera de seguridad. No publicar `pago` en Realtime.

## 5. Instalación, dependencias y exclusiones

La liberación depende de celulares Android, tablet, PC, un navegador capaz de mostrar o imprimir a PDF el formato de 80 mm, conectividad principal y conexión móvil 4G de respaldo mediante router 4G o hotspot móvil 4G autorizado. La impresora térmica física se valida solo si está disponible; su ausencia no bloquea H6 y se registra como pendiente operativo. El dominio propio se configura y valida si está disponible; su indisponibilidad no bloquea las pruebas funcionales ni el cierre de H6, y se registra como pendiente operativo usando el despliegue vigente de Cloudflare Pages. No incluye SUNAT, inventario, delivery, reservas, QR, división de cuenta, propinas, apertura/cierre de caja, reportes avanzados, impresión automática de cocina, app nativa, ESC/POS, impresión silenciosa u operación offline.

## 6. Criterios de salida

Código H6, pruebas automatizadas/SQL, typecheck, build, seguridad y regresiones aprobados; exportaciones verificadas; dispositivos, formato de impresión 80 mm mediante navegador/PDF, 4G y flujo integral aprobados humanamente; impresión física aprobada si existe equipo o registrada como pendiente operativa no bloqueante; cero defectos bloqueantes; aprobación explícita del usuario. No se crea `acceptance.md` antes de esa aprobación.

## 7. Trazabilidad

R01 → D01, T02, TP01–TP03; R02 → D01/D04, T02/T04, TP04/TP07; R03–R04 → D02, T02, TP05–TP07; R05 → D03, T03, TP08; R06 → D04, T04, TP09–TP12; R07–R09 → D05/D06, T05–T07, TP13–TP18. T01 solo inspecciona y contrasta el estado existente.

### Asuntos pendientes de decisión

No quedan asuntos pendientes de decisión funcional. `America/Lima` se hereda de H5; H6 mantiene únicamente las exportaciones CSV de ventas y productos. Si el dominio propio no está disponible, queda como pendiente operativo de liberación, no como bloqueante ni decisión abierta. Se aprueba validar la conectividad móvil 4G de respaldo mediante router 4G o hotspot móvil 4G autorizado; Wi-Fi doméstico no es una alternativa válida. Se aprueba validar funcionalmente la impresión de 80 mm mediante navegador y vista previa/impresión a PDF cuando no exista impresora térmica; la salida física queda entonces como pendiente operativa no bloqueante. Se mantiene `window.print`, sin ESC/POS ni impresión silenciosa.
