# MikuyApp — H6 MVP liberado: diseño

## D01. Resumen de ventas

Crear una lectura reutilizable para `ADMINISTRADOR` y `CAJA`. PostgreSQL obtiene el rol y local del perfil autenticado mediante `auth.uid()`; no recibe ni confía en un `local_id` del frontend. Filtra `pedido.estado = 'PAGADO'` y agrupa `pago` por medio y fecha local mediante `pagado_en at time zone 'America/Lima'`. El total y cantidades proceden de importes persistidos en `pago`; no se recalculan desde el cliente.

## D02. Exportaciones

Crear dos lecturas servidoras: ventas (pedido, mesa, pago, medio, importe) y productos (categoría y producto). Ambas derivan el local del contexto servidor. El cliente convierte filas ya autorizadas a CSV UTF-8 con encabezados, escape de comillas y descarga local; no expone credenciales ni requiere acceso a Supabase.

## D03. Respaldo

El respaldo es un procedimiento operativo documentado, no una tabla ni servicio nuevo. Para H6 se comprueba una ejecución inicial con archivos no vacíos, copia en el equipo administrativo y segunda copia fuera de él. El documento prescribe conservar cuatro cortes semanales y realizar un corte previo a cada publicación; no se exige esperar cuatro semanas para aceptar el hito.

## D04. Seguridad y regresión

Mantener RLS, privilegios y patrones RPC H1–H5. Revocar `PUBLIC`/`anon`, conceder ejecución solo a `authenticated`, validar rol y local dentro de cada función, y probar acceso cruzado manipulando parámetros. Revisar doble cobro, operaciones duplicadas, rollback y bloqueo de pedidos `PAGADO`; no reestructurar seguridad existente.

## D05. PWA, impresión y conectividad

Inspeccionar primero manifest, iconos, título y configuración de instalación existentes; completar únicamente lo mínimo faltante para que MikuyApp sea instalable y validar el resultado en el despliegue candidato. No implementar funcionamiento offline. Configurar y validar el dominio propio si está disponible; si no lo está, usar el despliegue vigente de Cloudflare Pages y registrar el dominio como pendiente operativo no bloqueante. Reutilizar `window.print` y CSS de H5 para papel de 80 mm, sin ESC/POS ni impresión silenciosa. Validar siempre la generación mediante navegador y el formato en vista previa o impresión a PDF; probar la salida física solo si existe impresora térmica disponible y, de no existir, registrarla como pendiente operativa no bloqueante. La PWA requiere red: validar 4G cambiando desde la conexión principal hacia una conexión móvil de respaldo mediante router 4G o hotspot móvil 4G autorizado; Wi-Fi doméstico no es válido. Registrar evidencia real de acceso al deployment publicado y operación de caja bajo la conexión 4G. Realtime continúa usando señales de `pedido`, `detalle_pedido` y `mesa` con resync autoritativo.

## D06. Flujo de validación

Usar un local operativo, usuarios por rol, pedido con múltiples detalles y un segundo local para aislamiento. Ejecutar por separado el flujo normal hasta pago/mesa libre y la reapertura H5 antes del pago: `ENTREGADO`, nuevo detalle `ABIERTO`, mesa `OCUPADA`, cocina, todos `LISTO`, nueva entrega y recién entonces pago. Los detalles anteriores permanecen `LISTO` y un pedido `PAGADO` no puede reabrirse. Registrar evidencia, defectos bloqueantes y evoluciones separadamente.
