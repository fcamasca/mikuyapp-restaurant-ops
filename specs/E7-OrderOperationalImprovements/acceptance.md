# MikuyApp — Aceptación E7: Mejoras operativas de pedidos

**Fecha de aceptación:** 30/09/2026
**Estado:** CERRADA, VALIDADA Y ACEPTADA

## 1. Declaración de aceptación

El responsable aprobó humanamente la **Evolución 7 — Mejoras operativas de pedidos** el 30/09/2026, después de la validación técnica (T02–T11) y de las pruebas humanas TH01–TH07 (T12), y autorizó su cierre y la preparación de la rama `feature/E7-OrderOperationalImprovements` para integración a `main`.

El cierre documental **no** implica despliegue a producción, no realiza el cutover de PM-002 y no modifica `mikuyapp-prod`.

## 2. Alcance aceptado

Alcance aprobado en el Spec del 23/09/2026 (`requirements.md` E7-R01–E7-R33, `design.md` E7-D01–E7-D20), sin ampliaciones:

- condición **requiere cocina** configurable por el administrador (por defecto sí) y snapshot por detalle;
- productos sin cocina: al enviarse quedan `LISTO`, no generan comanda ni aparecen en cocina; pedidos mixtos con estado agregado coherente, sin estados nuevos;
- **recepción completa** del pedido en cocina, idempotente y segura ante doble clic, reintentos y concurrencia, conservando el avance individual por producto;
- **cancelación por el mozo** de productos `ENVIADO`/`RECIBIDO_COCINA`, por línea completa y con motivo, con recálculo de total, pedido y mesa; productos sin cocina ya enviados no se cancelan;
- trazabilidad de cambios de estado y cancelaciones (`historial_detalle_pedido`);
- corrección HZ-01: edición y retiro de borradores `ABIERTO` vía RPC con el mismo orden transaccional, conservando las capacidades H3;
- **comandas** opcionales por envío con primera impresión única y reimpresiones registradas, impresas con `window.print()` hacia la impresora del sistema operativo del dispositivo `COCINA`, sin alterar el flujo digital;
- sincronización Realtime como señal y recarga autoritativa en mozo, cocina y caja.

Fuera de E7 (sin cambios): solicitud de cuenta del mozo a caja, nuevos mecanismos de división de cuenta, inventario, recetas y facturación electrónica.

## 3. Resultado de la validación humana (T12)

| Prueba | Resultado |
|---|---|
| E7-TH01 — ADMIN configura productos con y sin cocina | Aprobada |
| E7-TH02 — Mozo: pedido mixto, edición/retiro de borradores | Aprobada |
| E7-TH03 — Cocina: recepción completa y avance individual | Aprobada |
| E7-TH04 — Cancelación del mozo con cocina operando | Aprobada |
| E7-TH05 — Impresión física de comandas | Aprobada |
| E7-TH06 — Flujo completo mixto hasta entrega y cobro | Aprobada tras corregir dos defectos (§5) |
| E7-TH07 — Uso táctil y responsive | Aprobada |

Las aprobaciones corresponden a la decisión humana del responsable; el detalle está en `implementation-t12.md`.

## 4. Pruebas técnicas finales

| Validación | Resultado | Evidencia |
|---|---|---|
| Construcción focalizada T02–T09 | Aprobada | `implementation-t02-t05b.md`, `implementation-t06-t09.md` |
| Integración T10 (Supabase local real: PostgreSQL 17.6, PostgREST v14.5, Auth v2.196.0, Realtime v2.129.0) | Técnicamente completa, con desviación de ambiente aprobada | `implementation-t10.md` |
| Campaña integral T11: replay limpio de 57 migraciones, TP01–TP31, SQL E7 y del repositorio, carreras R1–R15, RLS/grants/`service_role`, 0 funciones con `40001` manual | Aprobada; fallos históricos clasificados sin regresiones reales | `implementation-t11.md` |
| Verificación cloud DEV (`ibfr…uinf`) de las correcciones de TH06 | #46 y #47 resincronizados con el mozo en mesas; #48 desde la pantalla del pedido con retorno a mesas ≈330 ms | `implementation-t12.md` §5 |
| Validación de cierre (Windows, 30/09/2026, sobre `4f780eb` + documentos de cierre): `npm run typecheck` | PASS | `e7-cierre-validacion.log` (local, no versionado) |
| `npm run build` | PASS (88 módulos; sólo el aviso conocido de chunk > 500 kB) | ídem |
| Suite Node completa | **391/391 PASS** | ídem |

No se repitió la campaña SQL en el cierre: la base de datos no cambió desde T11 (última migración `20260924000800_e7_t10_privilegios_supabase.sql`) y las correcciones de T12 son exclusivamente de frontend.

## 5. Defectos encontrados durante la validación y correcciones

| Momento | Defecto | Corrección |
|---|---|---|
| T10 | Los privilegios por defecto de Supabase dejaban a `service_role` con `ALL`/`TRUNCATE` sobre `historial_detalle_pedido` y `comanda` y `EXECUTE` sobre funciones E7. | Migración nueva `20260924000800_e7_t10_privilegios_supabase.sql` (`78e43d0`). |
| T11 | Prueba histórica `catalogSecurity` no contemplaba la concesión aditiva `requiere_cocina` (E7-D02). | Ajuste de la prueba sin reducir invariantes (`9cdba08`). |
| T12 / TH06 (1ª falla) | Tras el cobro total, un pedido `PAGADO` deja de ser visible para el mozo y la UI confundía esa ausencia esperada con un error de conexión (“No pudimos cargar el pedido vigente”). | `94f98ee`: se distingue “pedido ya no vigente” de un error real; la vista vuelve a mesas desde la señal Realtime, la carga y `Reintentar`. |
| T12 / TH06 (2ª falla) | Tras desmontaje/remontaje de una vista (React `StrictMode`, recarga del perfil por `SIGNED_IN`/`TOKEN_REFRESHED`), `supabase-js` reutilizaba el canal Realtime con el mismo nombre que todavía se estaba cerrando y la pantalla quedaba sin suscripción. | `bbf9edd`: nombre de canal único por suscripción; se mantiene Realtime como señal → refetch autoritativo, sin polling. Instrumentación temporal de diagnóstico retirada (`3ad50a0`). |

## 6. Estado de defectos y pendientes

- **Defectos bloqueantes abiertos: 0.**
- **Pendiente menor aceptado como no bloqueante:** texto de UX “1 línea” → “1 producto”. No se implementa en E7.
- **Fuera de E7 (procesos independientes):** despliegue a producción; PM-002 continúa `TRANSITIONING` y la revalidación cloud previa a release sigue su propio proceso; hallazgo de T11 sobre `h3_abrir_o_recuperar_pedido` (recreada por E1-T18) registrado para tratamiento aparte; homologación formal de pruebas históricas afectadas por E1-T18/E7 (`implementation-t11.md` §5).

## 7. Commits relevantes

| Commit | Contenido |
|---|---|
| `d7cb0fd` | Spec aprobado |
| `606ed94`–`818e9c4` | T02–T05B: modelo, envío, cocina, cancelación, edición/retiro (HZ-01) |
| `49eaf3e`, `c374f9b`, `bd8ca7b`, `f99ff5b` | T06–T09: administración, mozo, cocina, comandas |
| `78e43d0` | T10: privilegios Supabase (`…800`) |
| `9cdba08` | T11: validación integral |
| `94f98ee`, `bbf9edd` | T12: correcciones de TH06 |
| `3ad50a0`, `4f780eb` | T12: retiro de instrumentación y aprobación de TH06 |

## 8. Conclusión

La **Evolución 7 — Mejoras operativas de pedidos** queda **CERRADA, VALIDADA Y ACEPTADA** el 30/09/2026, sin defectos bloqueantes abiertos, y la rama queda lista para su integración a `main` por decisión del responsable.
