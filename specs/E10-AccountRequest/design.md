# MikuyApp — Evolución 10 — Solicitud de cuenta y atención en caja: diseño

**Estado: DISEÑO APROBADO (30/09/2026).** Diseño derivado de la inspección de `main` en `ee3c94c`, con las decisiones aprobadas DH-01 A (el cobro no exige solicitud previa) y DH-02 B (invalidación del borrador de Caja acotada al pedido seleccionado); ver `requirements.md` §10. Construcción habilitada, no iniciada.

## E10-D01 — Principios y cambio mínimo

Se conserva la arquitectura vigente: React + TypeScript, Supabase/PostgreSQL, RLS, funciones `SECURITY DEFINER` con `search_path = pg_catalog`, invariantes en PostgreSQL, operaciones multi-registro en una única transacción, Realtime como señal y snapshot autoritativo. No se agrega backend, librería ni estado de pedido, detalle o mesa.

| Objeto | Cambio | Tipo |
|---|---|---|
| `solicitud_cuenta` | Tabla nueva: una fila por solicitud, con cierre único. | Nueva |
| `rpc_solicitar_cuenta_pedido(bigint)` | Crea u obtiene la solicitud pendiente (MOZO). | Nueva |
| `tgf_pedido_cerrar_solicitud_cuenta` + `trg_pedido_after_update_cerrar_solicitud_cuenta` | Cierra la solicitud pendiente cuando el pedido sale de `ENTREGADO`. | Nuevos |
| `tgf_solicitud_cuenta_inmutable` + `trg_solicitud_cuenta_before_update_delete_inmutable` | Sólo admite el cierre `PENDIENTE → ATENDIDA/SIN_EFECTO`; rechaza borrado. | Nuevos |
| `pol_solicitud_cuenta_select_local` | `SELECT` para `MOZO` y `CAJA` del mismo local (lectura embebida y autorización Realtime). | Nueva |
| Publicación `supabase_realtime` | Se agrega `solicitud_cuenta`. | Aditivo |
| `obtener_pedidos_pendientes_pago_caja()` | Agrega al final `solicitud_cuenta_id`, `cuenta_solicitada_en`, `cuenta_solicitada_por_nombre`, `servidor_ahora`. Columnas y filtros existentes sin cambios. | Lectura extendida |
| `operationsRealtimeService` | Opción para escuchar tablas de señal adicionales; por defecto sin cambios. | Frontend aditivo |
| `waiterOrderService`, `WaiterOrderPage`, `WaiterTablesPage` | Solicitar cuenta, estado e indicador. | Frontend |
| `cashierService`, `CashierPage` | Indicador, prioridad, contador, datos de la solicitud; invalidación acotada del borrador (DH-02 B). | Frontend |

**No se modifican:** `rpc_registrar_cobro_pedido` ni las demás vías de pago, `fn_resolver_total_pedido`, `cobro`, `pago`, `descuento_pedido`, `auditoria_caja`, `entregar_pedido`, `sincronizar_estado_operativo_pedido`, `agregar_detalle_pedido`, `anular_pedido_supervisado`, `historial_estado`, las RPC de E7 ni las políticas RLS vigentes.

Nombres según `docs/DATABASE_STANDARD.md` (`rpc_`, `tgf_`, `trg_`, `pol_`, `ck_`, `uq_`, `idx_`). La tabla nueva conserva el estilo semántico vigente sin prefijo físico (decisión explícita del estándar §4, igual que E1/E7).

## E10-D02 — Modelo: alternativas evaluadas

| Alternativa | Evaluación |
|---|---|
| **Tabla nueva `solicitud_cuenta` con cierre único (elegida)** | Representa la solicitud como entidad operativa independiente, sin tocar estados. Admite una restricción única parcial para la idempotencia, conserva solicitudes `SIN_EFECTO` tras reaperturas y deja un cierre explícito con actor/hora para E8. Sin datos financieros, por lo que puede publicarse en Realtime con RLS (E1-D11). |
| Estado nuevo `CUENTA_SOLICITADA` en `pedido`/`mesa` | Prohibido por el alcance; obligaría a cambiar checks, derivación, entrega, cobro, reapertura, RLS, reportes y pruebas H3–E7. |
| Columnas `cuenta_solicitada_en/por` en `pedido` | Pierde las solicitudes previas a una reapertura, mezcla un aviso con la cabecera y funciona en la práctica como un estado global encubierto. |
| Evento en `historial_estado` | Esa tabla sólo registra estados reales de cabecera (E7-R20); insertar un “estado” ficticio rompería su semántica y las lecturas E1-T16/T17. |
| Evento en `auditoria_caja` | Es auditoría financiera de Caja con catálogo cerrado (E1-D10); el actor aquí es el mozo y no hay importe. |
| Idempotencia por clave del cliente (`idempotency_key`) | Innecesaria: la regla de negocio “una pendiente por pedido” ya es la clave natural; una clave del cliente no evitaría duplicados entre dos dispositivos o dos mozos. |

## E10-D03 — Modelo `solicitud_cuenta`

```text
solicitud_cuenta
  id                 bigint identity PK
  local_id           uuid    not null  FK local          ON DELETE RESTRICT
  pedido_id          bigint  not null  FK pedido         ON DELETE RESTRICT
  estado             text    not null  default 'PENDIENTE'
                                       ck ∈ PENDIENTE | ATENDIDA | SIN_EFECTO
  solicitada_por     uuid    not null  FK perfil_usuario ON DELETE RESTRICT
  solicitada_en      timestamptz not null
  cerrada_en         timestamptz null
  cerrada_por        uuid    null      FK perfil_usuario ON DELETE RESTRICT
  motivo_sin_efecto  text    null      ck ∈ REAPERTURA | ANULACION
```

Restricciones e índices:

- `ck_solicitud_cuenta_estado_valido`.
- `ck_solicitud_cuenta_cierre_coherente`: `PENDIENTE` ⇔ `cerrada_en`, `cerrada_por` y `motivo_sin_efecto` nulos; `ATENDIDA` ⇒ `cerrada_en` no nulo y `motivo_sin_efecto` nulo; `SIN_EFECTO` ⇒ `cerrada_en` y `motivo_sin_efecto` no nulos. `cerrada_por` sólo puede ser nulo en `PENDIENTE` o en un cierre ejecutado sin actor autenticado (mantenimiento; no existe en los flujos de la aplicación).
- `uq_solicitud_cuenta_pedido_pendiente`: índice único parcial `(pedido_id) WHERE estado = 'PENDIENTE'` — máximo una pendiente por pedido; defensa final de la idempotencia.
- `idx_solicitud_cuenta_pedido_solicitada_en (pedido_id, solicitada_en)` para lecturas por pedido y el uso posterior de E8.
- `COMMENT ON` para la tabla, columnas de tiempo y restricciones (estándar §21).

Decisiones de columnas:

- **Mesa derivada, no copiada.** `pedido.mesa_id` es inmutable: no existe traslado de mesa y `authenticated` no tiene `UPDATE` sobre `pedido`. La FK compuesta `fk_pedido_mesa_local` garantiza que mesa y local coinciden. Si una evolución futura permitiera trasladar pedidos entre mesas, deberá agregar el snapshot de mesa.
- **`local_id` copiado del pedido** por la RPC (única vía de escritura): lo exige la RLS sin joins y es consistente con el resto del modelo.
- **Sin `cobro_id`.** El cobro final se obtiene de forma unívoca como el `cobro` del pedido con `saldo_posterior = 0`; el actor que cerró queda en `cerrada_por`. Evita acoplar la tabla a la cabecera E1 y a las vías históricas sin cabecera.
- **Sin estado “en atención”** (E10-D10).

## E10-D04 — `rpc_solicitar_cuenta_pedido`

`rpc_solicitar_cuenta_pedido(p_pedido_id bigint) returns table (solicitud_id bigint, pedido_id bigint, estado text, solicitada_en timestamptz, solicitada_por uuid, ya_existia boolean)`

1. `auth.uid()` + `obtener_contexto_autenticado()`: rol `MOZO` activo y local; si no → `42501`. `p_pedido_id` nulo → `22023`.
2. Bloquear el pedido `FOR UPDATE` filtrando por `local_id` del contexto. Si no existe o es de otro local → `42501`.
3. `PAGADO` o `ANULADO` → `PT409` (“El pedido ya no está pendiente de pago”). Estado distinto de `ENTREGADO` → `PT409` (“El pedido todavía no fue entregado”).
4. Leer la mesa del pedido (sin bloqueo adicional) y exigir `PENDIENTE_PAGO`; si no → `PT409`. Basta el lock del pedido: toda transición de esta mesa fuera de `PENDIENTE_PAGO` (cobro, anulación, reapertura) ocurre con el mismo pedido bloqueado.
5. Buscar la solicitud `PENDIENTE` del pedido. Si existe → devolverla con `ya_existia = true`, sin escribir nada.
6. Insertar `(local_id = pedido.local_id, pedido_id, estado 'PENDIENTE', solicitada_por = auth.uid(), solicitada_en = clock_timestamp())` y devolverla con `ya_existia = false`.
7. Un `23505` sobre `uq_solicitud_cuenta_pedido_pendiente` (imposible bajo el lock, conservado como defensa) se resuelve releyendo y devolviendo la existente; nunca se expone como error ni se convierte en `40001`.

Propiedades: no recibe local, mesa, actor ni hora; no escribe `pedido`, `mesa`, `historial_estado` ni objetos financieros; es idempotente por construcción. `stable` no aplica (escribe). Orden de locks: `pedido → solicitud_cuenta`.

**Hora:** `clock_timestamp()` después de obtener el lock (y no `now()` de inicio de transacción) garantiza que la hora registrada sea posterior a cualquier cambio confirmado antes sobre el pedido (por ejemplo la entrega) y anterior a cualquier cierre posterior, aun si la transacción esperó el lock.

## E10-D05 — Cierre automático sobre la transición del pedido

**Decisión: trigger `AFTER UPDATE OF estado` sobre `pedido`**, no una modificación de las RPC de cobro, reapertura o anulación.

```text
trg_pedido_after_update_cerrar_solicitud_cuenta
  AFTER UPDATE OF estado ON pedido FOR EACH ROW
  WHEN (old.estado = 'ENTREGADO' AND new.estado IS DISTINCT FROM old.estado)
  EXECUTE FUNCTION tgf_pedido_cerrar_solicitud_cuenta()   -- SECURITY DEFINER
```

La función actualiza la única solicitud `PENDIENTE` del pedido (si existe):

| Nuevo estado del pedido | Resultado de la solicitud |
|---|---|
| `PAGADO` | `ATENDIDA` |
| `ANULADO` | `SIN_EFECTO`, `motivo_sin_efecto = 'ANULACION'` |
| Cualquier estado operativo (`ABIERTO`…`LISTO`) | `SIN_EFECTO`, `motivo_sin_efecto = 'REAPERTURA'` |

con `cerrada_en = greatest(clock_timestamp(), solicitada_en)` y `cerrada_por = auth.uid()` (actor `CAJA` del cobro final, `MOZO` de la reapertura o `ADMINISTRADOR` de la anulación).

Justificación:

1. **Una sola regla para todas las vías.** Cubre `rpc_registrar_cobro_pedido`, las vías históricas aún ejecutables (HZ-05), la reapertura vía `sincronizar_estado_operativo_pedido` y la anulación E1, sin editar ninguna.
2. **Atomicidad.** El cierre ocurre dentro de la transacción que cambia el pedido: si el cobro falla, la solicitud sigue pendiente; si confirma, ambos cambios son visibles juntos.
3. **Sin duplicar lógica de pagos.** La condición “saldo = 0” sigue decidida exclusivamente por E1; el trigger sólo observa `ENTREGADO → PAGADO`.
4. **Coste mínimo.** La cláusula `WHEN` limita la ejecución a la salida de `ENTREGADO` (una o pocas veces por pedido).
5. **Precedente.** E7 usa un trigger `AFTER UPDATE OF estado` para su historial de detalle (E7-D11).

Orden de locks resultante: toda vía que cambia un pedido ya tiene bloqueado el pedido (y en su caso sesión y mesa) cuando se ejecuta el trigger, que bloquea la solicitud al final: `[sesion_caja →] pedido → mesa → solicitud_cuenta`. La RPC de solicitud bloquea `pedido → solicitud_cuenta`. No hay ciclos de espera.

`greatest(…)` evita un intervalo negativo ante una corrección del reloj del servidor sin agregar un `CHECK` que pudiera hacer fallar un cobro.

Alternativa descartada: cerrar la solicitud dentro de `rpc_registrar_cobro_pedido`. Obliga a modificar la RPC financiera de E1, no cubre las vías históricas ni la reapertura/anulación y reparte la regla en varios lugares.

## E10-D06 — Inmutabilidad

`trg_solicitud_cuenta_before_update_delete_inmutable` ejecuta `tgf_solicitud_cuenta_inmutable`:

- `DELETE` → rechazado.
- `UPDATE` → sólo si `old.estado = 'PENDIENTE'`, `new.estado ∈ ('ATENDIDA','SIN_EFECTO')` y no cambian `id`, `local_id`, `pedido_id`, `solicitada_por` ni `solicitada_en`.
- `authenticated` sólo recibe `SELECT`; no hay `INSERT/UPDATE/DELETE` directos. `anon`, `public` y `service_role` sin privilegios sobre tabla y secuencia (lección E7-T10: `TRUNCATE` de `service_role` eludiría los triggers).

## E10-D07 — Realtime

**Decisión: publicar `solicitud_cuenta` en `supabase_realtime`** y escucharla como una señal más.

| Alternativa | Evaluación |
|---|---|
| **Publicar `solicitud_cuenta` con RLS (elegida)** | La solicitud y su cierre producen `INSERT`/`UPDATE` propios, entregados sólo a `MOZO`/`CAJA` del local por RLS. Sin importes ni datos financieros (E1-D11 lo admite). La señal de cierre `SIN_EFECTO` llega a Caja incluso cuando la reapertura deja el pedido invisible para ella (mitiga HZ-02 en pedidos con solicitud). |
| Tocar `pedido.modificado_en/por` desde la RPC para emitir `UPDATE` de `pedido` | No cambia la publicación, pero atribuye a la solicitud una “modificación del pedido”, contamina una columna cuya semántica sigue pendiente (HZ-04) y altera el orden `ultima_actualizacion_en` de E1-T17. |
| `UPDATE` sin cambios de `mesa`/`pedido` para forzar un evento | Artificio frágil y no documentable como invariante. |
| Polling | Prohibido. |

Detalle:

- Migración: `alter publication supabase_realtime add table public.solicitud_cuenta` (idempotente, comprobando `pg_publication_tables`). No se quita ni cambia ninguna tabla existente.
- `operationsRealtimeService.subscribeToOperationsChanges` recibe una opción `additionalSignalTables` (por defecto vacía). Mismo canal, mismo topic propio por suscripción (corrección E7-T12 intacta), mismos eventos `INSERT`/`UPDATE`, mismo debounce, coalescencia, segunda carga en `SUBSCRIBED` y resincronización ante error.
- `CashierPage`, `WaiterOrderPage` y `WaiterTablesPage` pasan `['solicitud_cuenta']`; `KitchenBoardPage` no cambia (sigue con seis enlaces).
- Los payloads no se usan como dato: cada evento sólo agenda el refetch autoritativo.

| Operación | Señales |
|---|---|
| Solicitud nueva | `INSERT solicitud_cuenta` → Caja y mozos del local. |
| Solicitud repetida (idempotente) | Ninguna (no escribe). El dispositivo que la pidió muestra el resultado devuelto. |
| Cobro final | `UPDATE solicitud_cuenta` (ATENDIDA) + `UPDATE pedido` (`PAGADO`, visible a Caja) + `UPDATE mesa` (`LIBRE`, visible a mozos). |
| Cobro parcial | Sin cambios en la solicitud; señales E1 vigentes. |
| Reapertura | `UPDATE solicitud_cuenta` (SIN_EFECTO) + señales vigentes de pedido/detalle/mesa para mozos. |
| Anulación ADMIN | `UPDATE solicitud_cuenta` (SIN_EFECTO) + señales vigentes. |

Impacto: un canal por vista como hoy; dos enlaces más en vistas de mozo y caja; como máximo dos eventos por pedido evaluados por RLS por suscriptor, volumen muy inferior al de `detalle_pedido`. Cocina no recibe eventos (sin política).

## E10-D08 — Lecturas autoritativas

### Caja

`obtener_pedidos_pendientes_pago_caja()` se recrea (`DROP` + `CREATE` en la misma transacción, como en E1-T10) conservando nombre, filtros, orden, seguridad y todas sus columnas en el mismo orden, y agrega al final:

| Columna | Origen |
|---|---|
| `solicitud_cuenta_id bigint` | Solicitud `PENDIENTE` del pedido (o nulo). |
| `cuenta_solicitada_en timestamptz` | `solicitada_en`. |
| `cuenta_solicitada_por_nombre text` | Nombre del mozo, resuelto dentro de la función sin ampliar `SELECT` sobre `perfil_usuario` (patrón E1-D11). |
| `servidor_ahora timestamptz` | `now()` para calcular “hace N min” sin depender del reloj del dispositivo (patrón E1-D16). |

Se elige extender la lectura existente en vez de una RPC nueva porque Caja ya la llama en cada refresco: la solicitud y el saldo salen del **mismo snapshot** y no se agrega una llamada por señal (lección E1-T18/E7-D08). La única consumidora es `cashierService.getPendingOrders`; las columnas nuevas son opcionales para ella.

### Mozo

Sin RPC nueva. `getOrderReview` y `getTableBoard` amplían su `select` de `pedido` con el recurso embebido `solicitud_cuenta(id,solicitada_en)` filtrado por `estado = 'PENDIENTE'` (PostgREST, misma petición; RLS aplica en ambos niveles). No agrega viajes de red al tablero del mozo, cuya latencia fue la observación no bloqueante de E1-T18.

## E10-D09 — Seguridad, RLS y privilegios

- `pol_solicitud_cuenta_select_local`: `FOR SELECT TO authenticated USING` existe contexto con `local_id = solicitud_cuenta.local_id` y `rol_codigo ∈ ('MOZO','CAJA')`. Es necesaria para la autorización Realtime y la lectura embebida del mozo. Expone sólo identificadores y timestamps, sin importes.
- Sin políticas de escritura; `GRANT SELECT` a `authenticated`; `REVOKE ALL` a `public`, `anon`, `service_role` sobre tabla y secuencia.
- `rpc_solicitar_cuenta_pedido`: `SECURITY DEFINER`, owner `postgres`, `search_path = pg_catalog`, referencias calificadas, `REVOKE ALL FROM public, anon, service_role`, `GRANT EXECUTE TO authenticated`.
- Funciones de trigger sin `EXECUTE` para ningún rol cliente.
- `obtener_pedidos_pendientes_pago_caja()` conserva sus privilegios y exige `CAJA` como hoy.
- Códigos: `42501` no autorizado/otro local; `22023` entrada inválida; `PT409` conflicto funcional; nunca `40001`.
- No se confía en `local_id`, mesa, actor, hora ni estado enviados por el cliente.

## E10-D10 — ¿Registrar un “comienzo de atención” de Caja?

**Decisión: no.** La métrica objetivo de E8 (“tiempo atribuible al proceso de Caja”) es `solicitada_en → cerrada_en` de la solicitud `ATENDIDA`. Un evento intermedio sólo aportaría la división *espera en cola / duración del cobro*, que no es un objetivo declarado.

| Razón analizada para un botón “Caja toma la solicitud” | Evaluación |
|---|---|
| Evitar que dos cajeros atiendan la misma mesa | E1 ya garantiza un único cobro final por lock y saldo; DF-08 opera una sola caja activa por local; el segundo intento recibe el conflicto vigente. |
| Medir cola vs. atención | No requerido por E8; exigiría un clic extra en cada cobro, se omitiría en la práctica y produciría datos menos fiables que los timestamps automáticos. |
| Cobros parciales largos | La tabla `cobro` ya registra hora y actor de cada acto; E8 puede derivar el primer acto de cobro posterior a la solicitud si en el futuro lo necesita. |

Si E8 llegara a requerir esa división, podrá agregarse de forma aditiva (columna o evento) sin cambiar el modelo de E10. No queda decisión humana pendiente por este punto.

## E10-D11 — Integración con el cobro de E1

- Caja selecciona el pedido como hoy y usa precuenta, descuento autorizado, `Cobrar` o `Cobrar una parte`, N medios y propina sin cambios (`rpc_registrar_cobro_pedido`).
- La solicitud no participa en la validación financiera ni en el orden `sesion_caja → pedido → mesa`; sólo es cerrada por el trigger después del `UPDATE` a `PAGADO`.
- Un cobro parcial no cierra la solicitud y el pedido sigue listado con el indicador.
- Sin solicitud, el cobro funciona igual (DH-01 A, aprobada): no se agrega ninguna validación en las vías de pago y el pedido queda como “sin solicitud registrada”.
- Documentos internos (precuenta, recibo, ticket) no cambian.

## E10-D12 — Concurrencia e idempotencia

Todas las operaciones que afectan una solicitud bloquean primero el pedido.

| Carrera | Resultado |
|---|---|
| Doble clic / reintento tras timeout del mozo | Serializadas por el lock del pedido; la segunda devuelve la existente con `ya_existia = true`. Si la primera no confirmó, el reintento la crea. Además, guard de UI. |
| Dos dispositivos del mismo mozo o dos mozos | Igual: una sola fila `PENDIENTE`, `solicitada_por` = el primero que confirmó. |
| Solicitud vs cobro final | Si la solicitud confirma primero: el cobro espera el lock del pedido y su `UPDATE` a `PAGADO` la deja `ATENDIDA` (`cerrada_en ≥ solicitada_en`). Si el cobro confirma primero: la solicitud ve `PAGADO` → `PT409`; el mozo recarga y vuelve a mesas (comportamiento E7-T12). |
| Solicitud vs cobro parcial | Independientes en efecto; serializadas por el pedido. La solicitud sigue `PENDIENTE`. |
| Solicitud vs reapertura (agregar producto) | Si la reapertura confirma primero: `PT409` (“todavía no fue entregado”). Si la solicitud confirma primero: la reapertura la deja `SIN_EFECTO/REAPERTURA`. |
| Solicitud vs anulación ADMIN | Análogo, con `ANULACION`. |
| Dos cajas sobre el mismo pedido | Ambas ven la solicitud; sólo un cobro final confirma (E1); la otra recibe la señal `PAGADO`, refresca y su intento, si ocurre, recibe el conflicto E1. |
| Pago mientras se procesa la señal Realtime | La señal sólo agenda un refetch coalescido; el snapshot ya no incluye el pedido. Una confirmación abierta se invalida porque el pedido seleccionado desapareció. |
| Señales duplicadas o fuera de orden | Irrelevantes: cada una produce el mismo refetch autoritativo. |

No se introducen `40001`, reintentos automáticos de PostgREST ni esperas activas.

## E10-D13 — UI del mozo

| Vista | Comportamiento |
|---|---|
| `WaiterOrderPage`, pedido `ENTREGADO` sin solicitud | Botón “Solicitar cuenta” junto a “Volver a mesas” (≥ 44 px, ancho completo en celular). Confirmación en línea con el mismo patrón de “Entregar pedido”: “¿Avisar a caja que Mesa X pide la cuenta?”. Guard `useRef` + estado deshabilitado mientras la operación está en curso. |
| Éxito / ya existía | Estado persistente “Cuenta solicitada a caja · hh:mm” (y “ya estaba solicitada” si `ya_existia`); el botón desaparece. |
| `PT409` | Mensaje de conflicto y resincronización; si el pedido dejó de estar vigente vuelve a mesas con el flujo existente `order-not-current`. |
| Pedido `ENTREGADO` con solicitud pendiente | Aviso junto a la carta: “Si agregas productos, la solicitud de cuenta quedará sin efecto y deberás solicitarla otra vez tras entregar”. No bloquea la reapertura H5. |
| `WaiterTablesPage` | Etiqueta “Cuenta solicitada” en la tarjeta de una mesa `PENDIENTE_PAGO` con solicitud pendiente. |
| Tipos | `WaiterOrderReview` y `WaiterTableBoardItem` incorporan `cuentaSolicitadaEn: string \| null`. |

Sin nuevas rutas, sin almacenamiento del navegador y sin estados locales que reemplacen el snapshot.

## E10-D14 — UI de Caja

| Elemento | Comportamiento |
|---|---|
| Lista de pendientes | Pedidos con solicitud pendiente primero, ordenados por `cuenta_solicitada_en` ascendente; luego el orden actual por creación. Etiqueta ámbar “Cuenta solicitada · hace N min” (con `servidor_ahora`), también visible en la barra colapsada junto al código de mesa. |
| Cabecera de la lista | Contador “N cuentas solicitadas” cuando N > 0. |
| Panel del pedido | Línea informativa “Cuenta solicitada por {mozo} a las hh:mm”. Sin botones nuevos: se usa el cobro existente. |
| Aviso | Región `aria-live="polite"` que anuncia “Mesa X pidió la cuenta” sólo para solicitudes nuevas respecto del snapshot anterior. Sin sonido ni notificaciones del sistema. |
| Invalidación del borrador (DH-02 B, aprobada) | `refresh` deja de llamar incondicionalmente a `clearPaymentOptions()`: compara la huella autoritativa del pedido seleccionado (`orderId`, estado, `netTotal`, `discount`, `paid`, `balance`) antes y después; sólo si cambió o desapareció limpia el borrador y muestra el aviso E1 “El saldo o el pedido cambió…”. Refrescos manuales y posteriores a una mutación propia conservan el comportamiento actual. |
| Responsive | Sin columnas nuevas; etiqueta con truncado; sin desplazamiento horizontal en tablet y PC. |

## E10-D15 — Preparación de datos para E8 (sin implementar métricas)

Con E10, E8 dispone de:

| Intervalo | Inicio | Fin | Atribución |
|---|---|---|---|
| Creación → envío | `pedido.creado_en` | `pedido.enviado_en` / `historial_detalle_pedido` `ENVIO` | Mozo |
| Envío → recibido → preparación → listo | `historial_detalle_pedido` (E7) / `historial_estado` | idem | Cocina |
| Listo → entregado | `historial_estado` `→ LISTO` | `historial_estado` `LISTO → ENTREGADO` | Entrega del mozo |
| **Entregado → solicitud** | última transición `→ ENTREGADO` con `creado_en ≤ solicitada_en` | `solicitud_cuenta.solicitada_en` de la solicitud `ATENDIDA` | Cliente (no atribuible a Caja) |
| **Solicitud → pago** | `solicitud_cuenta.solicitada_en` | `solicitud_cuenta.cerrada_en` (`ATENDIDA`); actor en `cerrada_por` | Proceso de Caja |
| Creación → pago | `pedido.creado_en` | `historial_estado` `ENTREGADO → PAGADO` | Total |

Reglas para que E8 no reinterprete datos:

- Cada pedido `PAGADO` tiene como máximo una solicitud `ATENDIDA`; es la única que mide Caja.
- Las solicitudes `SIN_EFECTO` documentan reaperturas/anulaciones y no se usan para el tiempo de Caja.
- Pedido `PAGADO` sin solicitud `ATENDIDA` (anterior a E10, cobro directo en caja): sólo se conoce `ENTREGADO → PAGADO`; E8 debe reportarlo como “sin solicitud registrada”.
- `solicitada_en` y `cerrada_en` usan `clock_timestamp()` y garantizan orden; `historial_estado.creado_en` y `cobro.cobrado_en` usan `now()` de su transacción y pueden diferir en milisegundos del cierre. Para el tiempo de Caja, E8 usa los timestamps propios de la solicitud.
- Las pausas por cobros parciales quedan dentro del tiempo de Caja; si E8 necesitara separarlas, `cobro` conserva cada acto.

E10 no crea vistas, funciones de agregación, tableros ni almacenamiento analítico.

## E10-D16 — Compatibilidad con PM-002, E1 y E7

- **PM-002 `TRANSITIONING`:** el proyecto actual es DEV y a la vez sirve Production hasta el cutover. Todas las migraciones de E10 son aditivas y compatibles hacia atrás con el frontend ya desplegado: la tabla nueva no afecta pantallas antiguas; `obtener_pedidos_pendientes_pago_caja` conserva sus columnas y el `DROP/CREATE` es atómico; la publicación agrega una tabla que el frontend antiguo no escucha. `mikuyapp-prod` no se toca. La próxima revalidación de PM-002 deberá esperar cuatro tablas publicadas (HZ-03); este spec no modifica PM-002.
- **E1:** sin cambios en RPC financieras, auditoría, reportes ni documentos. Sólo se extiende la lectura de pendientes y la regla de invalidación del borrador en la UI (DH-02 B).
- **E7:** la corrección de Realtime (topic único) se conserva; el trigger nuevo sobre `pedido` no interfiere con los triggers de detalle; las RPC de mozo/cocina no cambian.

## E10-D17 — Migración prevista (construcción futura)

Una migración nueva y aditiva, posterior a `20260924000800`, sin editar migraciones históricas:

`…_e10_t02_solicitud_cuenta.sql`: tabla, restricciones, índices, comentarios, RLS y privilegios (incluida la revocación a `service_role`); triggers de inmutabilidad y de cierre; `rpc_solicitar_cuenta_pedido`; recreación extendida de `obtener_pedidos_pendientes_pago_caja`; alta en la publicación; `notify pgrst, 'reload schema'`. Se aplica primero en local y luego en DEV, conforme a PM-002. Si la construcción prefiere separar la RPC/lectura en una segunda migración, se documenta en la evidencia de T03.

## E10-D18 — Estrategia de validación

Igual que E7: cada tarea ejecuta sólo sus verificaciones focalizadas; la suite completa, la regresión H3–E7, el replay limpio, las pruebas SQL integrales, seguridad, Realtime, `typecheck` y `build` se ejecutan una vez en la fase final E10-T07. Las pruebas históricas superadas (`h4_t05` publicación exacta, `h5_t03`/`e1_t10` firma de la lectura de caja, conteo de enlaces en `waiterRealtime`) se homologan con pruebas E10 equivalentes, sin editar la evidencia histórica.

## Riesgos de diseño

| Riesgo | Mitigación |
|---|---|
| Solicitud duplicada por doble clic, reintento o dos dispositivos | Lock del pedido + única pendiente por pedido + guard de UI. |
| Solicitud pendiente que nunca se cierra | Cierre por trigger en toda salida de `ENTREGADO`; sin otra ruta de salida posible. |
| Carrera entre solicitud y cobro/reapertura/anulación | Serialización por pedido; orden único de locks; `PT409` sin efectos. |
| Intervalo de Caja negativo o incoherente | `clock_timestamp()` tras el lock y `greatest(…)` en el cierre. |
| Borrador de cobro descartado por solicitudes de otras mesas | Invalidación acotada al pedido seleccionado (DH-02 B, E10-R22). |
| Mayor carga Realtime | Tabla de bajo volumen, mismo canal, mismo debounce; cocina sin cambios. |
| Pruebas históricas que fijan la publicación o firmas | Homologación documentada en la fase final. |
| Solicitud por error del mozo | Sin anulación manual (fuera de alcance); queda `ATENDIDA` al cobrar o `SIN_EFECTO` al reabrir; E8 puede identificar atenciones anómalas por su duración. |
