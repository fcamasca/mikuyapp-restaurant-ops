# E7 — Evidencia de construcción: T02–T05B

Fecha: 24/09/2026. Rama `feature/E7-OrderOperationalImprovements`, sobre el baseline documental aprobado `d7cb0fd` (“docs: spec aproved”, que ya incluía R06 `Must` y R26/R27 como solicitudes de impresión). No constituye aceptación de E7. T06 y posteriores **no iniciadas** por indicación del responsable.

## Ambiente de verificación

- PostgreSQL **16.13** local aislado en el contenedor de trabajo (puerto 5433, sin red externa), con un *shim* mínimo de Supabase (roles `anon`/`authenticated`/`service_role`, esquema `auth`, `auth.users`, `auth.uid()` desde `request.jwt.claim.sub`). No se pudo usar la imagen `supabase/postgres:17.6.1.166` utilizada en E1: los registros de contenedores (ECR/Docker Hub) están bloqueados por la política de red de la sesión. Diferencia a revalidar en T10/T11 contra DEV (PostgreSQL 17 de Supabase).
- Baseline: replay de las 49 migraciones vigentes (hasta `20260922000100_e1_delta_t18…`) + `seed.sql` → OK. E1 incluida E1-T18 presente.
- Método por tarea (según `tasks.md` §4): cada migración E7 se **aplica sobre una copia de la baseline** (`createdb -T baseline`), sin replay completo; cada prueba SQL se ejecuta en una copia fresca y termina en `ROLLBACK`.
- PM-002: sólo local. No se tocó DEV, Preview ni PROD.
- Referencia previa (baseline sin E7) de los 43 SQL individuales de `supabase/tests`: 26 pasan y 17 ya fallaban antes de E7 por contratos históricos anclados a su época (fingerprints DBSTD, “10 tablas exactas”, códigos `40001` cambiados por E1-T18, fixtures E1). Se usa como línea base diferencial para T11.

## E7-T02 — Modelo — COMPLETADA

- Migración: `supabase/migrations/20260924000100_e7_t02_modelo_cocina_historial_comanda.sql`.
- Implementado: `producto.requiere_cocina` (default `true`, grants de columna SELECT/INSERT/UPDATE para `authenticated`, RLS vigente limita la escritura a ADMIN); `detalle_pedido.requiere_cocina` (default/backfill `true`) + `ck_detalle_pedido_sin_cocina_estado`; tablas `historial_detalle_pedido` y `comanda` con FKs `ON DELETE RESTRICT`, checks, índices, RLS habilitado y sin grants directos; triggers `tgf_detalle_pedido_historial_estado` (AFTER UPDATE OF estado), `tgf_historial_detalle_pedido_inmutable`, `tgf_comanda_contenido_inmutable`; comentarios de catálogo.
- Focal: `supabase/tests/e7_t02_modelo.sql` → **PASS** (estructura, backfill, check validado y rechazando sin cocina en `ENVIADO`, historial `ENVIO` con actor, sin historial ficticio, inmutabilidad de historial/comanda, comanda vacía rechazada, `authenticated` sin acceso directo; partes estructurales de TP02/TP21/TP26).
- Defectos: ninguno.

## E7-T03 — Alta, envío y productos sin cocina — COMPLETADA

- Migración: `20260924000200_e7_t03_envio_sin_cocina_comanda.sql` (`agregar_detalle_pedido`, `enviar_pedido_cocina`, `registrar_auditoria_detalle_pedido`). Firmas y retornos sin cambios.
- Implementado: snapshot `requiere_cocina` con el precio; consolidación sólo con la misma condición; envío con cocina `ABIERTO→ENVIADO` y sin cocina `ABIERTO→LISTO` con el mismo `enviado_en`; una comanda correlativa por envío con líneas de cocina (sólo esas líneas, snapshot de código/nombre/cantidad/observación).
- Focal: `e7_t03_envio.sql` → **PASS** (TP03 completo en SQL, partes SQL de TP05/TP06, TP22, `ENVIO` de TP20). Regresión directa de las RPC modificadas: `h3_t03_add_order_detail`, `h3_t05_send_order_to_kitchen`, `h4_t01_order_detail_sent_at`, `h4_t04_derived_order_table_state` → **PASS**.
- Defectos encontrados y corregidos:
  1. El trigger H4 `registrar_auditoria_detalle_pedido` sólo admitía fijar `enviado_en` en `ABIERTO→ENVIADO`; bloqueaba `ABIERTO→LISTO`. Corrección mínima: admitir también `ABIERTO→LISTO` cuando `not requiere_cocina` (ver desviación D-1).
  2. `pg_catalog.coalesce` no existe como función (sintaxis): corregido a `coalesce`.
  3. La primera versión con un único `UPDATE … CASE` rompía los contratos textuales de `h3_t03`/`h3_t05`; se reescribió como dos `UPDATE` explícitos (mismo resultado) y ambas pruebas históricas vuelven a pasar.

## E7-T04 — Cocina y recepción completa — COMPLETADA

- Migración: `20260924000300_e7_t04_recepcion_completa_tablero.sql`.
- Implementado: `rpc_obtener_tablero_cocina()` (jsonb con `detalles`, `comandas`, `cancelaciones`, sólo `COCINA` del local); filtro `requiere_cocina` en el legado `obtener_tablero_cocina()`; `rpc_recibir_pedido_cocina(bigint)` (lock del pedido, sólo `ENVIADO` con cocina, 0 recibidos = éxito sin cambios, `PT409` para pedido fuera de cocina, marca de operación `RECEPCION_COMPLETA` restablecida); `actualizar_estado_detalle_cocina` devuelve `PT409` cuando el detalle fue cancelado (antes y después de esperar el lock).
- Focal: `e7_t04_recepcion_tablero.sql` → **PASS** (TP08; parte SQL de TP09: reintento 0 sin duplicados, `ENTREGADO`/`ANULADO`→`PT409`, CAJA→`42501`, otro local sin datos; tablero sin bebidas; transición sobre bebida `LISTO` rechazada `22023`; `PT409` de detalle cancelado; `42501` conservado para detalle inexistente).
- Carrera real TP10 (`scripts/e7_concurrency.sh t04`, conexiones independientes): **16/16 OK** — ver sección Concurrencia.
- Defecto: el caso “cocina esperó el lock y el detalle ya no existe” devolvía el mensaje genérico `PT409` ‘El detalle cambió…’; se agregó la misma detección de cancelación en esa rama. Re-ejecutados T04 SQL y carreras T04/T05 → OK.

## E7-T05 — Cancelación — COMPLETADA

- Migración: `20260924000400_e7_t05_cancelacion_detalle.sql` (`rpc_cancelar_detalle_pedido`, `rpc_obtener_cancelaciones_pedido`).
- Implementado según E7-D10: locks `pedido → detalle → mesa`; sólo `ENVIADO`/`RECIBIDO_COCINA` con cocina; línea completa; motivo obligatorio (trim, ≤ 200); pedido fuera de `ABIERTO…LISTO` o con pagos → `PT409`; snapshot inmutable en `historial_detalle_pedido` y eliminación de la línea activa; derivación por `sincronizar_estado_operativo_pedido` o rama “sin detalles” (`ABIERTO` + historial, mesa `OCUPADA`); idempotencia (`ya_cancelado = true`), también si la otra sesión canceló mientras se esperaba el lock.
- Focal: `e7_t05_cancelacion.sql` → **PASS** (TP14–TP17, `CANCELACION` de TP20, lectura del mozo y de cocina de TP19, total de caja excluye cancelados, `pedido.modificado_en` actualizado como señal Realtime).
- Carrera real TP18: **R6–R9 OK**.
- Defectos: ninguno propio (el ajuste de mensaje se hizo en la migración T04).

## E7-T05B — Edición/retiro `ABIERTO` y HZ-01 — COMPLETADA

- Reproducción previa: `supabase/tests/e7_t05b_hz01_reproduccion_baseline.sql` sobre la baseline → `NOTICE: HZ-01 REPRODUCIDO: pedido ABIERTO, mesa OCUPADA, todos los detalles LISTO`. Sobre E7 el mismo `DELETE` directo es rechazado (`permission denied for table detalle_pedido`).
- Migración: `20260924000500_e7_t05b_edicion_retiro_abierto.sql` (`rpc_modificar_detalle_pedido`, `rpc_retirar_detalle_pedido`; eliminación de `detalle_pedido_update_abierto_mozo` y `detalle_pedido_delete_abierto_mozo`; `REVOKE UPDATE (cantidad, observacion)` y `REVOKE DELETE` a `authenticated`).
- Frontend: `src/services/waiterOrderService.ts` (`updateOpenDetail`/`removeOpenDetail` usan las RPC; interfaz pública y mensajes sin cambios; `PT409` → conflicto concurrente existente). `WaiterOrderPage` sin cambios.
- Focal: `e7_t05b_edicion_retiro.sql` → **PASS** (TP11, TP12 incluida la corrección HZ-01 y re-entrega, retiro del último detalle + liberar mesa, privilegios sustituidos). Node: `node --experimental-strip-types --test tests/waiterBoard.test.mjs` → **51/51 PASS**. Carrera real TP13 → **R10–R13 OK, 0 deadlocks**.
- Pruebas históricas superadas expresamente por E7-D15 (se documentan, no se silencian; su cobertura funcional queda en `e7_t05b_edicion_retiro.sql` y en el retiro/edición E7):
  - `tests/waiterBoard.test.mjs`: 4 pruebas T07/T09 aseguraban la cadena `from('detalle_pedido').update()/delete()`; se reemplazaron por el contrato RPC equivalente (mismos campos, mismos conflictos y errores), con comentario E7-D15.
  - `supabase/tests/h3_t04_open_order_detail_mutations.sql`: falla en su matriz de grants/políticas y sus mutaciones directas como `authenticated` (ahora denegadas por diseño).
  - `supabase/tests/order_audit_trail.sql`: fija el `md5` del cuerpo del trigger de auditoría (cambiado por D-1) y usa `UPDATE`/`DELETE` directos (ahora denegados).
  Ambos SQL se tratarán en T11 como sustituciones documentadas con cobertura E7 equivalente.

## Concurrencia y locks (conexiones reales)

`PSQL_CONN=… scripts/e7_concurrency.sh all` sobre base aislada con E7 aplicado; la sesión A ejecuta la operación y mantiene la transacción 2 s; la B se lanza 0,6 s después y se observa en `pg_stat_activity` con `wait_event_type = 'Lock'`. Resultado: **fallos 0**, sin conexiones residuales.

| # | Carrera | Resultado |
|---|---|---|
| R1 | 2 cocinas, recepción completa | B espera; A recibe 3; B 0 sin error; 3 filas `RECEPCION_COMPLETA` |
| R2 | completa (A) vs individual (B) | B espera y pierde con `PT409`; una sola transición |
| R3 | individual (A) vs completa (B) | B espera y omite el detalle ya recibido |
| R4 | envío (A) vs completa (B) | B espera y recibe también lo recién enviado |
| R5 | completa (A) vs envío (B) | B espera; el nuevo detalle queda `ENVIADO`; comandas 1 y 2 |
| R6 | cancelación (A) vs `EN_PREPARACION` (B) | B espera; `PT409` “fue cancelado por el mozo”; pedido vacío `ABIERTO`/mesa `OCUPADA` |
| R7 | `EN_PREPARACION` (A) vs cancelación (B) | B espera; `PT409` “la preparación ya inició”; sin evento |
| R8 | doble cancelación | B espera; A cancela, B idempotente; 1 evento |
| R9 | anulación ADMIN E1 (A) vs cancelación (B) | B espera; `PT409`; pedido `ANULADO`, sin evento |
| R10 | retiro (A) vs envío (B) | B espera; envía 0; cabecera derivada `ENVIADO` |
| R11 | envío (A) vs retiro (B) | B espera; `PT409` |
| R12 | envío (A) vs edición (B) | B espera; `PT409`; cantidad intacta |
| R13 | edición (A) vs envío (B) | B espera; se envía con la cantidad editada |

Ningún resultado contuvo `40001`, `40P01` ni *deadlock*; `pg_stat_database.deadlocks = 0`. Orden de locks único en todas las mutaciones de detalle: `pedido → detalle → mesa`.

## Desviaciones respecto del Spec (detalles de implementación; alcance sin cambios)

| ID | Desviación | Motivo |
|---|---|---|
| D-1 | Se modificó `registrar_auditoria_detalle_pedido` (no listado en E7-D01) para admitir `enviado_en` en `ABIERTO→LISTO` sin cocina. | El trigger H4 lo impedía; sin el ajuste E7-D05 era imposible. Cambio mínimo; el resto de la auditoría no cambia. |
| D-2 | `GRANT SELECT (requiere_cocina)` sobre `producto`. | E7-D02 asumía que la política SELECT bastaba, pero `authenticated` tiene SELECT por columna. |
| D-3 | `rpc_modificar_detalle_pedido` mantiene la firma del diseño con semántica parcial: `NULL` = sin cambio/sin verificación, `''` = sin observación. | Replica exactamente el `UPDATE` parcial H3 sin cambiar la interfaz del servicio ni la página (E7-D15 suponía enviar ambos valores). |
| D-4 | `actualizar_estado_detalle_cocina` responde `PT409` sólo si existe el evento de cancelación; un ID inexistente sigue en `42501`. | Mantiene la semántica H4 de autorización y cumple E7-D10. |
| D-5 | `enviar_pedido_cocina` usa dos `UPDATE` en vez de uno con `CASE`. | Mismo comportamiento; conserva los contratos textuales H3/H4 que siguen pasando. |
| D-6 | Validación SQL en PostgreSQL 16 con *shim* en lugar de la imagen Supabase PG17. | Red bloqueada para registros de contenedores; revalidar en T10/T11. |

## Pendiente (no iniciado por indicación)

T06–T11 y T12 humana. `rpc_registrar_impresion_comanda` pertenece a T09.
