# E9 — Aceptación y cierre

**Estado final: CERRADA, VALIDADA Y ACEPTADA.** Fecha de cierre: **01/10/2026**, fecha local del proyecto (`America/Lima`). El responsable del proyecto declara explícitamente: **“El responsable del proyecto aprueba explícitamente el cierre de E9.”** La aprobación comunicada en esta solicitud autoriza la creación de este documento y acepta expresamente las dispensas TH02 y TH07.

## Objetivo y alcance aceptado

Jornada operativa del local abierta y cerrada por ADMINISTRADOR; fecha operativa y correlativo de servidor, idempotencia y trazabilidad de actor/hora. Pedidos y sesiones de caja asociados obligatoria e inmutablemente a la jornada de su local; coherencia de jornada en cobros con sesión. Bloqueo visual y autoritativo de operación con local cerrado; cierre sólo sin pedidos no terminales ni sesiones de caja abiertas. Historial ADMIN y Realtime de apertura/cierre como señal para relectura autoritativa, sin polling.

Fuente de verdad: [PLAN_MVP.md, Evolución 9](../../docs/PLAN_MVP.md#evolución-9--jornada-operativa-del-local), [requisitos](requirements.md) E9-R01–E9-R33 y DC-01–DC-12, [diseño](design.md), [tareas](tasks.md) y [plan de pruebas](test-plan.md). Spec aprobado en `313794a`, construcción autorizada en `c5ba802`; rama de construcción y cierre `feature/E9-OperationalDay`. Estimación aprobada: **22 h**, sin tiempo real consolidado.

No incluye horarios, cierre automático/forzado, reapertura de jornadas, traslado de pendientes, métricas E8 ni cambios financieros de E1. La aceptación no acredita despliegue a PROD ni altera PM-002.

## Evidencia técnica aceptada

Resultados ya ejecutados y aprobados, sin nuevas pruebas en este cierre. Evidencia detallada en [implementation.md](implementation.md) §§9.3–9.7.

| Verificación | Resultado |
|---|---|
| T02–T07 | Completadas |
| Realtime real | 7/7 PASS, apertura y cierre recibidos por cinco clientes |
| SQL E9 | 4/4 PASS |
| TP02 | 4/4 PASS |
| Concurrencia E9 | 13/13 PASS |
| Node | 430/430 PASS |
| Typecheck | PASS |
| Build | PASS |
| Regresión SQL | 52 PASS / **21 FAIL preexistentes** demostrados contra baseline; **0 nuevos** |
| Defectos E9 abiertos | Ninguno |

Los 21 fallos permanecen documentados individualmente, con test, errores en ambos lados, causa y relación con E9 en [implementation.md §9.3](implementation.md#93-fallos-preexistentes--fuera-del-alcance-de-e9--verificados-individualmente). Se aceptan como **preexistentes / fuera del alcance de E9**; no representan regresiones nuevas y **no se convierten en PASS**. HZ-E9-01 reproduce `42883` por `public.h2_auth_context()` ausente en la función heredada tanto en baseline como con E9; queda fuera de alcance, sin corrección histórica.

## Resultados humanos TH01–TH08

La fuente de estos resultados es la declaración explícita del responsable para este cierre. Se conservan los escenarios originales en [test-plan.md §4](test-plan.md#4-pruebas-humanas-e9-t08).

| Prueba | Resultado | Evidencia o decisión humana |
|---|---|---|
| TH01 | EJECUTADA Y APROBADA | Apertura y habilitación de los roles, confirmada por el responsable |
| TH02 | **NO EJECUTADA — ACEPTADA POR DISPENSA DEL RESPONSABLE** | No se dispone de un segundo ADMIN; dispensa explícita del responsable |
| TH03 | EJECUTADA Y APROBADA | Local cerrado, login/logout y funciones ADMIN, confirmada por el responsable |
| TH04 | EJECUTADA Y APROBADA | Atención completa con jornada abierta, confirmada por el responsable |
| TH05 | EJECUTADA Y APROBADA | Pendientes, resolución y cierre, confirmada por el responsable |
| TH06 | EJECUTADA Y APROBADA | Cierre/reapertura del mismo día, confirmada por el responsable; no se atribuye ejecución del cruce de medianoche opcional |
| TH07 | **NO EJECUTADA — ACEPTADA POR DISPENSA DEL RESPONSABLE** | Frontend aún no desplegado en un entorno adecuado para validar pérdida/recuperación real de conectividad; dispensa explícita |
| TH08 | EJECUTADA Y APROBADA | Uso táctil, responsive e historial, confirmada por el responsable |

**Seis pruebas humanas ejecutadas y aprobadas. Dos pruebas humanas no ejecutadas, aceptadas por dispensa explícita.** Las dispensas constituyen la decisión humana de aceptación para esos dos escenarios. TH02 y TH07 no son PASS ejecutados ni se ejecutan retroactivamente. E9-T08 queda completada por aceptación humana.

## DV-01 y aprobación final

**DV-01 aprobada e incorporada:** E9 no agrega una prohibición global sobre `pago.sesion_caja_id IS NULL`; conserva las reglas E1 y RPC vigentes. Cuando existe sesión de cobro, pedido y sesión deben pertenecer a la misma jornada. Registrada en [diseño D06](design.md#e9-d06--coherencia-pedido--sesión-en-el-cobro), TP09 e [implementation.md](implementation.md).

El responsable aprueba explícitamente el cierre con la evidencia técnica, las seis aprobaciones humanas y las dos dispensas. **E9 — CERRADA, VALIDADA Y ACEPTADA.** Sin defectos E9 abiertos. No se despliega, no se toca DEV compartido ni PROD y no se hace merge ni push a main en este cierre documental.
