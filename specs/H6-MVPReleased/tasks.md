# MikuyApp — H6 MVP liberado: tareas

| ID | Objetivo | Dependencias | Resultado verificable | Pruebas | Est. |
|---|---|---|---|---|---:|
| H6-T01 | **Completada.** Contrastar main, plan, H1–H5, migraciones, RLS, RPC, frontend y pruebas; registrar que las verificaciones SQL remotas y humanas pertenecen a tareas posteriores. | H5 aceptado | Inventario y riesgos documentados: H1–H5 existentes y sus suites pasan; H6-T02 (ventas/exportaciones), H6-T05 (PWA mínima), verificaciones SQL remotas y pruebas humanas permanecen pendientes. | TP09–TP12 | 0.5 h |
| H6-T02 | **Reabierta.** El resumen diario y las exportaciones conservan la validación TP01–TP07, pero durante TP17 se detectó que `/ventas` no tenía acceso visible. Se agregó la opción mínima `Resumen diario` al menú existente para `ADMINISTRADOR` y `CAJA`; queda pendiente validar el acceso funcional sobre un deployment corregido antes de cerrar nuevamente T02. | T01, D01–D02 | Resumen y dos descargas aisladas por local, accesibles desde el flujo normal autorizado. | TP01–TP07 y regresión de navegación | 1.5 h |
| H6-T03 | **Completada.** Documentar y ejecutar el procedimiento de respaldo manual. TP08 aprobó con CSV de ventas/productos no vacíos, copia administrativa y segunda copia verificada por tamaño/SHA-256 en memoria USB Kingston (disco físico independiente), además de política de cuatro respaldos semanales y respaldo previo a publicaciones. | T02, D03 | Guía y primer conjunto de respaldos comprobado. | TP08 | 0.25 h |
| H6-T04 | **Completada.** Ejecutar revisión final de seguridad, privilegios, RLS, RPC, duplicados y regresiones H1–H5. TP09–TP12 aprobaron: 293/293 automatizadas, 20/20 SQL remotas aplicables, doble cobro concurrente con pago único persistido, lint/typecheck/build aprobados, aislamiento y terminales verificados, migraciones alineadas y residuos finales en cero. | T01–T03 | Sin acceso cruzado ni regresiones; defectos clasificados. | TP09–TP12 | 0.5 h |
| H6-T05 | **Completada.** Se completó la configuración PWA mínima y TP13–TP14 aprobaron: pruebas PWA 3/3, typecheck/build válidos y deployment H6 operativo e instalable en `a6911511.mikuyapp.pages.dev`, con manifest, metadatos, iconos 192/512 y service worker sin lógica offline. El dominio propio queda pendiente operativo no bloqueante. | T02, D05 | URL candidata instalable y build aprobado. | TP13–TP14 | 0.25 h |
| H6-T06 | Validar instalación, dispositivos, Realtime, impresión y cambio desde la conexión principal hacia respaldo móvil mediante router 4G o hotspot móvil 4G autorizado; comprobar el deployment publicado y una operación real de caja bajo 4G. No aceptar Wi-Fi doméstico como respaldo. | T05, equipamiento disponible | Evidencia humana por dispositivo y conexión móvil 4G. | TP15–TP17 | 0.5 h |
| H6-T07 | Ejecutar por separado flujo normal y regresión de reapertura H5 antes del pago; cerrar defectos/evoluciones. | T04, T06 | Flujo normal y reapertura previa al pago aprobados; aprobación del usuario solicitada. | TP18 | 0.5 h |

## Orden y límites

T01 precede construcción y pruebas. T02 precede T03. T04 requiere el estado técnico construido. T05–T06 requieren despliegue y equipamiento. T07 es el cierre humano. No se incluyen evoluciones ni `acceptance.md`.

## Estimación

H6 conserva tres referencias independientes: planificación original (4 h correspondientes a los días 11–12 del plan original), planificación actual aprobada (40.5 h para el MVP completo) y tiempo real, que se registrará aparte. Las jornadas 14–15 pertenecen a una planificación posterior/revisada y no sustituyen la línea base original. La estimación de este Spec permanece en **4 h**, sin recalcular históricos.
