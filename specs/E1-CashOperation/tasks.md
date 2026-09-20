# MikuyApp — Evolución 1 — Operación de caja: tareas

## Estado

**E1-T01 y E1-T02 (Spec Mode)** quedan completadas documentalmente. **T03–T13, incluido el delta de acto de cobro con N medios, están completadas técnicamente y validadas en PostgreSQL local aislado/frontend.** T14 y TP62–TP64 permanecen pausadas y E1 no está aceptada. La impresión de comandas se trasladó a Evolución 7 y no forma parte de estas tareas.

| ID | Unidad implementable | Dependencias | Resultado verificable | Requisitos / pruebas | Est. |
|---|---|---|---|---|---:|
| E1-T01 | **Completada — Spec Mode.** Inventariar plan, H5/H6, PM-001, PM-002, Git, esquema, RPC, RLS, UI, reportes, pruebas y Realtime; elaborar requisitos, diseño, tareas y plan de pruebas. | MVP/PM-001 aceptados | Cuatro documentos; sin código, migraciones, datos ni `acceptance.md`. | Todos / revisión documental | 4 h |
| E1-T02 | **Completada — decisiones funcionales.** Registrar la aprobación de DF-01–DF-04 y DF-06–DF-09 y consolidar EC-06–EC-08. | T01 | Reglas cerradas y reflejadas consistentemente en requisitos, diseño, tareas y pruebas. | R01–R22 / revisión documental | 2 h |
| E1-T03 | **Completada técnicamente en local aislado.** Diseñar y migrar `caja`/`sesion_caja`, datos mínimos de caja y estrategia legacy, sin tocar migraciones históricas. | T02, PM-002 DEV disponible | Integridad, unicidad de sesión abierta, FKs y comentarios; evidencia en `implementation-t03.md`. | R01–R03 / TP01–TP08 aplicables al modelo; RPC pendientes de T04 | 4 h |
| E1-T04 | **Completada técnicamente en local aislado.** Implementar RPC/RLS/grants de apertura, recuperación compartida de sesión activa e histórico básico. | T03 | Una sesión abierta por caja; cualquier `CAJA` activo del local puede continuarla; apertura, recuperación, idempotencia, histórico y aislamiento validados. | R01–R03/R08 / TP03–TP08, TP11–TP12; aspectos T04 de TP09–TP10 | 3 h |
| E1-T05 | **Completada técnicamente en local aislado.** Implementar movimientos inmutables, saldo esperado y cierre/arquéo transaccional. | T04, T08 | Entradas/salidas explícitas; esperado, contado y diferencia persistidos; doble cierre, cierre-vs-movimiento y cierre-vs-cobro seguros. Evidencia en `implementation-t05.md`. | R04–R08 / TP13–TP18 | 6 h |
| E1-T06 | **Completada técnicamente en local aislado.** Implementar `descuento_pedido` como snapshot autoritativo y la función PostgreSQL de subtotal, descuento y total neto, sin duplicar snapshots en `pedido`. | T02, T03 | Snapshot autorizado, motivo/actores y total neto servidor conforme a DT-01. Evidencia en `implementation-t06.md`. | R09–R10 / TP19–TP25 | 4 h |
| E1-T07 | **Completada técnicamente en local aislado.** Implementar anulación directa por `ADMINISTRADOR`, con motivo, y bloqueo ante cualquier pago confirmado. | T02, T06 | Actor administrador, fecha/hora, estados anterior/nuevo, terminalidad, mesa e historial consistentes; sin solicitante/autorizador separados. Evidencia en `implementation-t07.md`. | R11–R12 / TP26–TP30 | 3 h |
| E1-T08 | **Completada técnicamente en local aislado.** Evolucionar estructuralmente `pago` y migrar contrato legacy para múltiples filas, sesión, propina e idempotencia, conservando temporalmente el cobro total H5. | T03, T04 | Filas históricas preservadas sin sesión fabricada; pagos nuevos con sesión abierta, actor, propina e idempotencia; esquema preparado sin habilitar parciales. Evidencia en `implementation-t08.md`. | R13–R17 / aspectos estructurales/legacy de TP31–TP35 | 4 h |
| E1-T09 | **Completada técnicamente en local aislado, incluido delta TP62.** Evolucionar el contrato a una cabecera `cobro` con N filas `pago`, RPC atómica, idempotencia por acto y orden `sesion_caja → pedido → mesa`; preservar legacy y cobros parciales como actos separados. | T05, T06, T08 | Un cobro confirma todos sus medios o ninguno; no hay sobrepago, duplicación ni pérdida de trazabilidad. Evidencia histórica y delta en `implementation-t09.md`. | R13–R17 / TP31–TP47 aplicables | 5 h |
| E1-T10 | **Completada técnicamente, con ajustes TP62 en curso.** Adaptar Caja para componer N medios dentro de un cobro normal/parcial y presentar movimientos en grilla sobre lectura autorizada y registro batch atómico; mantener las demás capacidades existentes. | Delta T09 + lecturas agrupadas | Cobro normal/parcial conserva snapshot servidor; movimientos históricos bloqueados y filas nuevas se guardan juntas, refrescando esperado y trazabilidad. Evidencia en `implementation-t10.md`. | R04/R19–R20/R22 / TP13–TP16, TP49–TP55 y TP59–TP60 aplicables; R13–R18 / TP32–TP48 | 7 h |
| E1-T11 | **Completada técnicamente en local aislado, incluida regresión delta.** Ajustar auditoría para un evento lógico por `cobro` y verificar inmutabilidad/aislamiento sin crear eventos nuevos. | Delta T09 | Reconstrucción por sesión/pedido/cobro con detalle de medios, sin N auditorías lógicas por un mismo acto. Evidencia en `implementation-t11.md`. | R19–R20 / TP49–TP55 aplicables | 4 h |
| E1-T12 | **Completada técnicamente en local aislado, incluida regresión delta.** Ajustar lecturas/reportes/exportación para agrupar por cobro y sumar cada fila por medio sin duplicar venta ni conteo de pedido. | Delta T09–T11 | Totales por medio, efectivo esperado, venta, propina y documentos concilian con cobros multi-medio. Evidencia en `implementation-t12.md`. | R21 / TP56–TP58 aplicables | 4 h |
| E1-T13 | **Completada técnicamente — checkpoint delta aprobado.** Puerta integral del modelo/contrato de cobro: replay, SQL, seguridad, concurrencia, Node, `typecheck` y `build`. | Deltas T09–T12 | Cobertura técnica TP01–TP61 vigente sobre la versión final antes de volver a TP62. Evidencia en `implementation-t13.md`. | Todos / TP afectados y TP61 | 5 h |
| E1-T14 | **EN VALIDACIÓN HUMANA, pausada en TP62.** Reanudar pruebas humanas sólo después del nuevo checkpoint T13 y Preview DEV actualizado; documentar evidencia y solicitar aceptación. | Nuevo checkpoint T13, deployment Preview DEV | TP62–TP64 aprobadas; no crear aceptación sin aprobación explícita. | Todos / TP62–TP64 | 4 h |

## Dependencias y orden

1. T01–T02 están completadas en Spec Mode; la construcción comienza en T03.
2. T03–T04 establecen caja, sesión y apertura. T08 adelanta exclusivamente la estructura/compatibilidad legacy de `pago` necesaria para asociar cobros y propinas a sesión.
3. T05 depende de T04 + T08 para calcular efectivo esperado y ejecutar TP18 cierre-vs-cobro sin inferencias por fecha.
4. T06 define el total neto; T07 comparte locks/auditoría. El delta T09 depende de T05 + T06 + T08 y agrega la identidad del acto de cobro, composición atómica de medios y parciales separados.
5. El orden del ajuste es T09 (modelo/RPC/lecturas mínimas) → T10 (UI/documentos) → T11 (auditoría) → T12 (reportes) → T13 (checkpoint). T14/TP62 sólo se reanudan después.
6. PM-002 `TRANSITIONING` condiciona el ambiente: construcción/verificación en DEV/Preview no habilita PROD ni modifica el plan de cutover.

## Estrategia de validación durante construcción

La cobertura final TP01–TP64 y el criterio de aceptación no cambian. Para evitar regresiones integrales repetidas durante la construcción:

1. T03–T12 ejecutan los TP propios de la tarea y sólo las regresiones directamente afectadas por los archivos, esquema o contratos modificados.
2. Una prueba ya aprobada no se repite dentro de la misma tarea salvo que un cambio pueda invalidarla, haya fallado y sido corregida, o sea necesaria para verificar una interacción nueva.
3. La suite Node completa no se ejecuta automáticamente después de cada tarea. Un cambio exclusivamente SQL tampoco obliga por sí solo a repetir `typecheck` o `build`.
4. La concurrencia con conexiones independientes se ejecuta únicamente cuando el plan de pruebas exige una carrera para la tarea.
5. Los fingerprints completos de datos legacy sólo se repiten si la tarea modifica datos, esquema o contrato legacy.
6. Se reutiliza una baseline local previamente validada para comprobaciones incrementales. El replay limpio desde las migraciones históricas se reserva para migraciones que lo requieran y para checkpoints.
7. La evidencia original de T08 conserva validez para estructura/compatibilidad legacy de `pago`; el delta T09 deberá repetir los invariantes legacy afectados por agregar `cobro_id`, sin fabricar cabeceras retroactivas.
8. T09 será el checkpoint ampliado del núcleo financiero T03–T09.
9. T13 conserva la puerta integral definitiva: TP01–TP61, SQL, seguridad, concurrencia, regresión H1–H6/PM-001, `typecheck` y `build`.

## Ajuste detectado durante TP62

El comportamiento construido trataba cada fila `pago` como un acto independiente. La decisión homologada exige que un acto pueda contener N medios y producir una sola confirmación/documento. El delta de T09–T13 deberá:

1. agregar `cobro` y la relación `pago.cobro_id` mediante migración nueva, preservando pagos legacy sin fabricar agrupaciones;
2. sustituir la escritura cliente por una RPC de cobro completo atómica e idempotente;
3. mantener `Cobrar una parte` como otro acto, no como sinónimo de agregar un medio;
4. ajustar lecturas, documentos, auditoría y reportes para agrupar por cobro;
5. ejecutar sólo las regresiones invalidadas y terminar con el checkpoint integral aplicable antes de volver a T14.

Esta homologación no autoriza implementación, migración ni despliegue. Las horas existentes se conservan como estimación aprobada de las unidades T01–T14; cualquier variación real del delta deberá estimarse al autorizar su construcción, sin alterar la referencia histórica de 30–40 horas.

## Estimación

La estimación de construcción excluye T01–T02 ya realizadas en Spec Mode y asume las decisiones cerradas sin iteraciones mayores:

| Alcance | Construcción futura | Con Spec Mode T01–T02 | Comparación con plan 30–40 h |
|---|---:|---:|---|
| Operación financiera de caja | **53 h** | **59 h** | +13 h sobre máximo de referencia (construcción) |

La referencia histórica de **30–40 horas** se conserva intacta. T01 (4 h) y T02 (2 h) suman **6 h de Spec Mode completado**; T03–T14 suman **53 h de construcción futura**; el total planificado de E1 permanece en **59 h**. La aprobación de decisiones cambia el estado de T02, no su estimación ni el total. El alcance financiero todavía supera la referencia; no se fuerza la cifra ni se elimina trazabilidad o seguridad.

## Riesgos de planificación

- Cambiar la DF-09 aprobada para exigir asignación histórica por detalle introduciría `pago_detalle` y ampliaría modelo, pruebas y estimación.
- Datos legacy y estado real de DEV deben verificarse antes de diseñar migración ejecutable.
- Ninguna cifra autoriza construcción, cambios remotos ni cierre de PM-002.
