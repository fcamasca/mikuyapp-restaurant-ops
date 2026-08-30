# MikuyApp — Cambios aprobados de alcance

Este registro consolida desviaciones y decisiones aprobadas respecto al plan inicial del MVP. No reemplaza el plan, los Specs ni sus aceptaciones. Los tiempos no documentados se mantienen como `No registrado`.

| ID | Fecha | Hito | Cambio | Motivo | Impacto | Estimación adicional | Tiempo real | Estado | Referencia |
|---|---|---|---|---|---|---:|---|---|---|
| CH-001 | 2026-08-25 | H2 | Ampliación de usuarios, carta y mesas hasta administración completa, seguridad y pruebas integrales. | Completar integridad, RLS y operación administrativa necesaria para el MVP. | Frontend, PostgreSQL, RLS y pruebas. | 5 h | No registrado | Aprobado | `docs/PLAN_MVP.md`; `specs/H2-UsersCatalogTables/h2_acceptance.md` |
| CH-002 | 2026-08-27 | H3 | Flujo del mozo robustecido con estado individual por detalle, envíos posteriores selectivos, seguridad y concurrencia. | Mantener trazabilidad por plato y permitir agregados posteriores sin retroceder la cabecera. | Modelo, funciones, RLS, UI y pruebas. | 2 h | No registrado | Aprobado | `specs/H3-WaiterFlow/acceptance.md`; H3-R01–H3-R11 |
| CH-003 | 2026-08-27 | H3 | Consolidación de detalles `ABIERTO` equivalentes por producto y observación. | Evitar líneas duplicadas antes del envío sin fusionar platos ya enviados. | Función de alta, concurrencia y UI. | No registrado | No registrado | Aprobado | H3-R05; H3-D04; H3-T07 |
| CH-004 | 2026-08-27 | H3 | Liberación manual de mesa con pedido `ABIERTO` vacío, anulando el pedido y registrando historial. | Recuperar mesas tomadas por error sin eliminar trazabilidad. | Función transaccional, UI y pruebas. | No registrado | No registrado | Aprobado | H3-R12; H3-D11; H3-TA16/H3-TM08/H3-TH09 |
| CH-005 | 2026-08-27 | H3 | Auditoría de creación/modificación en pedido y detalle, con creador visible en la mesa. | Identificar autor original y último actor sin agregar responsable a `mesa`. | Modelo, triggers, función de lectura, servicio, UI y pruebas. | No registrado | No registrado | Implementado y validado | H3-ER01; H3-ED01; H3-E01 |
| CH-006 | 2026-08-27 | H4 | Estado operativo individual en cocina, timestamp de envío por detalle, derivación transaccional y Realtime robusto. | Resolver estados mixtos, agregados posteriores, concurrencia y recuperación sin perder autoridad PostgreSQL. | Modelo, funciones, RLS, Realtime, UI y pruebas. | 1.5 h | No registrado | Aprobado | `specs/H4-KitchenRealtime/acceptance.md`; H4-R01–H4-R14 |
| CH-007 | 2026-08-30 | H5 | Reestimación de H5 de 4 h a 12 h para entrega segura, caja, cobro e impresión. | Cubrir transacciones e idempotencia, concurrencia, seguridad por rol/local, Realtime robusto, impresión térmica de 80 mm y validación técnica/humana integral. | Funciones PostgreSQL, RLS/privilegios mínimos, UI de mozo/caja, Realtime, impresión y pruebas. | 8 h | No registrado | Aprobado | `specs/H5-DeliveryCashPaymentPrint/acceptance.md`; H5-R01–H5-R12 |

## Lectura de esfuerzo

El plan inicial consideraba **24 h**. Las ampliaciones con estimación adicional documentada suman actualmente **16.5 h** (`CH-001` + `CH-002` + `CH-006` + `CH-007`), por lo que la referencia planificada revisada es **40.5 h**. Esto no equivale a tiempo real consumido: el tiempo real sigue sin estar consolidado y no se infiere.

Para H4, la estimación original fue **4 h** y la estimación revisada **8.5 h**. La desviación aprobada se clasifica en **+1.5 h de aumento de alcance** y **+3.0 h de reestimación del alcance original**. El tiempo real de H4 queda como **No registrado** por falta de evidencia consolidada suficiente.

Para H5, la estimación anterior fue **4 h** y la estimación aprobada del Spec fue **12 h**. La desviación de **+8 h** refleja el alcance real de entrega segura, caja, concurrencia, seguridad, Realtime, impresión y pruebas. Es una referencia de planificación; el tiempo real de H5 permanece como **No registrado**.
