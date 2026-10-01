# MikuyApp — Evolución 9 — Jornada operativa del local: diseño

**Estado de E9: SPEC MODE — listo para revisión humana final; no autorizado para construcción.** Diseño derivado de la inspección de `main` en `5e3b40b`. Incorpora las decisiones cerradas DC-10 (validación en puntos de entrada), DC-11 (local cerrado = sólo cerrar sesión) y DC-12 (sin backfill; aborto explícito de la migración) de `requirements.md` §10.2. No quedan decisiones humanas pendientes.

## E9-D01 — Principios y cambio mínimo

Se conserva la arquitectura vigente: React + TypeScript, Supabase/PostgreSQL, RLS, funciones `SECURITY DEFINER` con `search_path = pg_catalog`, invariantes en PostgreSQL, operaciones multi-registro en una única transacción, Realtime como señal y snapshot autoritativo. No se agrega backend, librería ni estado de pedido, detalle, mesa o sesión.

La regla central de E9 es **“sólo nace operación dentro de una jornada abierta, y una jornada sólo termina sin operación viva”**. Se implementa sobre las tablas donde nace la operación (`pedido`, `sesion_caja`) y donde se cruza pedido con caja (`pago`), no dentro de RPC concretas: así cubre toda vía vigente o heredada (HZ-05) sin modificar funciones aceptadas.

| Objeto | Cambio | Tipo |
|---|---|---|
| `jornada_operativa` | Tabla nueva: una fila por jornada, con cierre único. | Nueva |
| `pedido.jornada_operativa_id` | Columna `NOT NULL`, FK compuesta a la jornada del mismo local, inmutable. | Aditivo |
| `sesion_caja.jornada_operativa_id` | Ídem. | Aditivo |
| `fn_obtener_jornada_operativa_abierta(uuid)` | Función interna: devuelve y bloquea `FOR SHARE` la jornada abierta del local o rechaza “Local cerrado”. | Nueva |
| `tgf_pedido_asignar_jornada_operativa` + trigger | Asigna la jornada al insertar; impide cambiarla. | Nuevos |
| `tgf_sesion_caja_asignar_jornada_operativa` + trigger | Ídem para sesiones de caja. | Nuevos |
| `tgf_pago_validar_jornada_operativa` + trigger | Rechaza un pago cuyo pedido y sesión pertenecen a jornadas distintas. | Nuevos |
| `tgf_jornada_operativa_inmutable` + trigger | Sólo admite el cierre `ABIERTA → CERRADA`; rechaza borrado. | Nuevos |
| `rpc_abrir_jornada_operativa(uuid)` | Abre u obtiene la jornada abierta (ADMIN). | Nueva |
| `rpc_cerrar_jornada_operativa(bigint)` | Cierra la jornada si no hay pendientes (ADMIN). | Nueva |
| `rpc_obtener_jornada_operativa_actual()` | Estado del local para todos los roles del local. | Nueva (lectura) |
| `rpc_obtener_pendientes_cierre_jornada()` | Qué impide el cierre (ADMIN). | Nueva (lectura) |
| `rpc_obtener_historial_jornadas_operativas(integer, integer)` | Historial paginado (ADMIN). | Nueva (lectura) |
| `pol_jornada_operativa_select_local` | `SELECT` para los cuatro roles del mismo local (autorización Realtime). | Nueva |
| Publicación `supabase_realtime` | Se agrega `jornada_operativa`. | Aditivo |
| `operationalDayService` (frontend) | Lectura del estado, suscripción a la señal, abrir/cerrar, pendientes, historial. | Nuevo |
| `OperationalDayGate` + pantalla “Local cerrado” | Envuelve las rutas de MOZO, COCINA y CAJA en `App.tsx`. | Nuevo |
| `AdminHomePage`, `AdminShell`, `appRoutes`, página de historial | Bloque “Jornada operativa”, ítem de navegación y ruta `/admin/jornadas`. | Frontend |
| `CashierPage` | Muestra la identificación de la jornada junto al estado de caja (E9-R31). | Frontend mínimo |
| `waiterOrderService.openOrder` | Distingue el `PT409` de local cerrado (HZ-06). | Frontend mínimo |

**No se modifican:** `crear_o_recuperar_pedido_mesa`, `h3_abrir_o_recuperar_pedido`, `rpc_abrir_sesion_caja`, `fn_cerrar_sesion_caja` y sus envoltorios, `rpc_registrar_cobro_pedido` ni las vías de pago heredadas, `fn_resolver_total_pedido`, `cobro`, `pago` (salvo el trigger nuevo), descuentos, anulación, movimientos, auditoría, notificaciones, reportes, las RPC de H3/H4/E7/E10, `historial_estado`, ni las políticas RLS vigentes.

Nombres según `docs/DATABASE_STANDARD.md` (`rpc_`, `fn_`, `tgf_`, `trg_`, `pol_`, `ck_`, `uq_`, `idx_`, `fk_`). La tabla nueva conserva el estilo semántico vigente sin prefijo físico, decisión explícita del estándar §4 (igual que E1, E7 y E10); por clasificación sería un movimiento (`mov_`).

## E9-D02 — Modelo: alternativas evaluadas

| Alternativa | Evaluación |
|---|---|
| **Tabla transaccional `jornada_operativa` con cierre único (elegida)** | Representa cada periodo real de atención; admite varias por fecha, cruce de medianoche, unicidad de la abierta por índice parcial, FK obligatoria desde pedido y sesión, y trazabilidad de apertura/cierre en la propia fila. |
| Columna `abierto` / `jornada_abierta_desde` en `local` | No conserva historial, no permite asociar pedidos ni sesiones a un periodo y convierte una maestra en estado operativo. |
| Calendario o tabla de horarios/turnos | Prohibido por DC-01/DC-02. |
| Derivar la jornada de la sesión de caja (E1) | La sesión de caja pertenece a una caja física, puede cerrarse y reabrirse varias veces en una atención (cambio de cajero, DF-01) y no existe cuando aún no se abrió caja; no representa “local abierto”. |
| Tabla de eventos de apertura/cierre aparte de la jornada | Duplicaría lo que la fila ya conserva (una apertura y un cierre por jornada, inmutables). Sin valor adicional. |

## E9-D03 — Modelo `jornada_operativa`

```text
jornada_operativa
  id               bigint identity PK
  local_id         uuid        not null  FK local          ON DELETE RESTRICT
  fecha_operativa  date        not null
  numero           integer     not null  ck > 0
  estado           text        not null  default 'ABIERTA'   ck ∈ ABIERTA | CERRADA
  abierta_por      uuid        not null  FK perfil_usuario ON DELETE RESTRICT
  abierta_en       timestamptz not null
  cerrada_por      uuid        null      FK perfil_usuario ON DELETE RESTRICT
  cerrada_en       timestamptz null
  idempotency_key  uuid        not null
```

Restricciones e índices:

- `pk_jornada_operativa`; `fk_jornada_operativa_local`, `fk_jornada_operativa_abierta_por`, `fk_jornada_operativa_cerrada_por` (`RESTRICT`).
- `ck_jornada_operativa_estado_valido`; `ck_jornada_operativa_numero_positivo`.
- `ck_jornada_operativa_cierre_coherente`: `ABIERTA` ⇔ `cerrada_por` y `cerrada_en` nulos; `CERRADA` ⇒ ambos no nulos y `cerrada_en ≥ abierta_en`.
- `ck_jornada_operativa_fecha_operativa`: `fecha_operativa = (abierta_en AT TIME ZONE 'America/Lima')::date`. `timezone(text, timestamptz)` es `IMMUTABLE` en PostgreSQL (verificado en PostgreSQL 16), por lo que puede ser `CHECK`; Perú no tiene horario de verano.
- `uq_jornada_operativa_local_abierta`: índice único parcial `(local_id) WHERE estado = 'ABIERTA'` — **I-1**, defensa final ante cualquier carrera.
- `uq_jornada_operativa_local_fecha_numero (local_id, fecha_operativa, numero)` — unicidad de la identificación visible.
- `uq_jornada_operativa_idempotencia (local_id, abierta_por, idempotency_key)` — reintentos de apertura (patrón `uq_sesion_caja_idempotencia` de E1).
- `uq_jornada_operativa_id_local_id (id, local_id)` — destino de las FK compuestas desde `pedido` y `sesion_caja` (patrón `uq_mesa_id_local_id`).
- `idx_jornada_operativa_local_abierta_en (local_id, abierta_en desc)` — historial.
- `COMMENT ON` para tabla, fecha operativa, número, estados y restricciones (estándar §21).

Decisiones de columnas:

- **Identificación no persistida.** `Jornada YYYY-MM-DD (N)` se compone en las lecturas desde `fecha_operativa` y `numero` (3NF); `uq_jornada_operativa_local_fecha_numero` garantiza su unicidad.
- **`abierta_*`/`cerrada_*`** sustituyen a `creado_*`/`modificado_*`: la fila tiene exactamente un alta y a lo sumo un cierre, ambos inmutables.
- **Sin motivo de cierre, observaciones ni totales.** No los exige el alcance; los totales son E8.

## E9-D04 — Asociación de pedido y sesión de caja

```text
pedido.jornada_operativa_id       bigint not null
  fk_pedido_jornada_operativa_local       (jornada_operativa_id, local_id) → jornada_operativa(id, local_id) RESTRICT
  idx_pedido_jornada_operativa_id_estado  (jornada_operativa_id, estado)

sesion_caja.jornada_operativa_id  bigint not null
  fk_sesion_caja_jornada_operativa_local       (jornada_operativa_id, local_id) → jornada_operativa(id, local_id) RESTRICT
  idx_sesion_caja_jornada_operativa_id_estado  (jornada_operativa_id, estado)
```

- La FK compuesta garantiza que pedido/sesión y jornada son del mismo local (mismo patrón que `fk_pedido_mesa_local`).
- Los índices sirven exactamente a la verificación de cierre y a la lectura de pendientes (estándar §8.3).
- **Sin backfill (DC-07).** La migración agrega las columnas como `NOT NULL` directamente y, antes de hacerlo, verifica que `pedido` y `sesion_caja` no tengan filas; si las tienen, aborta con un mensaje explícito (DC-12). No se generan jornadas ficticias ni se modifican filas existentes; la preparación o limpieza del ambiente es una acción separada y autorizada por el responsable.
- **No se duplica la jornada** en `detalle_pedido`, `historial_estado`, `historial_detalle_pedido`, `comanda`, `solicitud_cuenta`, `descuento_pedido`, `anulacion_pedido`, `cobro`, `pago`, `movimiento_caja`, `resumen_cierre_sesion_caja`, `auditoria_caja` ni notificaciones: todas la derivan de forma unívoca por `pedido_id` o `sesion_caja_id`.

### Asignación e inmutabilidad por trigger

```text
fn_obtener_jornada_operativa_abierta(p_local_id uuid) returns bigint     -- interna, SECURITY DEFINER
  select id from jornada_operativa where local_id = p_local_id and estado = 'ABIERTA' for share
  si no existe → PT409 'Local cerrado — el sistema no se encuentra aperturado'

trg_pedido_before_insert_update_jornada_operativa
  BEFORE INSERT OR UPDATE OF jornada_operativa_id ON pedido FOR EACH ROW
  EXECUTE FUNCTION tgf_pedido_asignar_jornada_operativa()

trg_sesion_caja_before_insert_update_jornada_operativa
  BEFORE INSERT OR UPDATE OF jornada_operativa_id ON sesion_caja FOR EACH ROW
  EXECUTE FUNCTION tgf_sesion_caja_asignar_jornada_operativa()
```

Comportamiento de ambas funciones de trigger:

| Evento | Resultado |
|---|---|
| `INSERT` | `v_id := fn_obtener_jornada_operativa_abierta(new.local_id)`. Si `new.jornada_operativa_id` es nulo se asigna `v_id`; si viene informado y difiere → `42501` (“La jornada la asigna el servidor”). Sin jornada abierta → `PT409` “Local cerrado…”. |
| `UPDATE` que cambia `jornada_operativa_id` | Rechazo `23514` (“La jornada de un pedido/sesión es inmutable”). |

Justificación de hacerlo por trigger y no dentro de las RPC de creación:

1. **Cubre toda vía.** `crear_o_recuperar_pedido_mesa`, la heredada `h3_abrir_o_recuperar_pedido` (HZ-05) y `rpc_abrir_sesion_caja` quedan protegidas sin editarse; también cualquier vía futura.
2. **El cliente nunca decide la jornada** (E9-R14): ni las RPC ni el cliente la suministran; el valor proviene siempre de la jornada abierta bloqueada.
3. **Atomicidad.** El rechazo aborta la transacción de la RPC completa: no quedan `historial_estado`, cambio de mesa, `solicitud_apertura_caja` ni auditoría parciales.
4. **Precedentes.** E10 (`trg_pedido_after_update_cerrar_solicitud_cuenta`) y E7 (historial de detalle) ya expresan reglas transversales sobre transiciones de tabla mediante triggers documentados; el estándar §13.3 admite triggers para invariantes impracticables por constraint.

Los dos triggers son `SECURITY DEFINER` (necesitan leer y bloquear `jornada_operativa`, sin privilegios cliente), `search_path = pg_catalog`, sin `EXECUTE` para roles cliente.

**Orden de locks resultante.** Creación de pedido: `mesa (FOR UPDATE) → jornada (FOR SHARE)`. Apertura de caja: `caja (FOR UPDATE) → [sesión] → jornada (FOR SHARE)`. Ninguna de esas transacciones vuelve a esperar a otra después de tomar la jornada. El cierre de jornada sólo toma `jornada (FOR UPDATE)` y luego **lee sin bloquear** pedidos y sesiones. No hay ciclos de espera posibles.

## E9-D05 — Validación en operaciones críticas (DC-10)

**Decisión cerrada DC-10.** La validación autoritativa se compone de tres piezas, todas en PostgreSQL, y **no** se repite en las RPC operativas existentes:

| Pieza | Mecanismo | Cubre |
|---|---|---|
| Puntos de entrada | Triggers de E9-D04 sobre `pedido` y `sesion_caja`. | Toda creación de pedido y toda apertura de caja. |
| Coherencia de cobro | `trg_pago_before_insert_validar_jornada_operativa` (E9-D06). | Todas las vías de cobro, vigentes y heredadas. |
| Cierre restringido | `rpc_cerrar_jornada_operativa` (E9-D08) exige 0 pedidos no terminales y 0 sesiones abiertas. | Hace verdaderas I-2 e I-3. |

Con I-2 e I-3, todas las demás operaciones quedan inaplicables con el local cerrado porque **ya validan** que exista un pedido no terminal o una sesión `ABIERTA` del local:

| Operación (función vigente) | Precondición vigente que la hace inaplicable sin jornada |
|---|---|
| `agregar_detalle_pedido`, `rpc_modificar_detalle_pedido`, `rpc_retirar_detalle_pedido`, `enviar_pedido_cocina`, políticas `detalle_pedido_update/delete_abierto_mozo` | Pedido en estado operativo |
| `actualizar_estado_detalle_cocina`, `rpc_recibir_pedido_cocina`, `rpc_registrar_impresion_comanda`, `rpc_cancelar_detalle_pedido` | Pedido/detalle en estados de cocina |
| `entregar_pedido`, `rpc_solicitar_cuenta_pedido`, `liberar_mesa_pedido_vacio` | Pedido `LISTO` / `ENTREGADO` / `ABIERTO` vacío |
| `rpc_solicitar_descuento_pedido`, `rpc_decidir_descuento_pedido`, `anular_pedido_supervisado` | Pedido no terminal |
| `rpc_registrar_cobro_pedido`, `registrar_pago_pedido`, `rpc_registrar_pago_total_pedido`, `rpc_registrar_pago_pedido_v2` | Sesión `ABIERTA` y pedido `ENTREGADO` |
| `rpc_registrar_movimiento_caja`, `registrar_movimientos_caja`, `rpc_cerrar_sesion_caja`, `rpc_cerrar_sesion_caja_supervisor` | Sesión `ABIERTA` (el reintento idempotente de un cierre ya hecho devuelve el resumen existente, sin efectos) |
| `crear_o_recuperar_pedido_mesa` (rama de recuperación) | No existe pedido vigente que recuperar; la rama de creación cae en el trigger |

El plan de pruebas verifica **cada fila** con el local cerrado (E9-TP08). Ninguna de estas funciones ni políticas se modifica en E9. Consecuencia aceptada: con el local cerrado, su rechazo usa el conflicto vigente de cada operación (p. ej. pedido no vigente o sesión no abierta) y no el mensaje “Local cerrado”; la interfaz de los roles operativos no llega a invocarlas porque muestra la pantalla de local cerrado (E9-D13).

## E9-D06 — Coherencia pedido / sesión en el cobro

```text
trg_pago_before_insert_validar_jornada_operativa
  BEFORE INSERT ON pago FOR EACH ROW
  EXECUTE FUNCTION tgf_pago_validar_jornada_operativa()     -- SECURITY DEFINER
```

- Si `new.sesion_caja_id` es nulo → rechazo `23514` (no existe ya ninguna vía vigente que pague sin sesión: `registrar_pago_pedido` delega en `rpc_registrar_pago_total_pedido` con sesión; sin datos históricos no hay pagos legacy que proteger).
- Lee `sesion_caja.jornada_operativa_id` y `pedido.jornada_operativa_id` (filas ya bloqueadas por la RPC de cobro, sin locks nuevos). Si difieren → `PT409` (“El pedido y la sesión de caja pertenecen a jornadas distintas”).
- Se ubica en `pago` porque **toda** vía de cobro inserta al menos una fila `pago` con su `sesion_caja_id` (`rpc_registrar_cobro_pedido` inserta `cobro` y sus N `pago`; las vías heredadas insertan `pago`). Un único trigger cubre las cuatro vías sin modificarlas; un fallo revierte el `cobro` y la auditoría de la misma transacción.
- Por I-1–I-3 la condición no debería ocurrir nunca; el trigger hace explícita I-4 y la deja probada.

## E9-D07 — `rpc_abrir_jornada_operativa`

`rpc_abrir_jornada_operativa(p_idempotency_key uuid) returns table (jornada_operativa_id bigint, identificacion text, fecha_operativa date, numero integer, estado text, abierta_por uuid, abierta_en timestamptz, ya_existia boolean)`

1. `auth.uid()` + `obtener_contexto_autenticado()`: rol `ADMINISTRADOR` activo y local; si no → `42501`. `p_idempotency_key` nulo → `22023`.
2. `SELECT … FROM local WHERE id = v_local FOR NO KEY UPDATE`: serializa aperturas del local sin bloquear las comprobaciones de FK de otras transacciones (verificado: `FOR NO KEY UPDATE` no entra en conflicto con el `FOR KEY SHARE` de una FK).
3. Si existe una jornada con `(local_id, abierta_por, idempotency_key)` → devolverla tal cual (aunque esté `CERRADA`), `ya_existia = true`. Un reintento nunca abre otra.
4. Si existe una jornada `ABIERTA` del local → devolverla, `ya_existia = true` (doble clic con otra clave, segundo administrador).
5. `v_ahora := clock_timestamp()` (tras el lock); `v_fecha := (v_ahora AT TIME ZONE 'America/Lima')::date`; `v_numero := coalesce(max(numero), 0) + 1` para `(local, v_fecha)`.
6. Insertar la fila `ABIERTA` con `abierta_por = auth.uid()`, `abierta_en = v_ahora`; devolverla con `ya_existia = false`.
7. Un `23505` sobre `uq_jornada_operativa_local_abierta` o `uq_jornada_operativa_local_fecha_numero` (imposible bajo el lock, conservado como defensa) se resuelve releyendo y devolviendo la abierta; nunca se expone ni se convierte en `40001`.

No recibe local, fecha, número, actor ni hora. No escribe pedidos, mesas ni caja.

## E9-D08 — `rpc_cerrar_jornada_operativa`

`rpc_cerrar_jornada_operativa(p_jornada_operativa_id bigint) returns table (jornada_operativa_id bigint, identificacion text, estado text, abierta_por uuid, abierta_en timestamptz, cerrada_por uuid, cerrada_en timestamptz, ya_estaba_cerrada boolean)`

1. Contexto `ADMINISTRADOR` activo; si no → `42501`. Parámetro nulo → `22023`.
2. `SELECT … FROM jornada_operativa WHERE id = p AND local_id = v_local FOR UPDATE`; no existe u otro local → `42501`.
3. Si ya está `CERRADA` → devolverla, `ya_estaba_cerrada = true`, sin escribir.
4. **En sentencias nuevas** (snapshot fresco bajo `READ COMMITTED`, posterior a la obtención del lock): contar `sesion_caja` de la jornada con `estado = 'ABIERTA'` y `pedido` de la jornada con `estado NOT IN ('PAGADO','ANULADO')`. Si alguno > 0 → `PT409` “No se puede cerrar la jornada: N pedidos pendientes y M sesiones de caja abiertas”.
5. `UPDATE … SET estado = 'CERRADA', cerrada_por = auth.uid(), cerrada_en = greatest(clock_timestamp(), abierta_en)`; devolver con `ya_estaba_cerrada = false`.

**Por qué es seguro sin bloquear pedidos ni sesiones.** Toda creación de pedido o sesión toma `FOR SHARE` sobre la jornada (E9-D04), que entra en conflicto con el `FOR UPDATE` del cierre:

- Si una creación confirma antes, el cierre espera su commit y la ve en el paso 4 → rechazo.
- Si el cierre toma el lock antes, la creación espera; al confirmarse el cierre, su `SELECT … WHERE estado = 'ABIERTA' FOR SHARE` reevalúa la fila actualizada, ya no la encuentra → “Local cerrado” (verificado en PostgreSQL 16).
- Un pedido terminal no vuelve a estado operativo y una sesión cerrada no se reabre, por lo que transacciones concurrentes de cobro, anulación o cierre de caja sólo pueden **reducir** los pendientes: en el peor caso el cierre rechaza de forma conservadora y el administrador reintenta.

Sin `40001`, sin reintentos automáticos de PostgREST, sin esperas activas.

## E9-D09 — Inmutabilidad de la jornada

`trg_jornada_operativa_before_update_delete_inmutable` ejecuta `tgf_jornada_operativa_inmutable`:

- `DELETE` → rechazado.
- `UPDATE` → sólo si `old.estado = 'ABIERTA'`, `new.estado = 'CERRADA'` y no cambian `id`, `local_id`, `fecha_operativa`, `numero`, `abierta_por`, `abierta_en` ni `idempotency_key`. Cualquier otra modificación, incluida `CERRADA → ABIERTA`, se rechaza (I-5).
- `authenticated` sólo recibe `SELECT`; sin `INSERT/UPDATE/DELETE` directos. `public`, `anon` y `service_role` sin privilegios sobre tabla y secuencia (lección E7-T10: `TRUNCATE` de `service_role` eludiría los triggers).

## E9-D10 — Lecturas

| RPC | Roles | Devuelve | Notas |
|---|---|---|---|
| `rpc_obtener_jornada_operativa_actual()` `STABLE` | Los cuatro roles activos del local | Cero filas si el local está cerrado; si está abierto, una fila: `jornada_operativa_id`, `identificacion`, `fecha_operativa`, `numero`, `abierta_en`, `abierta_por_nombre`, `servidor_ahora`. | Única lectura que usa el `OperationalDayGate`. El nombre del administrador se resuelve dentro de la función sin ampliar `SELECT` sobre `perfil_usuario` (patrón E1-D11/E10-D08). `servidor_ahora` evita depender del reloj del dispositivo (patrón E1-D16). |
| `rpc_obtener_pendientes_cierre_jornada()` `STABLE` | `ADMINISTRADOR` | Filas `tipo ∈ (PEDIDO, SESION_CAJA)`: para pedidos `pedido_id`, `mesa_codigo`, `estado`, `creado_en`; para sesiones `sesion_caja_id`, `caja_codigo`, `abierta_por_nombre`, `abierta_en`. Vacío si el local está cerrado o no hay pendientes. | Sin importes ni saldos. Informativa: el cierre vuelve a decidir (E9-R22). |
| `rpc_obtener_historial_jornadas_operativas(p_limite integer default 50, p_offset integer default 0)` `STABLE` | `ADMINISTRADOR` | `jornada_operativa_id`, `identificacion`, `estado`, `abierta_por_nombre`, `abierta_en`, `cerrada_por_nombre`, `cerrada_en`, ordenado por `abierta_en desc, id desc`. | Paginación validada como `rpc_obtener_historial_sesiones_caja` (1–200, offset ≥ 0, si no `22023`). Sin totales ni conteos (E9-R25). |

Todas: `SECURITY DEFINER`, `search_path = pg_catalog`, contexto revalidado, `42501` fuera de rol/local, `EXECUTE` sólo `authenticated`. La identificación se compone como `'Jornada ' || to_char(fecha_operativa,'YYYY-MM-DD') || ' (' || numero || ')'` en un único lugar reutilizado (expresión interna o función `fn_formatear_identificacion_jornada(date, integer)` `IMMUTABLE`).

## E9-D11 — Seguridad, RLS y privilegios

- `pol_jornada_operativa_select_local`: `FOR SELECT TO authenticated USING` existe contexto activo con `local_id = jornada_operativa.local_id` (cualquiera de los cuatro roles). Necesaria para la autorización Realtime; expone sólo identificadores y timestamps, sin nombres ni datos financieros. No se restringe a filas `ABIERTA` para MOZO/COCINA/CAJA porque Realtime evalúa la RLS sobre la fila nueva: con esa restricción el `UPDATE` a `CERRADA` no les llegaría y no se enterarían del cierre (mismo fenómeno que E10 HZ-02). La interfaz no les ofrece historial; los nombres de actores sólo se exponen por las RPC.
- Sin políticas de escritura; `GRANT SELECT` a `authenticated`; `REVOKE ALL` a `public`, `anon`, `service_role` sobre tabla y secuencia.
- RPC: `SECURITY DEFINER`, owner `postgres`, `search_path = pg_catalog`, referencias calificadas, `REVOKE ALL FROM public, anon, service_role`, `GRANT EXECUTE TO authenticated`.
- Funciones de trigger y `fn_obtener_jornada_operativa_abierta`: sin `EXECUTE` para ningún rol cliente.
- Columnas nuevas de `pedido` y `sesion_caja`: sin cambio de privilegios ni de políticas (las tablas no conceden `INSERT`/`UPDATE` directos al cliente; las políticas de lectura existentes las exponen igual que el resto de columnas).
- Códigos: `42501` no autorizado / otro local / jornada suministrada por el cliente; `22023` entrada inválida; `23514` violación de inmutabilidad; `PT409` conflicto funcional (local cerrado, cierre impedido, jornadas distintas); nunca `40001`.

## E9-D12 — Realtime

**Decisión: publicar `jornada_operativa` en `supabase_realtime`** y escucharla desde una suscripción propia del estado del local, no desde las suscripciones operativas de cada pantalla.

| Alternativa | Evaluación |
|---|---|
| **Publicar `jornada_operativa` + suscripción propia del gate (elegida)** | Apertura (`INSERT`) y cierre (`UPDATE`) producen señal para los cuatro roles del local por RLS. Una sola suscripción por dispositivo, viva también mientras la pantalla operativa está desmontada (local cerrado). Cocina no cambia su `kitchenRealtimeService` ni sus enlaces. |
| Agregar `jornada_operativa` a `additionalSignalTables` de cada pantalla | Cocina no usa `operationsRealtimeService`; con el local cerrado la pantalla operativa no está montada y no podría enterarse de la apertura. |
| Inferir el cierre de las señales de `pedido`/`mesa` | La apertura y el cierre no modifican esas tablas. |
| Polling | Prohibido. |

Detalle:

- Migración: `alter publication supabase_realtime add table public.jornada_operativa` idempotente (comprobando `pg_publication_tables`). No se quita ni cambia ninguna tabla publicada. Resultado: cinco tablas (HZ-08).
- `operationalDayService.subscribe` reutiliza el patrón de `operationsRealtimeService`: topic propio por suscripción (`subscriptionTopic`), eventos `INSERT`/`UPDATE`, debounce y coalescencia, recarga en `SUBSCRIBED`, resincronización ante `CHANNEL_ERROR`/`TIMED_OUT`/`CLOSED`. `operationsRealtimeService` no se modifica ni se refactoriza: E9 reutiliza su patrón y, como única pieza compartida, la función exportada existente `subscriptionTopic`. Un refactor transversal sólo se consideraría si durante la construcción se demuestra estrictamente necesario, y requeriría registrarlo como decisión.
- Los payloads no se usan como dato: cada evento sólo agenda la relectura de `rpc_obtener_jornada_operativa_actual()`.
- Volumen: dos eventos por jornada. Impacto despreciable frente a `detalle_pedido`.

## E9-D13 — Frontend: `OperationalDayGate` y pantalla “Local cerrado”

`OperationalDayGate` envuelve en `App.tsx` todo lo que se renderiza para `MOZO`, `COCINA` y `CAJA` una vez resuelta la ruta (`/mozo/*`, `/cocina`, `/caja`, `/ventas` y `/tecnica` para esos roles — DC-11). No envuelve `/login`, `/403` ni las rutas ADMIN.

| Estado del gate | Render |
|---|---|
| `loading` (primera lectura) | “Verificando el estado del local…”, con `aria-busy`. |
| `open` | La pantalla solicitada, sin cambios visuales. El gate expone por contexto React `{ jornada, resync }` (`useOperationalDay()`). |
| `closed` | `LocalClosedScreen`: título **“Local cerrado — el sistema no se encuentra aperturado”**, texto de apoyo (“Cuando el administrador abra la jornada, esta pantalla se habilitará automáticamente.”), local, `AuthenticatedUserMenu` con **Cerrar sesión**, botón **Actualizar**. Sin navegación operativa. |
| `error` | Mensaje de verificación fallida con **Reintentar** y **Cerrar sesión**; no muestra la pantalla operativa (fail-closed, E9-R12). |

Transiciones:

- `open → closed` por señal: la pantalla operativa se desmonta (sus suscripciones se detienen como hoy al navegar). Por E9-R20 no puede haber trabajo en curso que perder: no existen pedidos vigentes ni caja abierta.
- `closed → open` por señal: se monta la pantalla solicitada desde cero con su carga inicial habitual.
- Un `PT409` “Local cerrado…” recibido por una pantalla (p. ej. carrera con el cierre) llama a `resync()` del gate. Ajuste mínimo en `waiterOrderService.openOrder` (HZ-06) y en la apertura de caja de `cashierService`/`CashierPage`; el resto de servicios no cambia.
- Sin almacenamiento del navegador; el estado vive en memoria y siempre proviene de la RPC.

`CashierPage` lee `useOperationalDay().jornada` y muestra “Jornada 2026-10-01 (1)” junto al estado de caja (E9-R31). Mozo y cocina no cambian con el local abierto.

## E9-D14 — Frontend ADMIN

| Elemento | Comportamiento |
|---|---|
| Inicio — bloque “Jornada operativa” (primer bloque de la página) | **Cerrado:** “Local cerrado” + botón primario **Abrir jornada** → confirmación en línea (“¿Abrir la jornada operativa del local? Mozo, Cocina y Caja podrán operar.”). **Abierto:** “Jornada 2026-10-01 (1) · abierta por {nombre} a las hh:mm” (y “desde el dd/mm” si cambió el día) + botón **Cerrar jornada** → confirmación (“Se verificará que no queden pedidos ni cajas abiertas.”). Guard `useRef` + deshabilitado durante la operación; mensajes de error y reintento; resultado `ya_existia`/`ya_estaba_cerrada` informado sin tratarlo como error. |
| Cierre impedido | Ante `PT409` se carga `rpc_obtener_pendientes_cierre_jornada()` y se listan pedidos (mesa, pedido, estado) y sesiones (caja, abierta por, desde) con enlaces a **Operación → Pedidos** e **Reportes → Caja**, y la secuencia sugerida: cobrar o anular pedidos → cerrar caja → cerrar jornada. |
| Navegación | `OPERACIÓN → Jornadas` (`/admin/jornadas`, nuevo `ApplicationRoute`, sólo ADMIN en `resolveApplicationRoute`). |
| `/admin/jornadas` | Tabla responsive del historial (identificación, estado, apertura, cierre) con “Cargar más” sobre la paginación de la RPC. Sin totales. |
| Señal | Inicio usa la misma suscripción del estado del local para reflejar aperturas/cierres hechos por otro administrador. |

## E9-D15 — Integración con E1, E7, E10 y el MVP

- **E1 caja.** DF-08 (caja única automática), recuperación de sesión abierta por cualquier `CAJA` (E1-R02), cierre normal y supervisor, movimientos y arqueo no cambian. Una jornada puede contener varias sesiones de caja sucesivas (cambio de cajero con cierre y nueva apertura). DF-01 sigue permitido: cerrar caja con pedidos `ENTREGADO` pendientes; esos pedidos se cobran en una sesión posterior **de la misma jornada**, y la jornada no puede cerrarse hasta entonces (HZ-04). No existe cobro posible de un pedido de una jornada en una sesión de otra (I-4).
- **E1 descuentos y anulación.** Sin cambios; sólo aplican a pedidos no terminales, por lo tanto dentro de la jornada abierta. Un pedido con cobros parciales no es anulable (E1-R12) y sólo puede resolverse con el cobro total.
- **E1 Inicio, reportes, auditoría y notificaciones.** Sin cambios; siguen por fecha calendario (HZ-03). El bloque de jornada se agrega a Inicio sin alterar los bloques existentes ni su orden.
- **E7.** Cocina, recepción completa, cancelación y comandas no cambian; el trigger sobre `pedido` es `BEFORE INSERT/UPDATE OF jornada_operativa_id` y no interfiere con los triggers de detalle ni con el `AFTER UPDATE OF estado` de E10. La corrección de Realtime E7-T12 se conserva.
- **E10.** Las solicitudes de cuenta pendientes sólo existen sobre pedidos `ENTREGADO`; cerrarlas forma parte del cobro o anulación ya vigentes (HZ-09).
- **H3/H5.** `liberar_mesa_pedido_vacio` es la forma de resolver un pedido `ABIERTO` vacío antes del cierre; la reapertura H5 de `ENTREGADO` antes del primer pago no cambia y mantiene el pedido en su jornada.

## E9-D16 — Homologación mínima de tests vigentes (HZ-01)

E9 introduce una precondición global nueva: todo `pedido` y toda `sesion_caja` necesitan una jornada abierta del mismo local. Los tests vigentes del repositorio que crean esas filas directamente dejan de cumplirla y, como ocurre siempre que el modelo de datos evoluciona, **se actualizan directamente en el repositorio durante la construcción**. Git conserva sus versiones anteriores; no se mantienen copias, transformaciones dinámicas ni mecanismos paralelos.

Regla:

> Cuando un test vigente cree directamente `pedido` o `sesion_caja`, su fixture se actualiza mínimamente para crear primero una jornada abierta válida. La modificación se limita a incorporar la precondición de E9 y los ajustes de limpieza estrictamente necesarios, sin alterar el comportamiento verificado, los datos relevantes, las aserciones ni el objetivo funcional original del test.

Alcance y límites:

1. **Precondición.** El fixture inserta, antes del primer `pedido` o `sesion_caja`, una fila `jornada_operativa` `ABIERTA` válida para su local (fecha operativa coherente con `abierta_en`, número correlativo, `abierta_por` un perfil del fixture), respetando todas las restricciones de E9.
2. **Limpiezas estrictamente necesarias.** La jornada es inmutable por diseño y no se borra. Donde un fixture limpia sus pedidos y sesiones, cierra su jornada mediante la transición permitida `ABIERTA → CERRADA` y deja de borrar las filas que la jornada referencia (`local`, `perfil_usuario`); el setup correspondiente tolera su existencia y crea una jornada nueva para su local (las jornadas cerradas nunca se reabren). La base de pruebas local se recrea en cada replay.
3. **Contratos que E9 cambia deliberadamente.** Los tests vigentes que fijan algo que E9 modifica a propósito se actualizan en el mismo sentido mínimo, sin crear tests sustitutos: la publicación exacta (`h4_t05_realtime_publication_rls.sql`, `h5_t06_realtime_cashier_signal.sql`) pasa a esperar también `jornada_operativa` (HZ-08), y las aserciones exactas sobre las claves de `to_jsonb(sesion_caja)` incorporan `jornada_operativa_id` (HZ-07).
4. **Sin mecanismos especiales.** No se crean triggers, funciones, roles ni configuraciones de base de datos exclusivos para tests; no se desactiva ni se evade la inmutabilidad (`DISABLE TRIGGER`, `session_replication_role` u otros); no se crean jornadas automáticamente al insertar locales.
5. **Evidencia histórica intacta.** No se modifican los documentos de aceptación ni de evidencia de H1–H6, E1, E7 y E10 (`acceptance.md`, `implementation*.md`, `*_execution.md`, logs y registros de campañas). La lista de tests actualizados y el motivo de cada cambio se registra en la evidencia de E9.
6. **Criterio de éxito.** Los tests afectados por E9 deben **pasar** después de su homologación. Un fallo no se acepta por haber existido antes: sólo puede tratarse como ajeno a E9 si (a) se demuestra que ocurre también contra la baseline anterior a E9, (b) se documenta individualmente con su causa, (c) no se oculta ni se considera aprobado automáticamente y (d) se informa al responsable antes de dar por finalizada E9-T07, que decide su tratamiento.
7. **Tests de E9.** Las suites nuevas de E9 se escriben desde el inicio con su precondición de jornada y no reemplazan tests existentes que sólo necesitan homologación.

La homologación se realiza en el repositorio dentro de E9-T07, antes de ejecutar la regresión integral (TP24).

## E9-D17 — Migraciones previstas

Nuevas y posteriores a `20260930000200`, sin editar migraciones históricas:

1. `…_e9_t02_jornada_operativa.sql`: precondición de tablas vacías con aborto explícito (DC-12); tabla, restricciones, índices, comentarios, RLS, política, privilegios, trigger de inmutabilidad, `fn_obtener_jornada_operativa_abierta`, columnas y FK en `pedido`/`sesion_caja`, triggers de asignación, trigger de coherencia en `pago`, publicación.
2. `…_e9_t03_rpc_jornada_operativa.sql`: las cinco RPC con privilegios y comentarios.

Ambas aditivas. Para el frontend ya desplegado (PM-002 `TRANSITIONING`) el efecto visible es intencional: sin jornada abierta no se pueden crear pedidos ni abrir caja; por eso E9 no debe aplicarse a un ambiente con datos ni a un ambiente compartido sin la acción separada y autorizada de preparación (DC-12), ni sin desplegar a la vez el frontend que permite abrir la jornada. `mikuyapp-prod` no se toca.

## E9-D18 — Estrategia de validación

Igual que E7/E10: cada tarea ejecuta sólo sus verificaciones focalizadas; la suite completa, la regresión H3–E10 con los tests vigentes homologados en el repositorio según E9-D16, el replay limpio, las pruebas SQL integrales, seguridad, concurrencia, Realtime, `typecheck` y `build` se ejecutan una vez en la fase final E9-T07.

## Riesgos de diseño

| Riesgo | Mitigación |
|---|---|
| Dos jornadas abiertas por carrera | Lock `FOR NO KEY UPDATE` del local + `uq_jornada_operativa_local_abierta`. |
| Jornada cerrada con operación viva | `FOR SHARE` en cada creación vs `FOR UPDATE` en el cierre; verificación en sentencia nueva; pruebas de carrera reales en ambos órdenes. |
| Interbloqueos | Orden único: la jornada es siempre el último lock de los creadores y el único del cierre. |
| Pedido o sesión creados sin jornada por una vía no prevista | Trigger sobre la tabla, no sobre la RPC; `NOT NULL` + FK compuesta como defensa final. |
| Jornada abierta olvidada durante días | Permitido por diseño (sin cierre automático); Inicio muestra desde cuándo está abierta. |
| Migración sobre ambiente con datos | Precondición explícita y aborto (DC-12); preparación del ambiente separada y autorizada. |
| Regresión rota por la columna obligatoria | Homologación mínima de los tests vigentes en el repositorio (E9-D16); los tests afectados deben pasar; sin mecanismos de base de datos exclusivos para tests ni edición de evidencia histórica. |
| Dispositivo con estado desactualizado | Señal Realtime + relectura autoritativa + fail-closed + `resync` ante `PT409`; PostgreSQL decide siempre. |
| Fallos de tests que no se deben a E9 | Demostración contra la baseline anterior a E9, documentación individual e informe al responsable antes de cerrar T07; nunca aceptación automática (E9-D16). |
| Reportes diarios que no coinciden con la jornada | Documentado (HZ-03); fuera de alcance. |
