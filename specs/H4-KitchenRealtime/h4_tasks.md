# MikuyApp — H4 Cocina en tiempo real: tareas

## Estado

El Spec fue aprobado humanamente. H4-T01–H4-T06 están implementadas y validadas; H4-T07–H4-T10 permanecen pendientes.

## Plan de construcción propuesto

| Estado | ID | Tarea | Diseño | Requisitos | Est. h |
|---|---|---|---|---|---:|
| [x] | H4-T01 | Crear cambio mínimo de modelo para `detalle_pedido.enviado_en`, backfill compatible, constraint e índice de antigüedad; adaptar el envío existente para fijar el timestamp en servidor una sola vez. | H4-D01, H4-D05 | H4-R03, H4-R10 | 0.75 |
| [x] | H4-T02 | Implementar snapshot seguro `obtener_tablero_cocina`, sus privilegios y lecturas RLS mínimas por rol/local. | H4-D02, H4-D08 | H4-R01, H4-R02, H4-R05 | 0.75 |
| [x] | H4-T03 | Implementar `actualizar_estado_detalle_cocina` con transición adyacente, lock, estado esperado, auditoría y rollback. | H4-D03, H4-D05, H4-D08, H4-D09 | H4-R04–H4-R06, H4-R10, H4-R13 | 1.00 |
| [x] | H4-T04 | Implementar derivación agregada actual de cabecera, historial de cada cambio real y sincronización de mesa; ajustar alta posterior para cabecera `→ ABIERTO` y mesa `PEDIDO_LISTO → OCUPADA`. | H4-D04 | H4-R07–H4-R10 | 1.00 |
| [x] | H4-T05 | Configurar publicación Realtime y ciclo de snapshot/suscripción/resincro en un servicio reutilizable; tratar eventos como señales para recargar, con debounce opcional y sin polling. | H4-D06, H4-D08, H4-D09 | H4-R11–H4-R13 | 1.00 |
| [x] | H4-T06 | Construir ruta y tablero de cocina con agrupación por pedido/mesa, antigüedad, tiempo, estados y acciones táctiles. | H4-D02, H4-D03, H4-D07, H4-D10 | H4-R01–H4-R04, H4-R07, H4-R14 | 1.25 |
| [ ] | H4-T07 | Integrar Realtime en cocina para nuevos detalles, actualizaciones, recarga autoritativa, errores y reconexión, evitando duplicados mediante reemplazo del snapshot. | H4-D06, H4-D07, H4-D09 | H4-R07, H4-R11–H4-R14 | 0.75 |
| [ ] | H4-T08 | Integrar señal/recarga Realtime en tablero y pedido del mozo para reflejar detalle, cabecera y mesa persistidos. | H4-D06, H4-D07 | H4-R09, H4-R11, H4-R12 | 0.50 |
| [ ] | H4-T09 | Ejecutar pruebas SQL, automatizadas, técnicas, concurrencia y regresión H1–H3; corregir únicamente defectos de H4. | H4-D01–H4-D10 | H4-R01–H4-R14 | 0.75 |
| [ ] | H4-T10 | Ejecutar validación humana responsive y de dos dispositivos; consolidar evidencia de H4 sin crear aceptación. | H4-D02, H4-D06, H4-D09, H4-D10 | H4-R01–H4-R14 | 0.75 |

**Estimación revisada:** 8.5 horas. El ajuste de derivación y la simplificación de Realtime no cambian materialmente las tareas previstas.

De las **4.5 horas** sobre las 4 originales, se recomienda clasificar **1.5 horas como aumento de alcance** atribuible a la evolución aprobada de estado individual por detalle y sus consecuencias: timestamp individual de envío, estados mixtos y recálculo transaccional de cabecera/mesa. Las **3.0 horas restantes son reestimación** de alcance ya presente en el plan original: tablero, Realtime, reconexión, dos dispositivos, seguridad y validación. `CHANGELOG_SCOPE.md` no se modifica hasta la aprobación humana del Spec.

## Dependencias y secuencia

```text
T01 → T02 → T03 → T04
  └───────────────┬──→ T05 → T06 → T07 → T08 → T09 → T10
                  └─────────────────────────────────────────
```

- T01–T04 establecen la autoridad PostgreSQL antes de exponer acciones en UI.
- T05 define el patrón Realtime reutilizado por cocina y mozo.
- T09 debe completar toda verificación obligatoria antes de T10.
- T10 no acepta H4; solo deja evidencia lista para una decisión humana posterior.

## Matriz de trazabilidad

| Requisito | Diseño | Tareas | Pruebas |
|---|---|---|---|
| H4-R01 | H4-D02, H4-D07, H4-D08 | H4-T02, H4-T06, H4-T09, H4-T10 | H4-TA01, H4-TM01, H4-TH01 |
| H4-R02 | H4-D02 | H4-T02, H4-T06, H4-T09 | H4-TA02, H4-TA03, H4-TH01 |
| H4-R03 | H4-D01, H4-D02 | H4-T01, H4-T06, H4-T09 | H4-TA04, H4-TM02, H4-TH02 |
| H4-R04 | H4-D03 | H4-T03, H4-T06, H4-T09 | H4-TA05, H4-TA06, H4-TM03, H4-TH03 |
| H4-R05 | H4-D03, H4-D08 | H4-T02, H4-T03, H4-T09 | H4-TA07, H4-TM01, H4-TM04 |
| H4-R06 | H4-D03, H4-D09 | H4-T03, H4-T09 | H4-TA08, H4-TA09, H4-TM05 |
| H4-R07 | H4-D02, H4-D04, H4-D07 | H4-T04, H4-T06, H4-T07, H4-T09 | H4-TA10, H4-TA11, H4-TA12, H4-TH04 |
| H4-R08 | H4-D04 | H4-T04, H4-T09 | H4-TA13, H4-TA14, H4-TM06 |
| H4-R09 | H4-D04, H4-D07 | H4-T04, H4-T08, H4-T09 | H4-TA15, H4-TA16, H4-TM06, H4-TH05 |
| H4-R10 | H4-D04, H4-D05 | H4-T01, H4-T03, H4-T04, H4-T09 | H4-TA17, H4-TM07 |
| H4-R11 | H4-D06, H4-D07 | H4-T05, H4-T07, H4-T08, H4-T09 | H4-TA18, H4-TA19, H4-TH04, H4-TH05 |
| H4-R12 | H4-D06, H4-D09 | H4-T05, H4-T07, H4-T08, H4-T09 | H4-TA20, H4-TA21, H4-TM08, H4-TH06 |
| H4-R13 | H4-D03, H4-D06, H4-D09 | H4-T03, H4-T05, H4-T07, H4-T09 | H4-TA09, H4-TA22, H4-TM05, H4-TH06 |
| H4-R14 | H4-D02, H4-D10 | H4-T06, H4-T07, H4-T10 | H4-TA23, H4-TM09, H4-TH01, H4-TH02 |

## Condición de cierre de tareas

Ninguna tarea se marca completada con pruebas obligatorias pendientes. H4-T10 solo puede declararse completada cuando los resultados automatizados, técnicos y humanos estén registrados sin inventar evidencia. `acceptance.md` corresponde a una aprobación humana posterior y no forma parte de estas tareas.
