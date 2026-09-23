# MikuyApp — Aceptación E1: Operación de caja

**Fecha de aprobación:** 21/09/2026  
**Estado:** APROBADA Y CERRADA

## Declaración de aceptación

El usuario aprobó formalmente la **Evolución 1 — Operación de caja** después de completar la validación técnica y humana prevista. Las pruebas humanas **E1-TP62, E1-TP63 y E1-TP64** quedaron aprobadas.

Con esta aprobación, E1 queda **CERRADA**. El cierre documental no implica un despliegue automático en producción.

Al cierre, el usuario aplicó manualmente en DEV la migración final de T17, `20260921000400_e1_t17_pedidos_admin_ultima_actualizacion.sql`. `supabase db push` finalizó correctamente sin informar otras migraciones pendientes, por lo que las migraciones E1 quedaron alineadas entre local y DEV. Este cierre **no desplegó E1 ni sus migraciones a PROD**.

## Alcance funcional aceptado

E1 entrega una operación de caja más completa y una supervisión diaria más clara para el administrador:

- apertura o recuperación de una sesión de caja existente;
- cobros totales y parciales con uno o varios medios;
- propinas separadas del importe de venta;
- precuenta, recibo interno parcial y ticket interno final;
- movimientos de entrada y salida de efectivo;
- revisión previa al cierre, diferencia y motivo cuando corresponde;
- reporte interno de cierre imprimible;
- solicitud y decisión administrativa de descuentos;
- notificaciones por apertura, cierre y cierres con diferencia;
- Inicio ADMIN con indicadores del día, atención pendiente, flujo actual de pedidos, ventas por medio y estado de caja;
- consulta administrativa de pedidos y anulación directa de pedidos elegibles sin pagos;
- navegación administrativa consistente en escritorio, tablet y móvil;
- trazabilidad de los principales actos de caja y administración.

## Resultado de validación

| Validación | Resultado |
|---|---|
| E1-TP62 | Aprobada humanamente: jornada de Caja e Inicio ADMIN |
| E1-TP63 | Aprobada humanamente: descuentos y anulación administrativa |
| E1-TP64 | Aprobada humanamente: comportamiento responsive y regresión operativa |
| Validación técnica | Aprobada según la evidencia incremental de T03–T17 |
| Defectos bloqueantes de aceptación | 0 |

## Límites conservados

E1 no incorpora facturación electrónica, comprobantes fiscales, integración SUNAT, operación offline, selector o consolidación multilocal, cancelación individual de productos, históricos analíticos ni métricas avanzadas. Esas capacidades permanecen en sus evoluciones correspondientes.

## Correctivo E1-T18 — convención de errcode `40001` → `PT409`

**Fecha de aprobación del correctivo:** 23/09/2026
**Estado:** APROBADO PARA CIERRE

Con posterioridad al cierre original de E1 (21/09/2026), se detectó en DEV un incidente de CPU alta originado por el uso manual de `SQLSTATE 40001` para representar conflictos funcionales de aplicación (por ejemplo en `rpc_solicitar_descuento_pedido`). La causa raíz fue que PostgREST 14.5 interpreta `40001` como una condición de serialización transitoria y reintenta automáticamente la solicitud, generando reintentos en cascada y saturación de CPU.

La solución aplicada fue migrar los conflictos funcionales controlados al código `PT409`, mediante una nueva migración (`20260922000100_e1_delta_t18_migrar_errcode_conflicto_funcional.sql`) que reemplaza únicamente las versiones vigentes de las 17 funciones/triggers afectados, sin alterar migraciones históricas. `40001` queda reservado en adelante para una eventual condición nativa de serialización de PostgreSQL. Los servicios cliente (`cashierService.ts`, `kitchenRealtimeService.ts`, `waiterOrderService.ts`) reconocen `PT409` conservando compatibilidad temporal con `40001`/`23505`.

Tras aplicar el correctivo se ejecutó una campaña de capacidad en DEV (niveles 5/10/20/40 clientes concurrentes) para verificar que el cambio no introdujera regresiones bajo carga concurrente. Hasta 20 listeners no se observó degradación relevante; con 40 listeners el flujo se mantuvo funcional y sin errores, `PT409` ni `40001`, y sin saturación de Supabase/PostgreSQL, aunque apareció backlog no bloqueante en el refresh del tablero de mozo (ver `docs/E1_T18_CAPACITY_TEST_EVIDENCE.md` y `design.md` D18 para el detalle completo). La conclusión de la campaña es que no se requiere escalar compute ni cambiar el plan Supabase Free.

Validación técnica: pruebas Node (355/355 en la suite completa, incluidas 105/105 de la evidencia específica de T18), `typecheck` y `build` en verde. El usuario ejecutó y aprobó `npm run build` en su entorno Windows habitual (`tsc --noEmit && vite build`, 86 módulos transformados, build finalizado correctamente en 625 ms; el warning de chunk >500 kB no fue bloqueante). El entorno Linux de verificación de esta sesión no pudo ejecutar `vite build` por ausencia de `@rolldown/binding-linux-x64-gnu`, una limitación exclusivamente ambiental de ese entorno, sin impacto en la validación del proyecto. Auditoría estática confirmando que ninguna función/trigger vigente de `public` conserva un `40001` manual (evidencia completa en `test-plan.md` TP65).

El usuario aprobó formalmente el cierre del correctivo E1-T18 el 23/09/2026. Esta aprobación no implica un despliegue a producción ni cambios en el alcance funcional, reglas de negocio o mensajes de E1.

## Cierre

El alcance funcional, la validación técnica y las pruebas humanas acordadas quedaron conformes. MikuyApp **E1 — Operación de caja** queda formalmente **APROBADA Y CERRADA** el **21/09/2026**, con el correctivo técnico **E1-T18 aprobado para cierre** el **23/09/2026**.
