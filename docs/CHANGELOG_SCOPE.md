# MikuyApp — Cambios aprobados de alcance

Este registro consolida desviaciones y decisiones aprobadas respecto al plan inicial del MVP. No reemplaza el plan, los Specs ni sus aceptaciones. Los tiempos no documentados se mantienen como `No registrado`.

| ID | Fecha | Hito | Cambio | Motivo | Impacto | Estimación adicional | Tiempo real | Estado | Referencia |
|---|---|---|---|---|---|---:|---|---|---|
| CH-001 | 2026-08-25 | H2 | Ampliación de usuarios, carta y mesas hasta administración completa, seguridad y pruebas integrales. | Completar integridad, RLS y operación administrativa necesaria para el MVP. | Frontend, PostgreSQL, RLS y pruebas. | 5 h | No registrado | Aprobado | `docs/PLAN_MVP.md`; `specs/H2-UsersCatalogTables/h2_acceptance.md` |
| CH-002 | 2026-08-27 | H3 | Flujo del mozo robustecido con estado individual por detalle, envíos posteriores selectivos, seguridad y concurrencia. | Mantener trazabilidad por plato y permitir agregados posteriores sin retroceder la cabecera. | Modelo, funciones, RLS, UI y pruebas. | 2 h | No registrado | Aprobado | `specs/H3-WaiterFlow/acceptance.md`; H3-R01–H3-R11 |
| CH-003 | 2026-08-27 | H3 | Consolidación de detalles `ABIERTO` equivalentes por producto y observación. | Evitar líneas duplicadas antes del envío sin fusionar platos ya enviados. | Función de alta, concurrencia y UI. | No registrado | No registrado | Aprobado | H3-R05; H3-D04; H3-T07 |
| CH-004 | 2026-08-27 | H3 | Liberación manual de mesa con pedido `ABIERTO` vacío, anulando el pedido y registrando historial. | Recuperar mesas tomadas por error sin eliminar trazabilidad. | Función transaccional, UI y pruebas. | No registrado | No registrado | Aprobado | H3-R12; H3-D11; H3-TA16/H3-TM08/H3-TH09 |
| CH-005 | 2026-08-27 | H3 | Auditoría de creación/modificación en pedido y detalle, con creador visible en la mesa. | Identificar autor original y último actor sin agregar responsable a `mesa`. | Modelo, triggers, función de lectura, servicio, UI y pruebas. | No registrado | No registrado | Implementado y validado | H3-ER01; H3-ED01; H3-E01 |

## Lectura de esfuerzo

El plan inicial consideraba **24 h**. Las ampliaciones con estimación adicional documentada suman actualmente **7 h** (`CH-001` + `CH-002`), por lo que la referencia planificada revisada es **31 h**. Esto no equivale a tiempo real consumido: el tiempo real sigue sin estar consolidado y no se infiere.
