# MikuyApp — H6 MVP liberado: tareas

| ID | Objetivo | Dependencias | Resultado verificable | Pruebas | Est. |
|---|---|---|---|---|---:|
| H6-T01 | **Completada.** Contrastar main, plan, H1–H5, migraciones, RLS, RPC, frontend y pruebas; registrar que las verificaciones SQL remotas y humanas pertenecen a tareas posteriores. | H5 aceptado | Inventario y riesgos documentados: H1–H5 existentes y sus suites pasan; H6-T02 (ventas/exportaciones), H6-T05 (PWA mínima), verificaciones SQL remotas y pruebas humanas permanecen pendientes. | TP09–TP12 | 0.5 h |
| H6-T02 | **Completada.** Construir resumen diario y exportaciones CSV servidoras/cliente. La migración remota quedó alineada y TP01–TP07 aprobaron con dos locales, roles autorizados/rechazados, cruce UTC/Lima, aislamiento y exportaciones contextuales; rollback y auditoría final confirmaron cero residuos. | T01, D01–D02 | Resumen y dos descargas aisladas por local. | TP01–TP07 | 1.5 h |
| H6-T03 | **Completada.** Documentar y ejecutar el procedimiento de respaldo manual. TP08 aprobó con CSV de ventas/productos no vacíos, copia administrativa y segunda copia verificada por tamaño/SHA-256 en memoria USB Kingston (disco físico independiente), además de política de cuatro respaldos semanales y respaldo previo a publicaciones. | T02, D03 | Guía y primer conjunto de respaldos comprobado. | TP08 | 0.25 h |
| H6-T04 | Ejecutar revisión final de seguridad, privilegios, RLS, RPC, duplicados y regresiones H1–H5. | T01–T03 | Sin acceso cruzado ni regresiones; defectos clasificados. | TP09–TP12 | 0.5 h |
| H6-T05 | Inspeccionar manifest/iconos existentes y completar únicamente la configuración mínima faltante para PWA; validar build, Cloudflare/dominio, instalación y despliegue candidato. No implementar offline. | T02, D05 | URL candidata instalable y build aprobado. | TP13–TP14 | 0.25 h |
| H6-T06 | Validar instalación, dispositivos, Realtime, impresión y 4G. | T05, equipamiento disponible | Evidencia humana por dispositivo y conexión. | TP15–TP17 | 0.5 h |
| H6-T07 | Ejecutar por separado flujo normal y regresión de reapertura H5 antes del pago; cerrar defectos/evoluciones. | T04, T06 | Flujo normal y reapertura previa al pago aprobados; aprobación del usuario solicitada. | TP18 | 0.5 h |

## Orden y límites

T01 precede construcción y pruebas. T02 precede T03. T04 requiere el estado técnico construido. T05–T06 requieren despliegue y equipamiento. T07 es el cierre humano. No se incluyen evoluciones ni `acceptance.md`.

## Estimación

H6 conserva tres referencias independientes: planificación original (4 h correspondientes a los días 11–12 del plan original), planificación actual aprobada (40.5 h para el MVP completo) y tiempo real, que se registrará aparte. Las jornadas 14–15 pertenecen a una planificación posterior/revisada y no sustituyen la línea base original. La estimación de este Spec permanece en **4 h**, sin recalcular históricos.
