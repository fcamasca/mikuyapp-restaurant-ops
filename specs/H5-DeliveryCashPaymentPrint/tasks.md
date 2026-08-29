# MikuyApp — H5 Entrega, caja, cobro e impresión: tareas

Estimación final propuesta del Spec: **12 horas (6 jornadas de 2 h)**. Es una reestimación del alcance real de H5; no modifica `PLAN_MVP.md` ni `CHANGELOG_SCOPE.md`. La referencia del plan asigna 4 h originales (jornadas 12–13), pero el Spec exige función transaccional, seguridad, concurrencia, impresión y pruebas completas.

| ID | Trabajo | Req. | Diseño | Est. |
|---|---|---|---|---:|
| H5-T01 | **Completada (2026-08-29).** Verificar esquema desplegado, constraints, índices, privilegios, RLS, funciones y publicación Realtime; registrar contradicciones. | R08-R12 | D11 | 1 h |
| H5-T02 | **Completada (2026-08-29).** Diseñar/implementar función segura de entrega, historial, lock e idempotencia; bloquear modificaciones posteriores. | R01-R04 | D01-D02,D10 | 1.5 h |
| H5-T03 | Implementar lectura autoritativa de caja y total basado en precios históricos, con aislamiento por local y políticas mínimas. | R05,R10 | D03-D06 | 1.5 h |
| H5-T04 | Implementar función transaccional de cobro, constraint único, historial, liberación y rollback. | R07-R10 | D05-D06,D10 | 2 h |
| H5-T05 | Construir ruta `/caja`, listado, detalle, estados, precuenta y ticket postpago. | R05-R07 | D03,D07 | 2 h |
| H5-T06 | Integrar Realtime existente, snapshot/resync y estados de mozo/caja sin ampliar publicación. | R01,R05,R12 | D09 | 1 h |
| H5-T07 | Crear vista imprimible y CSS 80 mm; probar navegador/PC e impresión degradada en pantalla. | R06,R11 | D07-D08 | 1 h |
| H5-T08 | Ejecutar pruebas SQL/técnicas de seguridad, constraints, rollback y concurrencia; corregir defectos del alcance aprobado. | R03,R08-R10 | D01,D05,D06,D10-D11 | 1 h |
| H5-T09 | Ejecutar pruebas humanas de flujo completo en PC/tablet y regresión H1–H4. | R01-R12 | D01-D12 | 0.75 h |
| H5-T10 | Preparar evidencias y revisión humana del Spec/implementación; no crear `acceptance.md` en esta fase. | Todos | D11-D12 | 0.25 h |

## Orden y dependencias

T01 precede T02–T04. T02 debe cerrar antes de probar caja. T03 y T04 preceden T05. T06/T07 pueden ejecutarse después de T05. T08–T10 son cierre. Las tareas describen trabajo futuro; este Spec no lo ejecuta.

## Criterio de terminado propuesto

Todas las pruebas H5-TA y H5-TH pasan; no hay segunda fila de pago; las transiciones e historial son correctos; la mesa se libera atómicamente; precuenta/ticket se visualizan en los estados permitidos; impresión 80 mm funciona; regresión H1–H4 no presenta fallas; y las decisiones pendientes fueron aprobadas.
