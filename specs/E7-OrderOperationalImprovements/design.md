# MikuyApp — Evolución 7 — Mejoras operativas de pedidos: diseño

**Estado: SPEC MODE — BORRADOR PENDIENTE DE APROBACIÓN.** Este documento define contratos y decisiones; no autoriza migraciones ni cambios de código hasta la aprobación humana.

## E7-D01 — Principios y cambio mínimo

Se conserva la arquitectura vigente: React + TypeScript, Supabase/PostgreSQL, RLS, funciones `SECURITY DEFINER` con `search_path = pg_catalog`, invariantes críticas en PostgreSQL, operaciones multi-registro en una única transacción, Realtime como señal y snapshot autoritativo. No se agrega backend, agente de impresión ni librería nueva.

Resumen del cambio estructural:

| Objeto | Cambio | Tipo |
|---|---|---|
| `producto.requiere_cocina` | Columna nueva `boolean not null default true`. | Aditivo |
| `detalle_pedido.requiere_cocina` | Snapshot `boolean not null default true`, backfill `true`, check de coherencia con estado. | Aditivo |
| `historial_detalle_pedido` | Tabla histórica inmutable de transiciones y cancelaciones de detalle. | Nueva |
| `comanda` | Documento inmutable de cocina por envío, con metadatos de impresión. | Nueva |
| `agregar_detalle_pedido` | Copia snapshot y lo incluye en la clave de consolidación. | Modificación mínima |
| `enviar_pedido_cocina` | Sin cocina → `LISTO`; genera comanda. Firma y retorno sin cambios. | Modificación mínima |
| `obtener_tablero_cocina` | Excluye detalles sin cocina. Firma sin cambios; queda en desuso por el frontend. | Modificación mínima |
| `actualizar_estado_detalle_cocina` | Detalle inexistente (cancelado) → `PT409` en lugar de `42501`. | Modificación mínima |
| `rpc_obtener_tablero_cocina` | Lectura unificada de cocina (detalles, comandas, cancelaciones). | Nueva |
| `rpc_recibir_pedido_cocina` | Recepción completa. | Nueva |
| `rpc_cancelar_detalle_pedido` | Cancelación por mozo. | Nueva |
| `rpc_obtener_cancelaciones_pedido` | Lectura de cancelaciones para el mozo. | Nueva |
| `rpc_registrar_impresion_comanda` | Registro de la primera solicitud de impresión / reimpresión. | Nueva |
| `rpc_modificar_detalle_pedido` | Edición H3 de cantidad/observación de un detalle `ABIERTO` (HZ-01). | Nueva (sustituye `UPDATE` directo) |
| `rpc_retirar_detalle_pedido` | Retiro H3 de un detalle `ABIERTO` con recálculo (HZ-01). | Nueva (sustituye `DELETE` directo) |
| Grants/RLS de `detalle_pedido` | Se revocan `UPDATE (cantidad, observacion)` y `DELETE` de `authenticated` y se eliminan `detalle_pedido_update_abierto_mozo` / `detalle_pedido_delete_abierto_mozo`. | Endurecimiento |
| Triggers de historial e inmutabilidad | `tgf_detalle_pedido_historial_estado`, `tgf_historial_detalle_pedido_inmutable`, `tgf_comanda_contenido_inmutable`. | Nuevos |

`sincronizar_estado_operativo_pedido`, `entregar_pedido`, `crear_o_recuperar_pedido_mesa`, `liberar_mesa_pedido_vacio`, las RPC de caja E1 y la publicación Realtime **no se modifican**. Las políticas RLS vigentes tampoco cambian, salvo la eliminación de las dos políticas de mutación directa de detalles `ABIERTO` sustituidas por RPC (E7-D15).

Nombres nuevos siguen `docs/DATABASE_STANDARD.md` (`rpc_`, `fn_`, `tgf_`, `trg_`, `pol_`, `ck_`, `uq_`, `idx_`). Las tablas nuevas conservan el estilo semántico vigente (sin prefijo físico `his_`/`mov_`), decisión explícita requerida por el estándar §4.1. Las funciones H3/H4 existentes conservan su nombre histórico para no romper contratos.

## E7-D02 — Representación de `requiere_cocina` en el catálogo

- `producto.requiere_cocina boolean not null default true`, comentado con `COMMENT ON`.
- El default `true` preserva el comportamiento de todos los productos existentes, del alta vía carga inicial y de cualquier cliente que no envíe el campo.
- Privilegios: se amplían los `GRANT INSERT (…)` y `GRANT UPDATE (…)` por columna de `producto` para incluir `requiere_cocina`. Las políticas RLS `h2_insert_admin_products` / `h2_update_admin_products` ya limitan la mutación a `ADMINISTRADOR` del mismo local; no se crean políticas nuevas.
- `catalogService` incorpora la columna en `productColumns`, validación booleana, alta y edición. La carta operativa del mozo la recibe como lectura (la política de `SELECT` ya existente la expone).
- La exportación H6 `exportar_productos_local` **no cambia** su contrato en E7 (restricción de alcance).

Alternativa descartada: representar la condición por `categoria` (por ejemplo, “Bebidas”). Es más frágil (una categoría puede mezclar productos) y obliga a interpretar nombres; el atributo por producto es explícito y simple.

## E7-D03 — Snapshot en `detalle_pedido`

**Decisión: sí se almacena snapshot** `detalle_pedido.requiere_cocina boolean not null default true`.

Justificación (consistencia histórica y simplicidad):

1. Mismo patrón aprobado para `precio_unitario` (estándar §19.3, “snapshot histórico”): el detalle conserva lo aplicado al pedido.
2. Sin snapshot, cambiar un producto de “sin cocina” a “requiere cocina” haría aparecer en cocina detalles `LISTO` ya servidos, y el cambio inverso haría desaparecer trabajo real de cocina en curso. Ambos casos rompen H4.
3. El tablero, la recepción completa, la cancelación y la comanda filtran por una columna local del detalle, sin joins condicionales al catálogo ni reglas temporales.
4. Coste mínimo: una columna booleana y un backfill trivial.

Reglas:

- **Momento del snapshot:** al crear el detalle en `agregar_detalle_pedido`, leyendo `producto.requiere_cocina` junto con el precio vigente, dentro de la misma consulta. Si el catálogo cambia mientras el detalle sigue `ABIERTO`, el detalle conserva el valor de su creación; un nuevo agregado del mismo producto creará una línea distinta si el valor difiere (E7-D04).
- **Backfill:** todas las filas existentes quedan `true` (históricamente todo pasó por cocina); no requiere inferencia.
- **Inmutabilidad:** `authenticated` no recibe `UPDATE (requiere_cocina)` sobre `detalle_pedido` (hoy sólo `cantidad, observacion`) ni `INSERT` directo; ninguna RPC lo actualiza. No se requiere trigger adicional.
- **Invariante en PostgreSQL:** `ck_detalle_pedido_sin_cocina_estado check (requiere_cocina or estado in ('ABIERTO','LISTO'))`. Un detalle sin cocina nunca puede estar en un estado de cocina, aunque falle una RPC.

## E7-D04 — Alta y consolidación

`agregar_detalle_pedido(bigint, uuid, integer, text)` conserva firma, retorno, permisos, locks (`pedido → mesa`, advisory lock por pedido/producto) y errores E1-T18. Cambios:

- lee `pr.precio, pr.requiere_cocina` en la misma consulta de producto activo;
- la búsqueda de consolidación agrega `and d.requiere_cocina = v_requiere_cocina`;
- el `INSERT` incluye `requiere_cocina`.

El frontend puede leer el snapshot desde `detalle_pedido` (la política `SELECT` del mozo ya concede todas las columnas).

## E7-D05 — Estado de un detalle que no requiere cocina

**Decisión: al enviarse pasa `ABIERTO → LISTO` directamente, con `enviado_en` del envío.**

| Alternativa | Evaluación |
|---|---|
| `ABIERTO → LISTO` al enviar (**elegida**) | Sin estados nuevos. “Listo” describe correctamente un producto de entrega inmediata. El agregado H4 ya trata `LISTO` como terminado, por lo que un pedido mixto sólo queda `LISTO` cuando cocina termina. El check `ck_detalle_pedido_envio_coherente` se cumple porque `enviado_en` se fija. La entrega, el cobro, el tablero del mozo y el flujo ADMIN E1 funcionan sin cambios. |
| `ABIERTO → ENVIADO` | Generaría trabajo de cocina y aparecería en el tablero; incumple E7-R05. |
| Permanecer `ABIERTO` | El pedido nunca llegaría a `LISTO` (prioridad `ABIERTO`) y seguiría editable/retirable como no enviado. |
| Estado nuevo (`SERVIDO`, `NO_APLICA`, etc.) | Innecesario: obliga a cambiar checks, derivación, cocina, entrega, caja, reportes y pruebas históricas. Los estados actuales son suficientes. |

Consecuencias documentadas:

- Un pedido sólo de productos sin cocina pasa `ABIERTO → LISTO` en su historial de cabecera (sin `ENVIADO` intermedio). Es un cambio real y se registra una sola vez.
- El flujo `Flujo actual de pedidos` de E1 lo clasificará como `Listos para entregar`, que es correcto.
- Decisión DH-03 (aprobada): un producto sin cocina enviado no es cancelable por el mozo (está `LISTO`); mientras está `ABIERTO` se retira con el retiro H3.

## E7-D06 — Envío modificado y generación de comanda

`enviar_pedido_cocina(bigint)` conserva firma, retorno, validaciones, lock `FOR UPDATE` de la cabecera y estados admitidos. Nueva secuencia dentro de la misma transacción:

1. validar identidad/rol/local y bloquear el pedido (vigente);
2. `v_envio := clock_timestamp()`;
3. `UPDATE … SET estado = CASE WHEN requiere_cocina THEN 'ENVIADO' ELSE 'LISTO' END, enviado_en = v_envio WHERE pedido_id = … AND estado = 'ABIERTO'`, obteniendo en `RETURNING` los IDs y la condición de cocina;
4. si no hubo filas, devolver sin cambios (comportamiento vigente, sin comanda ni historial);
5. fijar `pedido.enviado_en` si es el primer envío (vigente);
6. si al menos una fila requiere cocina, insertar **una** fila en `comanda` (E7-D12) con las líneas de cocina de ese envío;
7. derivar cabecera/mesa con `sincronizar_estado_operativo_pedido`.

El retorno conserva su semántica: `detalles_enviados` es el total de detalles que salieron de `ABIERTO`. No se cambia el tipo de retorno para evitar `DROP FUNCTION` y romper consumidores.

## E7-D07 — Impacto en estado agregado de pedido y mesa

`sincronizar_estado_operativo_pedido` **no cambia**. Sus prioridades ya producen el comportamiento requerido porque un detalle sin cocina está `ABIERTO` (antes del envío) o `LISTO` (después):

- pedido mixto con cocina pendiente → estado del detalle de cocina menos avanzado; mesa `OCUPADA`;
- todo `LISTO` → pedido `LISTO`, mesa `PEDIDO_LISTO`;
- pedido `ENTREGADO` + nuevo producto: la regla H5 existente lo reabre (`ABIERTO`/`OCUPADA`) y el nuevo envío lo devuelve a `LISTO`/`PEDIDO_LISTO` para una nueva entrega.

La única situación que la función no admite es un pedido sin detalles; E7-D10 la resuelve dentro de la cancelación y E7-D15 dentro del retiro sin modificar la función compartida.

## E7-D08 — Lectura de cocina

Se crea `rpc_obtener_tablero_cocina() returns jsonb` (`stable`, `SECURITY DEFINER`, rol `COCINA`, local del contexto) con una sola llamada por refresco, para no multiplicar consultas por señal Realtime (lección del incidente de CPU de E1-T18):

```json
{
  "detalles": [ /* mismas columnas que obtener_tablero_cocina() */ ],
  "comandas": [ { "comanda_id", "pedido_id", "numero", "mesa_codigo", "mesa_nombre",
                  "creado_en", "creado_por_nombre", "lineas", "impresiones",
                  "primera_impresion_en", "ultima_impresion_en" } ],
  "cancelaciones": [ { "pedido_id", "detalle_id", "producto_nombre", "cantidad",
                       "observacion", "estado_anterior", "motivo", "cancelado_en" } ]
}
```

Filtros:

- `detalles`: igual que H4 (`pedido.estado ∈ ABIERTO…LISTO`, `detalle.estado ∈ ENVIADO…LISTO`, mismo local) **y** `detalle.requiere_cocina`. Orden H4 por `enviado_en, pedido_id, detalle_id`.
- `comandas`: comandas de pedidos del local en `ABIERTO…LISTO` (fuera de cocina no se ofrecen), ordenadas por `creado_en`.
- `cancelaciones`: eventos `CANCELACION` de detalles con `requiere_cocina` de pedidos del local en `ABIERTO…LISTO`, ordenados por fecha descendente.

`obtener_tablero_cocina()` (H4) recibe el mismo filtro `requiere_cocina` para que ningún camino exponga productos sin cocina a cocina; su firma no cambia, deja de ser usada por el frontend y su retiro se difiere (no se elimina en E7). El agrupamiento/orden de `groupKitchenBoard` se mantiene. Un pedido cuyas líneas de cocina fueron todas canceladas deja de tener `detalles`, pero sus cancelaciones siguen visibles mientras el pedido esté en `ABIERTO…LISTO`, como grupo de sólo lectura.

Índice: el índice parcial vigente `idx_detalle_pedido_cocina_enviado_en` sigue siendo aplicable; no se agrega índice salvo que el plan de consulta real lo justifique durante T04. Índices nuevos mínimos en tablas nuevas: `historial_detalle_pedido(pedido_id, creado_en)` y `comanda(pedido_id, numero)` único.

## E7-D09 — Recepción completa transaccional

`rpc_recibir_pedido_cocina(p_pedido_id bigint) returns table (pedido_id bigint, detalles_recibidos integer, detalle_ids bigint[], pedido_estado text)`.

1. `auth.uid()` + `obtener_contexto_autenticado()`: rol `COCINA` y local; si no → `42501`.
2. Bloquear el pedido `FOR UPDATE` con `local_id` del contexto y estado `ABIERTO…LISTO`. Si no existe o no pertenece al local → `42501`; si está `ENTREGADO`, `PAGADO` o `ANULADO` → `PT409` (“El pedido ya no está en cocina”).
3. `set_config('mikuyapp.operacion_detalle', 'RECEPCION_COMPLETA', true)` para el historial (E7-D11).
4. `UPDATE detalle_pedido SET estado = 'RECIBIDO_COCINA' WHERE pedido_id = … AND estado = 'ENVIADO' AND requiere_cocina RETURNING id`.
5. Si 0 filas: **éxito sin cambios** (`detalles_recibidos = 0`), sin historial ni derivación. Así, doble clic, reintento o carrera perdida no producen error ni reintentos de PostgREST.
6. Si > 0: `sincronizar_estado_operativo_pedido` (lock de mesa después del pedido) y devolver IDs recibidos.

Orden de locks `pedido → detalle → mesa`, idéntico a `actualizar_estado_detalle_cocina`, `enviar_pedido_cocina`, la cancelación y las nuevas RPC de edición/retiro `ABIERTO` (E7-D15): con E7 todas las mutaciones de detalles siguen un único orden y no se introducen ciclos de espera. Concurrencia:

| Carrera | Resultado |
|---|---|
| Dos recepciones completas | La segunda espera el lock y recibe 0 filas → éxito sin cambios. |
| Recepción completa vs individual `ENVIADO → RECIBIDO_COCINA` | Serializadas; la perdedora individual recibe `PT409` por estado esperado obsoleto, o la completa omite el detalle ya recibido. |
| Recepción completa vs nuevo envío del mozo | Serializadas; si el envío confirma antes, los nuevos `ENVIADO` visibles se reciben también (la operación procesa el estado persistido, E7-R09). La UI recarga el snapshot después de la operación. |
| Recepción completa vs cancelación | Serializadas; el detalle cancelado ya no existe o, si la recepción gana, queda `RECIBIDO_COCINA`, que sigue siendo cancelable. |

UI: botón “Recibir pedido (N)” en cada grupo con al menos un detalle `ENVIADO`; guard local por pedido (`Set` en `useRef`) que deshabilita el botón grupal y los botones individuales del grupo mientras la operación está en curso; siempre libera el guard y resincroniza, siguiendo `runKitchenDetailMutation`. `PT409` se muestra como conflicto recuperable. El procesamiento individual existente no cambia.

## E7-D10 — Cancelación por mozo y concurrencia con cocina

`rpc_cancelar_detalle_pedido(p_detalle_id bigint, p_motivo text) returns table (detalle_id bigint, pedido_id bigint, pedido_estado text, mesa_estado text, ya_cancelado boolean)`.

**Representación elegida: eliminación física de la línea + snapshot completo en `historial_detalle_pedido`.**

| Alternativa | Evaluación |
|---|---|
| Borrar la línea y registrar snapshot inmutable (**elegida**) | El total (`sum(cantidad*precio_unitario)`), la derivación H4, el tablero, entrega, `fn_resolver_total_pedido`, lecturas y reportes de caja, exportaciones y `Flujo actual` siguen correctos **sin tocar ninguna** de esas funciones. La trazabilidad completa vive en el historial. |
| Estado nuevo `CANCELADO` en detalle | Nuevo estado no justificado; exigiría excluirlo explícitamente en derivación, totales, caja, reportes, exportaciones, tablero, entrega, RLS y pruebas H3–E1. Alto riesgo de regresión. |
| Columnas `cancelado_en/por/motivo` conservando la fila | Mismo impacto que un estado nuevo (todas las sumas y filtros deberían excluir filas canceladas). |

Secuencia:

1. Validar `auth.uid()`, rol `MOZO`, local; `p_motivo` no nulo, no vacío y con longitud acotada (≤ 200) → si no, `22023`.
2. Localizar `pedido_id` del detalle. Si el detalle no existe: si existe un evento `CANCELACION` para ese `detalle_id` en un pedido del mismo local → devolver ese resultado con `ya_cancelado = true` (idempotencia, E7-R16); si no → `42501`.
3. Bloquear el pedido `FOR UPDATE` (mismo local). Estado debe ser `ABIERTO…LISTO`; `ENTREGADO` con detalle cancelable no es posible por construcción; `PAGADO`/`ANULADO` → `PT409`.
4. Bloquear el detalle `FOR UPDATE`. Si desapareció entre (2) y (4), repetir la comprobación idempotente o `PT409`.
5. Validar `requiere_cocina` y `estado ∈ ('ENVIADO','RECIBIDO_COCINA')` (DH-03: un detalle sin cocina enviado está `LISTO` y se rechaza). La cancelación siempre elimina la línea completa, cualquiera sea `cantidad` (DH-04); no existe parámetro de cantidad. `EN_PREPARACION`/`LISTO` → `PT409` (“La preparación ya inició”); `ABIERTO` → `PT409` (“Usa retirar para productos no enviados”).
6. Insertar el evento `CANCELACION` en `historial_detalle_pedido` con snapshot (producto, cantidad, precio, observación, condición de cocina, estado anterior, motivo, actor, hora).
7. `DELETE` del detalle. Los triggers vigentes actúan normalmente: `tgf_bloquear_detalle_pedido_con_pago` rechaza si existe pago; `registrar_auditoria_detalle_pedido` actualiza `pedido.modificado_*` (cambio comercial real).
8. Si quedan detalles → `sincronizar_estado_operativo_pedido`. Si no quedan → actualizar la cabecera a `ABIERTO` (si difiere), insertar `historial_estado` y dejar la mesa `OCUPADA`; `pedido.enviado_en` se conserva como dato histórico del primer envío.
9. Devolver estados persistidos.

Concurrencia con cocina: ambos lados bloquean primero el pedido, por lo que se serializan. Si cocina confirma `RECIBIDO_COCINA → EN_PREPARACION` antes, la cancelación ve `EN_PREPARACION` y falla con `PT409`. Si la cancelación confirma antes, `actualizar_estado_detalle_cocina` no encuentra el detalle: hoy devuelve `42501` cuando el detalle no existe; E7 lo cambia a `PT409` (“El detalle cambió o fue cancelado”) para que la UI de cocina lo trate como conflicto y resincronice. Es el único cambio de esa función.

UI del mozo: en “Ya solicitado”, los detalles `ENVIADO`/`RECIBIDO_COCINA` con `requiere_cocina` muestran “Cancelar producto”; confirmación con resumen (producto, cantidad, importe que se descuenta, estado actual) y motivo (opciones frecuentes + texto libre); guard por detalle; `PT409` se muestra como conflicto y se recarga el pedido. Los detalles `EN_PREPARACION`/`LISTO` muestran que ya no pueden cancelarse. Una sección “Cancelados” de sólo lectura muestra las líneas canceladas (E7-D13).

## E7-D11 — Trazabilidad: `historial_detalle_pedido`

```text
historial_detalle_pedido
  id               bigint identity PK
  local_id         uuid   not null  FK local            ON DELETE RESTRICT
  pedido_id        bigint not null  FK pedido           ON DELETE RESTRICT
  detalle_id       bigint not null  (sin FK: la línea cancelada deja de existir)
  producto_id      uuid   not null  FK producto         ON DELETE RESTRICT
  operacion        text   not null  ck ∈ ENVIO | TRANSICION_COCINA | RECEPCION_COMPLETA | CANCELACION
  estado_anterior  text   not null  ck dominio de detalle
  estado_nuevo     text   null      ck dominio de detalle; null sólo si CANCELACION
  requiere_cocina  boolean not null
  cantidad         integer not null ck > 0
  precio_unitario  numeric(10,2) not null
  observacion      text null
  motivo           text null        ck obligatorio y no vacío sólo si CANCELACION
  usuario_id       uuid   not null  FK perfil_usuario   ON DELETE RESTRICT
  creado_en        timestamptz not null default now()
```

- **Transiciones:** trigger `trg_detalle_pedido_after_update_historial_estado` (`AFTER UPDATE OF estado`, `FOR EACH ROW`, `WHEN old.estado IS DISTINCT FROM new.estado`) ejecuta `tgf_detalle_pedido_historial_estado` (`SECURITY DEFINER`). Operación: `ENVIO` si `old.estado = 'ABIERTO'`; `RECEPCION_COMPLETA` si `current_setting('mikuyapp.operacion_detalle', true) = 'RECEPCION_COMPLETA'`; en otro caso `TRANSICION_COCINA`. Actor: `auth.uid()`, con el mismo criterio de resolución del trigger de auditoría vigente. Cubre sin cambios `actualizar_estado_detalle_cocina` y todas las RPC futuras que cambien estado.
- **Cancelación:** inserción explícita desde `rpc_cancelar_detalle_pedido` antes del `DELETE`.
- **Inmutabilidad:** `trg_historial_detalle_pedido_before_write_inmutable` rechaza `UPDATE`/`DELETE` (patrón E1 `tgf_*_inmutable`). `authenticated` no recibe privilegios de tabla; RLS habilitado sin políticas de escritura. Las lecturas se exponen sólo mediante RPC.
- **Sin backfill:** los detalles anteriores a E7 no tienen transiciones reconstruibles; el historial comienza al desplegar E7.
- `historial_estado` sigue registrando únicamente cambios reales de cabecera.
- El retiro H3 de `ABIERTO` no se registra (antes del envío no existe impacto en cocina).

Por qué `detalle_id` sin FK: una FK `ON DELETE RESTRICT` impediría la cancelación física, y `SET NULL` violaría la inmutabilidad. El identificador conserva la correlación; `pedido_id` y `producto_id` sí mantienen FK.

## E7-D12 — Comandas: generación, deduplicación, reimpresión e impresión

### Modelo

```text
comanda
  id                     bigint identity PK
  local_id               uuid   not null FK local
  pedido_id              bigint not null FK pedido
  numero                 integer not null ck > 0      uq (pedido_id, numero)
  enviado_en             timestamptz not null          (= enviado_en del lote)
  lineas                 jsonb  not null ck arreglo no vacío
                         [{detalle_id, producto_codigo, producto_nombre, cantidad, observacion}]
  creado_por             uuid   not null FK perfil_usuario (mozo que envió)
  creado_en              timestamptz not null default now()
  impresiones            integer not null default 0 ck >= 0
  primera_impresion_en   timestamptz null
  primera_impresion_por  uuid null FK perfil_usuario
  ultima_impresion_en    timestamptz null
  ultima_impresion_por   uuid null FK perfil_usuario
  ck coherencia: impresiones = 0 ⇔ primera_impresion_* null
```

Contenido inmutable: `tgf_comanda_contenido_inmutable` rechaza `DELETE` y cualquier `UPDATE` que no sea de las columnas de impresión. Sin privilegios directos para `authenticated`.

### Reglas

| Tema | Decisión |
|---|---|
| Momento de generación | Dentro de la transacción de `enviar_pedido_cocina`, cuando el lote enviado contiene ≥ 1 detalle con `requiere_cocina`. Si el envío falla, no hay comanda. |
| Contenido | Sólo las líneas de cocina de ese envío, con nombre/código de producto como snapshot documental; mesa y mozo se resuelven al leer. Productos sin cocina no se incluyen. |
| Nuevos productos posteriores | Cada envío posterior con líneas de cocina crea la comanda `numero + 1` (correlativo por pedido bajo el lock del pedido), con sólo sus líneas nuevas. |
| Deduplicación | Una comanda por lote enviado: el envío repetido sin detalles `ABIERTO` no genera comanda; `uq_comanda_pedido_id_numero` es defensa final. En impresión: `rpc_registrar_impresion_comanda(p_comanda_id, p_reimpresion boolean)` bloquea la comanda; si `p_reimpresion = false` y ya tiene impresiones → `PT409` (“Ya fue impresa; usa reimprimir”). |
| Reimpresión | `p_reimpresion = true` exige al menos una impresión previa; incrementa `impresiones` y actualiza `ultima_impresion_*`. El papel muestra “COPIA n”. Disponible mientras el pedido esté en `ABIERTO…LISTO`. |
| Trazabilidad | `creado_por/creado_en`, `primera_impresion_*`, `impresiones`, `ultima_impresion_*`. No se crea tabla de eventos de impresión (suficiente para E7). |
| Cancelaciones posteriores | La comanda no se altera. El tablero muestra la cancelación (E7-D08) y, al reimprimir, las líneas cuya cancelación esté registrada se marcan “CANCELADO” en el papel a partir del historial. No se imprime aviso automático de cancelación. |
| Mecanismo técnico (DH-02) | Igual que caja H5/E1: vista `print-overlay`/`print-document` con CSS de 80 mm y `window.print()` desde el navegador de una sesión `COCINA`, hacia cualquier impresora accesible y configurada por el sistema operativo del dispositivo. No se definen servicios Android, bridges, agentes locales, ESC/POS directo, impresión silenciosa, servidor ni hardware adicional. La compatibilidad física se verifica en la validación humana. |
| Opcionalidad | Cada comanda se presenta en su grupo del tablero con las acciones manuales `Imprimir` (si aún no tiene impresiones, marcada “Sin imprimir”) y `Reimprimir`. La impresión es opcional porque ninguna operación depende de ella; no existe preferencia, configuración por dispositivo ni uso de almacenamiento del navegador. |
| Orden de acciones | Al pulsar “Imprimir”: 1) llamar `rpc_registrar_impresion_comanda`; 2) con éxito, mostrar el documento y ejecutar `window.print()`. Un `PT409` refresca y ofrece reimprimir. |
| Impresora no disponible | El navegador no confirma impresión física; el registro representa “impresión solicitada”. Si falla la impresora, el documento sigue visible, el estado digital no cambia y se usa “Reimprimir”. Ningún estado de detalle, pedido o mesa depende de la impresión. |
| Rol | Sólo `COCINA` registra impresiones y lee comandas, desde cualquier dispositivo con sesión `COCINA`. |

## E7-D13 — Lectura de cancelaciones para el mozo

`rpc_obtener_cancelaciones_pedido(p_pedido_id bigint)` (`stable`, rol `MOZO`, mismo local, pedido vigente `ABIERTO…ENTREGADO`) devuelve `detalle_id, producto_id, producto_nombre, cantidad, precio_unitario, observacion, estado_anterior, motivo, cancelado_en, cancelado_por_nombre`. El mozo la invoca al cargar el pedido y en cada resincronización del pedido abierto. No se expone el historial por lectura directa de tabla.

## E7-D14 — Seguridad, RLS y privilegios

- Todas las funciones nuevas: `SECURITY DEFINER`, owner `postgres`, `set search_path = pg_catalog`, referencias calificadas, `REVOKE ALL … FROM public, anon`, `GRANT EXECUTE … TO authenticated` sólo para RPC; funciones de trigger sin `EXECUTE` para `authenticated`.
- Validación en cada RPC de `auth.uid()`, perfil/rol/local activos vía `obtener_contexto_autenticado()`, y pertenencia al local del pedido/detalle/comanda.
- Tablas nuevas con RLS habilitado y sin privilegios directos para `anon`/`authenticated`.
- `producto`: sólo se amplían los grants por columna para `requiere_cocina`.
- `detalle_pedido`: no se amplían grants; se revocan `UPDATE`/`DELETE` directos (E7-D15); `requiere_cocina` no es actualizable por el cliente.
- Códigos: `42501` no autorizado/fuera de local; `22023` entrada inválida; `PT409` conflicto funcional; nunca `40001`.
- Comentarios `COMMENT ON` para snapshot, check de coherencia, tablas nuevas y RPC (estándar §21).

## E7-D15 — Consistencia: edición y retiro de detalles `ABIERTO` (HZ-01, DH-01 aprobada)

**Problema.** La edición (`UPDATE` directo) y el retiro (`DELETE` directo) de H3 bloquean primero la fila del detalle y, a través del trigger de auditoría, después la cabecera `pedido`; `enviar_pedido_cocina`, la cocina, la recepción completa y la cancelación bloquean primero el pedido y después los detalles. Además, el retiro no ejecuta la derivación, lo que produce HZ-01. Se sustituyen ambas mutaciones directas por RPC con el orden único `pedido → detalle → mesa`, **sin cambiar las capacidades funcionales H3**.

### `rpc_modificar_detalle_pedido`

`rpc_modificar_detalle_pedido(p_detalle_id bigint, p_cantidad integer, p_observacion text, p_cantidad_esperada integer, p_observacion_esperada text) returns table (detalle_id bigint, cantidad integer, observacion text, estado text)`

1. `auth.uid()` + contexto: rol `MOZO` y local → si no, `42501`.
2. Validación H3: `p_cantidad` entera ≥ 1; `p_observacion` normalizada con `btrim` y vacía → `NULL` (misma normalización que hoy aplica el servicio); → `22023` si es inválida.
3. Localizar el pedido del detalle; bloquear el pedido `FOR UPDATE` (mismo local, vigente `ABIERTO…ENTREGADO`, igual que la política RLS actual) → si no, `42501`.
4. Bloquear el detalle `FOR UPDATE`. Si no existe, no está `ABIERTO`, o `cantidad`/`observacion` persistidas difieren de los valores esperados → `PT409` (hoy: 0 filas afectadas → conflicto concurrente en la UI).
5. Actualizar sólo `cantidad` y `observacion`. El trigger de auditoría conserva su semántica (`pedido.modificado_*`). No se consolida con otras líneas (H3 no consolida por edición) y no se deriva estado (la edición no cambia estados).

El frontend envía siempre los valores finales de ambos campos y los valores que mostraba como esperados; así se conserva la verificación optimista actual de `updateOpenDetail`.

### `rpc_retirar_detalle_pedido`

`rpc_retirar_detalle_pedido(p_detalle_id bigint) returns table (detalle_id bigint, pedido_id bigint, pedido_estado text, mesa_estado text)`

1. Identidad/rol `MOZO`/local como arriba.
2. Bloquear el pedido `FOR UPDATE` (mismo local, vigente) y luego el detalle `FOR UPDATE`; si el detalle no existe o no está `ABIERTO` → `PT409` (comportamiento actual de conflicto).
3. `DELETE` del detalle (los triggers vigentes de auditoría y de bloqueo por pago siguen aplicando). No se registra en `historial_detalle_pedido`: un borrador no enviado no tiene impacto en cocina (E7-D11).
4. Si quedan detalles → `sincronizar_estado_operativo_pedido` (corrige HZ-01: un pedido `ENTREGADO` reabierto cuyo producto nuevo se retira vuelve a `LISTO`/`PEDIDO_LISTO`). Si no quedan → cabecera `ABIERTO` (con historial sólo si cambia) y mesa `OCUPADA`, habilitando `liberar_mesa_pedido_vacio` como hoy.

### Privilegios

- Se revocan `UPDATE (cantidad, observacion)` y `DELETE` sobre `detalle_pedido` a `authenticated` y se eliminan las políticas `detalle_pedido_update_abierto_mozo` y `detalle_pedido_delete_abierto_mozo`. `SELECT` y sus políticas se mantienen.
- Consecuencia documentada: las aserciones de metadatos de `supabase/tests/h3_t04_open_order_detail_mutations.sql` que verifican esos grants/políticas quedan superadas por E7; en E7-T05B se agregan pruebas E7 equivalentes (mismas capacidades vía RPC) sin editar la evidencia histórica de H3.
- Se descarta un trigger `AFTER DELETE` que derive estados, porque tomaría el lock del pedido después del lock de la fila y conservaría el riesgo de interbloqueo con `enviar_pedido_cocina`.

### Frontend

`waiterOrderService.updateOpenDetail` y `removeOpenDetail` conservan su interfaz pública y mensajes, cambiando sólo la llamada (`rpc` en lugar de `update`/`delete`); `PT409` se mapea al conflicto concurrente ya existente. `WaiterOrderPage` no cambia su comportamiento.

## E7-D16 — Realtime

No se modifica la publicación (`detalle_pedido`, `pedido`, `mesa`) ni se publican `historial_detalle_pedido` o `comanda`. Señales disponibles:

| Operación | Señal que reciben los clientes |
|---|---|
| Envío (con o sin cocina) | `UPDATE` de `detalle_pedido`; `UPDATE` de `pedido`/`mesa` si cambia el agregado. La comanda se lee en el mismo snapshot de cocina. |
| Recepción completa | `UPDATE` de cada `detalle_pedido`; cambio de cabecera si corresponde. |
| Edición `ABIERTO` | `UPDATE` de `detalle_pedido` (igual que hoy). |
| Retiro `ABIERTO` | Como la cancelación: `UPDATE` de `pedido` por el trigger de auditoría y, si cambia, de cabecera/mesa. |
| Cancelación | El `DELETE` no se escucha (el frontend sólo escucha `INSERT`/`UPDATE`), pero el trigger de auditoría vigente siempre actualiza `pedido.modificado_*` → `UPDATE` de `pedido`, visible por RLS para `MOZO`, `COCINA` (`ABIERTO…LISTO`) y `CAJA` cuando aplique. |
| Registro de impresión | Sin señal. Otros dispositivos se actualizan en la siguiente señal o con “Actualizar”; la deduplicación la garantiza `PT409` en el servidor. |

Los clientes mantienen el patrón H4: snapshot inicial, suscripción, segunda carga al `SUBSCRIBED`, debounce, reemplazo completo del estado local y resincronización ante error/reconexión. Cocina sustituye la llamada a `obtener_tablero_cocina` por `rpc_obtener_tablero_cocina` (una llamada por refresco).

## E7-D17 — Frontend

| Área | Cambios |
|---|---|
| Admin — Carta (`CategoryAdministrationPage`, `catalogService`) | Checkbox “Requiere preparación en cocina” (marcado por defecto) en alta/edición; indicador “Sin cocina” en la lista. |
| Mozo (`WaiterOrderPage`, `waiterOrderService`) | Edición y retiro `ABIERTO` vía RPC con la misma interfaz y UX H3 (E7-D15); indicador “Sin cocina” en carta y pedido; tras el envío, productos sin cocina se muestran como “Listo para servir”; acción “Cancelar producto” con motivo; sección “Cancelados”; tipos `requiere_cocina`. |
| Cocina (`KitchenBoardPage`, `kitchenRealtimeService`) | Snapshot unificado; botón “Recibir pedido (N)” por grupo; conflicto `PT409` tras cancelación; cancelaciones por grupo; comandas por grupo con `Imprimir`/`Reimprimir`. |
| Impresión | Componente de comanda 80 mm reutilizando las clases de impresión existentes en `index.css`. |
| Caja / Admin E1 | Sin cambios. |

## E7-D18 — Interacciones con E1 (sin cambios de E1)

- `tgf_bloquear_detalle_pedido_con_pago` impide cancelar y alterar detalles de un pedido con pagos: defensa adicional de E7-R12.
- `anular_pedido_supervisado` bloquea el pedido; una cancelación posterior ve `ANULADO` y falla con `PT409`.
- `Flujo actual de pedidos` y `Operación → Pedidos` leen cabecera/historial; reflejan correctamente pedidos sin cocina y cancelaciones.
- Descuentos: se solicitan sólo sobre `ENTREGADO`, donde no existen detalles cancelables. HZ-02 permanece fuera de E7.

## E7-D19 — Migraciones previstas (construcción futura)

Migraciones nuevas y aditivas, ordenadas después de `20260922000100_e1_delta_t18…`, sin editar migraciones históricas:

1. `…_e7_t02_modelo_cocina_historial_comanda.sql`: columnas, check, backfill, tablas nuevas, triggers de historial e inmutabilidad, grants de columna y comentarios.
2. `…_e7_t03_envio_sin_cocina_comanda.sql`: `agregar_detalle_pedido`, `enviar_pedido_cocina`.
3. `…_e7_t04_recepcion_completa_tablero.sql`: `rpc_obtener_tablero_cocina`, `rpc_recibir_pedido_cocina`, filtro en `obtener_tablero_cocina`, `PT409` en `actualizar_estado_detalle_cocina`.
4. `…_e7_t05_cancelacion_detalle.sql`: `rpc_cancelar_detalle_pedido`, `rpc_obtener_cancelaciones_pedido`.
5. `…_e7_t05b_edicion_retiro_abierto.sql`: `rpc_modificar_detalle_pedido`, `rpc_retirar_detalle_pedido`, revocación de grants y eliminación de las políticas de mutación directa.
6. `…_e7_t09_impresion_comanda.sql`: `rpc_registrar_impresion_comanda`.

Cada migración termina con `notify pgrst, 'reload schema'` y se aplica primero en local y luego en DEV, conforme a PM-002.

## E7-D20 — Estrategia de validación

Durante la construcción cada tarea ejecuta sólo sus verificaciones focalizadas (definidas en `tasks.md` y `test-plan.md` §2). La suite completa, la regresión H3/H4/H5/E1, el replay limpio de migraciones, las pruebas SQL integrales, seguridad, `typecheck` y `build` se ejecutan una vez, en la fase final E7-T11. Esto no reduce cobertura: E7 no se cierra con pruebas pendientes.

## Riesgos de diseño

| Riesgo | Mitigación |
|---|---|
| Cambio de catálogo durante un pedido abierto | Snapshot en detalle; consolidación por condición de cocina. |
| Cancelación en carrera con cocina | Lock por pedido, validación sobre estado persistido, `PT409` en ambos lados y resincronización. |
| Pedido sin detalles tras cancelar | Rama explícita en la RPC (`ABIERTO` vacío, mesa `OCUPADA`) sin tocar la derivación compartida. |
| Multiplicar consultas por señal en cocina | Lectura unificada `rpc_obtener_tablero_cocina`; debounce existente. |
| Reintentos automáticos de PostgREST | Ningún `40001`; recepción completa repetida es éxito sin cambios. |
| Comanda impresa y producto luego cancelado | Tablero muestra cancelaciones; reimpresión marca líneas canceladas; la tablet es la fuente de verdad. |
| Dos dispositivos solicitan imprimir la misma comanda | Lock + `PT409` en la primera solicitud de impresión; reimpresión explícita. |
| Impresora no disponible o incompatible | Impresión manual y opcional con la impresora del sistema operativo; no afecta estados; compatibilidad física verificada en validación humana (DH-02). |
| Retiro/edición H3 inconsistentes o con orden de locks inverso (HZ-01) | RPC de edición y retiro con orden `pedido → detalle → mesa` y derivación (DH-01). |
