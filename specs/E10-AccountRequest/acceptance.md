# E10 — Aceptación y cierre

**Estado final: ACEPTADA / CERRADA.** Fecha de aceptación humana: **30/09/2026**. El responsable del proyecto aprobó explícitamente: **“Apruebo TH01–TH07 y autorizo el cierre de E10.”** Esta aprobación fue comunicada para el presente cierre documental.

## Objetivo y alcance aceptado

El mozo solicita la cuenta total de un pedido entregado; Caja recibe el aviso en tiempo real mediante Realtime como señal y recarga el estado autoritativo de PostgreSQL. Caja atiende la solicitud con el flujo de cobro existente de E1. La solicitud registra actor y timestamps de solicitud y cierre para que E8 pueda distinguir el tiempo del cliente (`ENTREGADO → solicitud`) del tiempo atribuible al proceso de Caja (`solicitud → pago`). E10 no implementa las métricas de E8 ni altera el modelo financiero de E1. Alcance detallado: `requirements.md` E10-R01–E10-R22 y `design.md`.

## Línea base y cambios relevantes

- Línea base de especificación: `main` = `origin/main` en `ee3c94c` (cierre de E7); spec aprobado en `fc08a1a` y decisiones DH-01 A / DH-02 B registradas en `9c71685`.
- Rama de ejecución y cierre: `feature/E10-AccountRequest`, creada desde `9c71685`.
- Construcción y validación: `03c3d0d` (T02), `d83eeea` (T03), `1e18067` (T04), `3df48a0` (T05), `98d83b3` (T06), `9798e4d` (corrección T07) y `c94940d` (campaña T07). Evidencia documental de build y DEV: `b47a457` y `8b73ef5`.

## Resultados de aceptación

| Verificación | Resultado y evidencia |
|---|---|
| TP01–TP21 | **21/21 técnicamente completadas**, según `implementation.md` §8.3. TP20 significa **sin regresión** frente a la línea base; la suite SQL histórica no pasa completa: homologada, línea base 53 PASS / 12 FAIL y E10 57 PASS / 12 FAIL, con los mismos 12 fallos. Las pruebas E10 SQL fueron 4/4 PASS, las carreras E10 8/8 PASS, la suite Node 409/409 PASS y `typecheck` PASS (`implementation.md` §8.1). |
| TH01–TH07 | **7/7 aprobadas humanamente** por el responsable, conforme a su aprobación explícita para este cierre. `test-plan.md` §4 define los siete casos. |
| Build | `npm run build` **PASS** en Windows el 30/09/2026 sobre `c94940d`, ejecutado por el responsable; `tsc --noEmit` OK y Vite compiló 88 módulos (`implementation.md` §8.1). |
| DEV, PostgREST y Realtime | El responsable aplicó las dos migraciones E10 en DEV compartido y ejecutó `scripts/e10_dev_verificacion.mjs`: **12/12 PASS** el 30/09/2026, 23:38:44–23:39:20 UTC, con 118 eventos Realtime registrados. La lectura embebida de pedido y tablero pasó sobre PostgREST real; la solicitud llegó a dos cajas y al segundo dispositivo del mozo, el cierre `ATENDIDA` y `SIN_EFECTO` produjo las señales esperadas, y la reconexión resincronizó el snapshot. Fuente: `implementation.md` §§9–10 y `e10-dev-verificacion.log` (local, no versionado). |

**Decisiones aprobadas:** DH-01 **A**: el cobro no exige solicitud previa; DH-02 **B**: una solicitud de otro pedido conserva el borrador de cobro del pedido seleccionado. Se mantienen según `requirements.md` §10.

**HZ-02:** confirmado en DEV real y documentado como comportamiento heredado de H5, fuera del alcance de E10. Una reapertura sin solicitud no emite señal visible para Caja; cuando hay solicitud pendiente, `SIN_EFECTO` sí permite retirar el pedido de su vista. No se corrigió en E10 (`implementation.md` §10).

**Defectos bloqueantes abiertos:** ninguno. **Estimación aprobada:** 18 h (`tasks.md` §6). **Tiempo real:** no se registra un tiempo real consolidado; la evidencia disponible no permite calcularlo.

La dependencia documental con E8 permanece en `docs/PLAN_MVP.md`: E8 consumirá los eventos de E10 para separar los intervalos, sin atribuir tiempo de Caja a pedidos pagados sin solicitud registrada.
