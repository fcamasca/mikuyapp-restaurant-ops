# E7 — Evidencia de construcción: T10 (integración)

Fecha: 24/09/2026. Rama `feature/E7-OrderOperationalImprovements`, desde el checkpoint T09 `ea37539` (árbol limpio). No constituye aceptación. T11 y T12 **no iniciadas**.

**Estado de T10: TÉCNICAMENTE COMPLETA con desviación de ambiente aprobada** (23/09/2026). Por decisión del responsable no se creó un tercer proyecto cloud ni se tocó el proyecto compartido: la validación final se ejecutó sobre el **stack Supabase local real** (Docker + Supabase CLI, §7). No se tocó Production, el proyecto Supabase compartido, `mikuyapp-prod` ni Cloudflare; PM-002 sigue sin completar.

Niveles de evidencia de T10:

- **PostgreSQL 16 mínimo** (§2): evidencia focal histórica.
- **Supabase local real** (§7): evidencia final de T10.
- **DEV/Preview cloud**: pendiente por PM-002, no ejecutado por riesgo sobre Production (§4).

Esta validación **no sustituye** la revalidación cloud previa a release/validación humana.

## 1. Baseline real del ambiente (verificación sin conexión)

| Dato | Resultado | Fuente |
|---|---|---|
| Estado PM-002 | `TRANSITIONING` | `docs/PM002_ENVIRONMENTS.md`, `.env.local` (`MIKUY_ENVIRONMENT_STATE`) |
| Destino DEV de Local/Preview | “Supabase actual compartido”; es **el mismo proyecto** que atiende Cloudflare Production (`SHARED`) hasta el cutover | `PM002_ENVIRONMENTS.md` (tabla de rutas) |
| Proyecto enlazado | `mikuyapp`; ref esperado = ref DEV (valores no publicados) | `supabase/.temp/linked-project.json`, `.env.local` |
| PostgreSQL real | **17.6.1.155** (imagen Supabase); PostgREST v14.5; GoTrue v2.196.0 | `supabase/.temp/*-version` (03/09/2026) |
| E1 / E1-T18 en DEV | Registrado como aplicado manualmente en DEV (E1-T15, T17, T18) | `specs/E1-CashOperation/tasks.md`; **no verificable desde esta sesión** |
| Conectividad | Sin acceso a `*.supabase.co`, `supabase.com` ni `api.supabase.com` desde el contenedor ni desde el equipo (proxy de salida: `connect_rejected`) | Intentos `curl` read-only con la clave publicable → HTTP 000 |

## 2. Integración local (entorno previsto por el Spec)

Ambiente: PostgreSQL 16.13 local aislado + *shim* de Supabase. Para acercarlo al ambiente real se **emularon los privilegios por defecto de Supabase** (`ALTER DEFAULT PRIVILEGES … GRANT ALL ON TABLES/FUNCTIONS/SEQUENCES TO anon, authenticated, service_role`) antes de aplicar E7 sobre una copia de la baseline previa (49 migraciones hasta `20260922000100` + seed; sin replay completo).

| Verificación | Resultado |
|---|---|
| Aplicación de `20260924000100`–`000700` sobre baseline con privilegios Supabase | OK |
| Defecto detectado (ver §3) y corrección `20260924000800` | OK |
| SQL focales E7 T02–T09 sobre la base con privilegios Supabase | 6/6 PASS |
| Carreras reales `scripts/e7_concurrency.sh all` (R1–R15) | 0 fallos, 0 deadlocks, sin conexiones residuales |
| Recorrido integrado `supabase/tests/e7_t10_integracion.sql` | PASS (con y sin emulación de privilegios Supabase) |
| Contratos RPC del frontend vs funciones en BD (nombre, argumentos con nombre, `EXECUTE` a `authenticated`) — 13 RPC usadas por flujos E7 | 13/13 OK |

Recorrido integrado (dos mozos y dos cocinas del mismo local, `ROLLBACK` final):

1. Mozo A: pedido mixto (2 ceviches con cocina, 1 ceviche a retirar, chicha sin cocina).
2. Edición de borrador vía `rpc_modificar_detalle_pedido` y retiro vía `rpc_retirar_detalle_pedido`; el Mozo B con snapshot antiguo recibe `PT409`.
3. Envío: chicha `LISTO`, ceviches `ENVIADO`; comanda 1 sólo con ceviches.
4. Ambas cocinas obtienen el mismo snapshot, sin la chicha.
5. Primera solicitud de impresión (cocina 1); la cocina 2 recibe `PT409` y reimprime (2 solicitudes).
6. Recepción completa (cocina 1: 2 detalles); reintento de la cocina 2 = 0 sin error.
7. Mozo B cancela un ceviche `RECIBIDO_COCINA`; la cocina ve la cancelación; la transición de la cocina 2 sobre el cancelado → `PT409`; el mozo lo ve en “Cancelados”.
8. Avance individual del ceviche restante; cancelación en `EN_PREPARACION` rechazada (`PT409`) y COCINA no puede cancelar (`42501`); pedido `LISTO`, mesa `PEDIDO_LISTO`.
9. Entrega; agregado posterior (ceviche + chicha) → comanda 2 sólo con el ceviche nuevo; cocina lo completa; nueva entrega.
10. Caja: total autoritativo 114 (excluye la línea cancelada).
11. Historial de detalle: 13 eventos (`ENVIO`, `RECEPCION_COMPLETA` ×3, `TRANSICION_COCINA`, 1 `CANCELACION`).

Realtime (parte base de datos de TP27): en cada paso se verificó, como `authenticated` con los *claims* del suscriptor, que las filas-señal (`detalle_pedido`, `pedido`, `mesa`) son visibles por RLS para quien debe recibirlas (mozo B, cocina 1/2); incluida la señal `UPDATE` de `pedido` que produce la cancelación. La publicación `supabase_realtime` no cambia. **La entrega efectiva de eventos entre dispositivos no se pudo ejecutar**: requiere el servicio Realtime de Supabase (DEV), no disponible localmente.

## 3. Defecto encontrado y corregido

| Defecto | Causa | Corrección |
|---|---|---|
| En Supabase, `service_role` conserva `ALL` sobre `historial_detalle_pedido` y `comanda` (incluido `TRUNCATE`, que elude los triggers de inmutabilidad) y `EXECUTE` sobre las funciones de trigger y RPC de E7. | Los privilegios por defecto de Supabase conceden a `anon`, `authenticated` y `service_role`; E7 revocaba sólo `anon`/`authenticated`, a diferencia de la convención E1. No se manifestaba en PG16 sin emulación. | Migración nueva `20260924000800_e7_t10_privilegios_supabase.sql` (sin editar migraciones previas): revoca a `service_role` tablas, secuencias, funciones de trigger y RPC de E7; RPC sólo para `authenticated`. Reproducido: el bloque de privilegios de `e7_t10_integracion.sql` **falla sin la migración** y **pasa con ella**. |

## 4. Bloqueos para DEV/Preview (requieren decisión humana)

1. **Sin acceso desde esta sesión.** La política de red bloquea Supabase; además, aplicar migraciones requiere credenciales administrativas que no forman parte de esta sesión. Según el procedimiento usado en E1, la aplicación en DEV la ejecuta el responsable (manual/CLI enlazado).
2. **DEV comparte base con Production (PM-002 `TRANSITIONING`).** La migración `20260924000500` revoca `UPDATE`/`DELETE` directos sobre `detalle_pedido` y elimina sus políticas (E7-D15, DH-01). El frontend de `main` (`d1f0517`) todavía edita y retira con `from('detalle_pedido').update()/delete()` y el tablero de cocina usa `obtener_tablero_cocina`. Aplicar E7 al proyecto compartido **rompería editar/retirar borradores en Production** mientras ésta siga sirviendo el frontend de `main`. Las migraciones `…100`–`…400`, `…700` y `…800` son compatibles hacia atrás con ese frontend (aditivas; el envío sólo cambia para productos marcados sin cocina, que no existen hasta configurarlos); `…500`/`…600` no lo son.

Opciones para decidir (sin ejecutar ninguna):

- a) Aplicar E7 en el proyecto compartido sólo en una ventana coordinada con el despliegue a Production del frontend E7 (implica liberar E1 y E7 juntos; fuera del alcance de T10).
- b) Completar primero el cutover de PM-002 (Production → proyecto PROD) y luego aplicar E7 en el DEV ya exclusivo.
- c) Validar T10-DEV en otro proyecto Supabase aislado (p. ej., uno de pruebas) con la baseline E1 aplicada.

## 5. Diferencias PostgreSQL 16 local vs Supabase real

| Aspecto | Resultado |
|---|---|
| Migraciones | Aplican sin error en PG16; el SQL usado (PL/pgSQL, `jsonb`, `array_agg`, CTE con `UPDATE … RETURNING`, `FOR UPDATE`) es compatible con PG17. Pendiente la aplicación real en 17.6.1. |
| Funciones | Sin diferencias detectadas; revisión estática sin construcciones dependientes de versión. |
| RLS/grants | Diferencia real encontrada: privilegios por defecto de Supabase → corregida con `…800`. |
| PostgREST | Firmas y nombres de argumentos coinciden con las llamadas del frontend (13/13). `PT409` → HTTP 409 requiere PostgREST ≥ 12; el proyecto usa v14.5 (mismo mecanismo que E1-T18). No ejecutado contra PostgREST real. |
| Tipos | `bigint` (IDs) llega como número; `numeric` como texto/número y el frontend ya aplica `Number(...)`; `jsonb` del tablero se valida con `parseKitchenSnapshot`. Sin incompatibilidades detectadas en revisión. |
| Realtime | Publicación sin cambios; visibilidad RLS de señales verificada localmente; entrega efectiva pendiente de DEV. |

## 6. Pendiente

- Revalidación cloud previa a release/validación humana: aplicar `20260924000100`–`000800` en DEV una vez resuelto §4 (PM-002) y repetir `e7_t10_integracion.sql` + recorrido con dos dispositivos (Realtime cloud, comanda impresa desde Preview). La evidencia de §7 no la sustituye. Procedimiento de referencia: `t10-ambiente-validacion.md`.
- Para T11 (no iniciado): `typecheck`, `build`, suite completa, replay limpio total y tratamiento documentado de `h3_t04_open_order_detail_mutations.sql` y `order_audit_trail.sql`.

## 7. Validación final en Supabase local real (Docker + Supabase CLI)

Desviación de ambiente **aprobada por el responsable** (sustituye el proyecto aislado de `t10-ambiente-validacion.md`, que no se creó). Ejecutada el 23/09/2026 en el equipo del responsable con `scripts/e7_t10_local.cmd` → `scripts/e7_t10_local.ps1`, sobre el commit `c0ebdb0` + los ajustes de arnés de §7.5. Registro en `e7-t10-local.log` (ignorado por git). Sin claves en el registro: la salida de `supabase start` se filtra y las claves locales se leen de `supabase status` sin registrarlas. El runner nunca usa `link`, `--linked` ni `db push`.

### 7.1 Ambiente

| Componente | Versión / dato |
|---|---|
| Docker Engine | 29.7.2 (Docker Desktop, Windows) |
| Supabase CLI | 2.115.0 (`npx supabase`, dependencia del repositorio) |
| PostgreSQL | 17.6 (`supabase/postgres:17.6.1.155`, misma imagen que DEV) |
| PostgREST | v14.5 (igual que DEV) |
| Auth (GoTrue) | v2.196.0 (igual que DEV) |
| Realtime | v2.129.0 |
| Gateway | Kong 2.8.1 |
| Servicios excluidos | studio, imgproxy, mailpit, storage-api, edge-runtime, logflare, vector, supavisor, postgres-meta |
| Imágenes | Reutilizadas de E1; **ninguna descarga nueva** (listado antes/después idéntico) |

### 7.2 Reconstrucción y esquema

| Verificación | Resultado |
|---|---|
| `supabase db reset --local` (migraciones + `seed.sql`) | OK — **57 migraciones** en orden (49 de baseline hasta E1-T18 `20260922000100` + E7 `20260924000100`–`000800`); última `20260924000800`; seed OK |
| Publicación `supabase_realtime` | `detalle_pedido, mesa, pedido` (sin cambios) |
| Privilegios con roles reales (revalidación de `…800`) | `historial_detalle_pedido`, `comanda` y las 3 funciones de trigger E7: sin privilegios para `service_role`, `authenticated` ni `anon`. Las 7 RPC E7: sólo `authenticated`. Referencia E1 (`descuento_pedido`, `anulacion_pedido`): `service_role=false`, mismo criterio |

### 7.3 SQL y concurrencia en PostgreSQL 17 real

| Prueba | Resultado |
|---|---|
| `e7_t02_modelo`, `e7_t03_envio`, `e7_t04_recepcion_tablero`, `e7_t05_cancelacion`, `e7_t05b_edicion_retiro`, `e7_t09_impresion_comanda` | 6/6 PASS |
| `e7_t10_integracion.sql` (dos mozos y dos cocinas, visibilidad RLS de señales, bloque de privilegios `…800`) | PASS — 13 eventos de detalle, 2 comandas, total caja 114 |
| `scripts/e7_concurrency.sh all` (R1–R15) | **0 fallos**; sin `40001`, sin `40P01`, sin deadlocks, sin conexiones residuales |

### 7.4 Recorrido vía Auth + PostgREST + Realtime reales (`scripts/e7_t10_validation.mjs`, modo local)

Servicios reales del frontend (`waiterOrderService`, `kitchenRealtimeService`, `kitchenCommandService`, `operationsRealtimeService`) con **cuatro sesiones autenticadas por contraseña** (2 `MOZO`, 2 `COCINA`) y suscripciones Realtime reales. Resultado: **19/19 OK**.

| Paso | Resultado |
|---|---|
| Fixture aislada (local `E7-VAL-<run>`, 4 usuarios Auth, mesa, productos con y sin cocina) | OK |
| Edición vía `rpc_modificar_detalle_pedido`; snapshot antiguo → `PT409` de PostgREST → conflicto concurrente | OK |
| Retiro vía `rpc_retirar_detalle_pedido` | OK |
| Envío mixto; producto sin cocina → `LISTO` | OK |
| Realtime: la cocina recibe el envío sin la bebida y con comanda | OK (553 ms) |
| Primera solicitud de impresión concurrente de dos cocinas (una OK, otra `PT409`); reimpresión registrada | OK |
| Recepción completa (cocina 2); Realtime: cocina 1 ve `RECIBIDO_COCINA`; reintento = 0 sin error | OK (626 ms) |
| Cancelación de línea completa (mozo B); Realtime: la cocina recibe la cancelación; el mozo B resincroniza y la ve en “Cancelados” | OK (423 ms; la señal del mozo B llegó durante esa espera) |
| Transición de cocina sobre el cancelado → `PT409` | OK |
| Resincronización del snapshot autoritativo + documento imprimible (`COPIA 1`, línea `CANCELADO`) | OK |
| Cancelación en `EN_PREPARACION` bloqueada (`PT409`); pedido `LISTO` / mesa `PEDIDO_LISTO` | OK |

La impresión física no forma parte de T10 (E7-TH05, T12).

### 7.5 Diferencias de plataforma y ajustes de arnés (no son defectos de E7)

| Hallazgo | Tratamiento |
|---|---|
| La imagen Supabase local no concede a `service_role` privilegios sobre las tablas base de la baseline (`42501` en `rol` al crear la fixture vía PostgREST). | Sólo en el script de validación, modo local: la fixture de tablas se crea con `psql` como `postgres` en el contenedor local; `service_role` se usa únicamente para Auth admin (crear usuarios). Las operaciones E7 siguen vía sesiones `authenticated` y PostgREST. El modo cloud no cambia. |
| En Supabase real hay conexiones propias de la plataforma (PostgREST, Auth, Realtime); la comprobación “sin conexiones residuales” de `e7_concurrency.sh` contaba 9. | La comprobación se limita a las sesiones del propio script (`PGAPPNAME=e7_concurrency`): 0 residuales. |
| Con el stack de E1 aún levantado (todos los servicios), el reinicio posterior a `db reset` fallaba por el contenedor de storage, aunque las 57 migraciones y el seed se habían aplicado. | El runner detiene primero el stack previo (conservando el volumen) e inicia sólo los servicios necesarios. |

No se encontraron defectos de E7 en Supabase real: **no se requirió ninguna migración nueva** y no se modificó ninguna migración comprometida.

### 7.6 Cierre

T10 queda **técnicamente completa con desviación de ambiente aprobada**. Fuera de T10 queda la revalidación cloud previa a release/validación humana, condicionada por PM-002. T11 **no iniciada**.
