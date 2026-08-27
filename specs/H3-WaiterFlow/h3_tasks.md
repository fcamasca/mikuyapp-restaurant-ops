# MikuyApp — H3 Flujo del mozo: tareas

## Estado de ejecución

- [x] H3-T01 — Cambio mínimo de modelo implementado, migrado y validado contra Supabase remoto.
- [x] H3-T02 — Creación o recuperación transaccional del pedido implementada, validada y aprobada.
- [x] H3-T03 — Alta segura de detalles implementada y validada; precio y estado controlados por PostgreSQL.
- [x] H3-T04 — Privilegios por columna y RLS para modificar o retirar únicamente detalles `ABIERTO` implementados y validados.
- [x] H3-T05 — Envío transaccional, selectivo e idempotente implementado y validado, incluida concurrencia real y rollback completo.
- [ ] H3-T06 — Pendiente.
- [ ] H3-T07 — Pendiente.
- [ ] H3-T08 — Pendiente.
- [ ] H3-T09 — Pendiente.
- [ ] H3-T10 — Pendiente.

## 1. Plan de construcción posterior a la aprobación del Spec

| ID | Trabajo | Diseño | Requisitos | Horas |
|---|---|---|---|---:|
| H3-T01 | Preparar el cambio mínimo de modelo: estado de detalle, checks, índice por pedido/estado e índice único de pedido vigente. | H3-D01 | H3-R03, H3-R09, H3-R10 | 0.50 |
| H3-T02 | Implementar `crear_o_recuperar_pedido_mesa`, historial inicial y ocupación segura de mesa. | H3-D03, H3-D09 | H3-R02, H3-R03, H3-R11 | 0.75 |
| H3-T03 | Implementar `agregar_detalle_pedido` con precio obtenido en servidor y estado `ABIERTO` obligatorio. | H3-D04, H3-D09 | H3-R05, H3-R11 | 0.50 |
| H3-T04 | Implementar privilegios por columna y RLS para modificar cantidad/observación y retirar únicamente detalles `ABIERTO`. | H3-D05, H3-D09 | H3-R06, H3-R07, H3-R11 | 0.50 |
| H3-T05 | Implementar `enviar_pedido_cocina` selectiva, atómica e idempotente: detalles abiertos a enviados, cabecera solo `ABIERTO → ENVIADO` en el primer envío y conservación posterior de estado y `enviado_en`. | H3-D07, H3-D09 | H3-R09, H3-R11 | 0.75 |
| H3-T06 | Adaptar tablero de mesas con cards, estados, total, filtros, orden y navegación. | H3-D02, H3-D06 | H3-R01, H3-R03 | 0.50 |
| H3-T07 | Construir cards de productos, filtro por categoría y controles táctiles de cantidad/observación/retiro. | H3-D02, H3-D04, H3-D05 | H3-R04, H3-R05, H3-R06, H3-R07 | 0.75 |
| H3-T08 | Implementar revisión, total persistido, separación por enviar/solicitado y agregados posteriores. | H3-D06, H3-D08 | H3-R08, H3-R10 | 0.50 |
| H3-T09 | Manejar recuperación, errores, reintentos, doble clic y concurrencia en UI/servicios. | H3-D03, H3-D07, H3-D09 | H3-R02, H3-R03, H3-R09, H3-R10, H3-R11 | 0.50 |
| H3-T10 | Ejecutar y documentar pruebas automatizadas, técnicas manuales y humanas. | H3-D01–H3-D10 | H3-R01–H3-R11 | 0.75 |

## 2. Estimación revisada

**Total: 6 horas.** H3 tiene 4 horas previstas para los días 5 y 6 del plan; la desviación es de **+2 horas (+50 %)**. La revisión mantiene la estimación porque la función única de alta evita complejidad innecesaria, pero siguen siendo indispensables el cambio de modelo, la creación transaccional del pedido, el envío selectivo, RLS/privilegios por columna, concurrencia y las tres capas de pruebas. No se reduce seguridad, atomicidad ni cobertura para forzar las 4 horas.

## 3. Matriz de trazabilidad completa

| Requisito | Diseño | Tareas | Pruebas |
|---|---|---|---|
| H3-R01 | H3-D02, H3-D06 | H3-T06, H3-T10 | H3-TH01, H3-TH02 |
| H3-R02 | H3-D03, H3-D09 | H3-T02, H3-T09, H3-T10 | H3-TA01, H3-TA02, H3-TM01 |
| H3-R03 | H3-D01, H3-D03 | H3-T01, H3-T02, H3-T06, H3-T09, H3-T10 | H3-TA03, H3-TM02, H3-TH03 |
| H3-R04 | H3-D02 | H3-T07, H3-T10 | H3-TH04, H3-TH05 |
| H3-R05 | H3-D04, H3-D09 | H3-T03, H3-T07, H3-T10 | H3-TA04, H3-TA05, H3-TM03, H3-TM04 |
| H3-R06 | H3-D05, H3-D06 | H3-T04, H3-T07, H3-T10 | H3-TA06, H3-TA07, H3-TM05 |
| H3-R07 | H3-D02, H3-D05 | H3-T04, H3-T07, H3-T10 | H3-TA08, H3-TH06 |
| H3-R08 | H3-D06 | H3-T08, H3-T10 | H3-TA09, H3-TH07 |
| H3-R09 | H3-D01, H3-D07, H3-D09 | H3-T01, H3-T05, H3-T09, H3-T10 | H3-TA10, H3-TA11, H3-TA12, H3-TM06 |
| H3-R10 | H3-D01, H3-D08 | H3-T01, H3-T08, H3-T09, H3-T10 | H3-TA13, H3-TA14, H3-TH08 |
| H3-R11 | H3-D04, H3-D05, H3-D07, H3-D09 | H3-T02–H3-T05, H3-T09, H3-T10 | H3-TA05, H3-TA07, H3-TA11, H3-TA15, H3-TM03–H3-TM07 |

## 4. Condición de inicio y cierre

Estas tareas no se inician hasta que una persona apruebe explícitamente los cuatro documentos del Spec. Completar tareas y pruebas no crea por sí solo aceptación; `acceptance.md` se redactará después de construcción, pruebas humanas y aprobación explícita.
