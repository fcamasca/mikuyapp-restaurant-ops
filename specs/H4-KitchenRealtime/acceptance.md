# MikuyApp — Aceptación del Hito H4

## Identificación

| Campo | Valor |
|---|---|
| Fecha de cierre | 2026-08-27 |
| Hito | H4 — Cocina en tiempo real |
| Estado | **CERRADO / VALIDADO / ACEPTADO** |
| Evidencia técnica principal | `specs/H4-KitchenRealtime/h4_t09_execution.md` |

## Alcance aceptado

Se acepta el flujo de cocina por detalle con snapshot autoritativo, transición adyacente `ENVIADO → RECIBIDO_COCINA → EN_PREPARACION → LISTO`, auditoría, derivación transaccional de cabecera y mesa, tablero táctil, señales Realtime y reflejo de cambios hacia el mozo.

Forman parte del diseño aceptado el timestamp individual e inmutable `detalle_pedido.enviado_en`; los estados mixtos dentro del mismo pedido; el recálculo hacia atrás de la cabecera y de `PEDIDO_LISTO → OCUPADA` ante agregados posteriores; PostgreSQL como fuente de verdad; y la permanencia visual de detalles `LISTO` hasta H5. El tablero prioriza pedidos con trabajo pendiente por su envío pendiente más antiguo, presenta pendientes antes que listos dentro del pedido y mantiene al final una sección visual **Listos**.

H4 no incorpora entrega, caja, pago, impresión, polling ni funcionalidades de H5.

## Resultado y requisitos

H4-R01–H4-R14 quedan cubiertos mediante H4-D01–H4-D10, H4-T01–H4-T10 y las pruebas H4-TA, H4-TM y H4-TH trazadas en el Spec vigente.

Todas las tareas H4-T01–H4-T10 fueron completadas. No quedan pruebas obligatorias ni bloqueantes conocidos dentro del alcance aceptado.

## Evidencia de aceptación

- Suite integral H1–H4: **261/261 aprobadas** en la consolidación técnica de T09.
- Suites focalizadas posteriores para concurrencia, Realtime, ordenamiento y presentación: aprobadas, junto con typecheck, build, responsive técnico y `git diff --check`.
- SQL remoto H4-T01–H4-T05: aprobado contra Supabase.
- Seguridad y consistencia: RLS, grants, aislamiento por rol/local, `SECURITY DEFINER`, locks, inmutabilidad, auditoría, rollback y derivación aprobados.
- Migraciones local/remoto sincronizadas hasta `20260827000900`; `db lint --linked` sin errores y fixtures residuales en `0`.
- Concurrencia técnica: una transición ganadora y una sesión perdedora con SQLSTATE `40001`, sin doble transición.
- Validación humana H4-TH01–H4-TH06: **aprobada**, incluyendo tablet/responsive, antigüedad, transición por detalle, agregados posteriores, reflejo hacia el mozo, dos sesiones, conflicto y recuperación Realtime.

Los detalles técnicos y resultados por ID se conservan en `h4_t09_execution.md`. La aprobación humana explícita de cierre confirma los resultados H4-TH01–H4-TH06; no se fabrica metadata de dispositivo, navegador o viewport que no haya sido consignada.

## Defectos relevantes resueltos durante H4-T10

- En concurrencia de dos cocineros, la sesión perdedora podía permanecer en `Actualizando…`. Se desacopló la liberación del guard de la finalización de la resincronización y se añadió reconciliación por `detalle_id`, estado esperado y token de operación. Un snapshot PostgreSQL ganador libera inmediatamente la acción y una RPC tardía no sobrescribe el estado reciente.
- El tablero podía intercalar pedidos completamente listos antes de trabajo accionable. Se ajustó la prioridad para mostrar primero pedidos con pendientes, ordenar por el pendiente más antiguo, presentar líneas pendientes antes de `LISTO` y colocar pedidos completamente listos al final en la sección **Listos**.

Ambos defectos fueron cubiertos con pruebas automatizadas focalizadas y aprobados humanamente antes de este cierre.

## Decisión

La aprobación humana explícita confirma que las pruebas automatizadas, técnicas y humanas de H4 fueron satisfactorias y que no quedan pendientes bloqueantes conocidos.

**H4 — Cocina en tiempo real queda CERRADO, VALIDADO y ACEPTADO.**

H5 no fue iniciado.
