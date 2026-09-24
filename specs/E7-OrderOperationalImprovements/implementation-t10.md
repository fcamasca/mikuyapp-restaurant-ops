# E7 — Evidencia de construcción: T10 (integración)

Fecha: 24/09/2026. Rama `feature/E7-OrderOperationalImprovements`, desde el checkpoint T09 `ea37539` (árbol limpio). No constituye aceptación. T11 y T12 **no iniciadas**.

**Estado de T10: PARCIAL.** Integración local (PostgreSQL 16) completada. Decisión del responsable (24/09/2026): **no aplicar E7 sobre el proyecto compartido con Production**; T10 se cerrará en un **proyecto Supabase aislado de validación** (§7). No se tocó ningún proyecto Supabase ni Cloudflare.

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

## 7. Cierre en proyecto Supabase aislado (PostgreSQL 17 real)

Estado: **procedimiento y herramientas preparados; ejecución pendiente del responsable.** Esta sesión no puede alcanzar Supabase (política de red, §1) ni dispone de credenciales administrativas, por lo que la creación del proyecto y la aplicación de migraciones se solicitan al responsable.

- Procedimiento: `specs/E7-OrderOperationalImprovements/t10-ambiente-validacion.md` (cuota, creación sin `supabase link`, `supabase db push --db-url` de las 57 migraciones —49 de baseline hasta E1-T18 + 8 de E7—, verificación de publicación Realtime, SQL focales + integración + carreras con `psql` del contenedor `supabase/postgres:17.6.1.166`, y recorrido vía API).
- Herramienta: `scripts/e7_t10_validation.mjs` — recorrido integrado con los servicios reales del frontend contra PostgREST/Auth/Realtime del proyecto aislado (dos mozos, dos cocinas): pedido mixto, edición/retiro, `PT409` vía PostgREST, envío con bebida `LISTO`, **Realtime** de envío, recepción completa y cancelación (señal `UPDATE` de `pedido`), resincronización del mozo B, comanda (primera solicitud concurrente con `PT409`, reimpresión, documento con `COPIA 1` y línea `CANCELADO`), avance individual hasta `LISTO`.
- Guardia del script verificada en esta sesión: aborta con la URL del proyecto de `.env.local` (DEV/compartido) y sólo continúa con un ref distinto; sintaxis verificada (`node --check`). No se ejecutó contra ningún proyecto real.
- Riesgo de cuota: la organización ya tiene dos proyectos (`mikuyapp`, `mikuyapp-prod`); si el plan no permite un tercero, T10-DEV queda detenido y se reporta sin sustituirlo por Production.
- Evidencia Supabase/PostgreSQL 17 y Realtime real: **pendiente** (se registrará aquí al recibir las salidas del procedimiento).

## 6. Pendiente

- Aplicar `20260924000100`–`000800` en DEV y repetir `e7_t10_integracion.sql` + recorrido con dos dispositivos (Realtime real, comanda impresa desde Preview) una vez resuelto §4.
- Para T11 (no iniciado): `typecheck`, `build`, suite completa, replay limpio total y tratamiento documentado de `h3_t04_open_order_detail_mutations.sql` y `order_audit_trail.sql`.
