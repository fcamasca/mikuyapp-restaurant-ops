# MikuyApp — Evolución 10 — Solicitud de cuenta y atención en caja: plan de pruebas

**Estado: PLAN APROBADO (30/09/2026)**, con DH-01 A y DH-02 B aprobadas. Verificaciones focalizadas T02–T06 y fase final T07 ejecutadas: **TP01–TP21 técnicamente completadas** (`implementation.md` §8.3 y §10; en TP20 la suite histórica reproduce la línea base, sin regresión). **TH01–TH07 (E10-T08) no iniciadas.**

## 1. Estrategia

Se mantiene el modelo aprobado en E7:

1. **Construcción (E10-T02–E10-T06):** cada tarea ejecuta **sólo** las verificaciones focalizadas de la sección 2.
2. **Fase final (E10-T07):** se ejecuta **una vez** todo este plan: SQL integral, concurrencia, seguridad/RLS, Realtime, suite Node completa, regresión H3/H4/H5/H6/E1/E7, replay limpio de migraciones, `typecheck` y `build`. Después, E10-T08 ejecuta las pruebas humanas.

Reglas:

- Si se modifica una RPC, trigger o lectura, se ejecutan sus pruebas SQL específicas.
- Si se crea o modifica una migración, se valida que aplica sobre la baseline local vigente (sin replay completo).
- Si se modifica un componente o servicio frontend, se ejecuta sólo su prueba Node focalizada (`node --experimental-strip-types --test tests/<archivo>.test.mjs`).
- Un cambio sólo SQL no obliga a `typecheck`/`build`; un cambio sólo UI no obliga a repetir SQL.
- Defectos bloqueantes se corrigen dentro de la tarea; no bloqueantes se registran y se resuelven antes de T07.
- E10 no puede cerrarse con pruebas pendientes y las pruebas automatizadas no sustituyen la validación humana.

### Ambientes y datos

- Local aislado con la baseline vigente (hasta `20260924000800`) y `supabase/seed.sql`; luego DEV/Preview conforme a PM-002 `TRANSITIONING`. Nunca `mikuyapp-prod`.
- Fixtures SQL en transacción con `ROLLBACK` o limpieza verificable, siguiendo el patrón `set_config('request.jwt.claim.sub', …)` de `supabase/tests/`.
- Usuarios activos `ADMINISTRADOR`, dos `MOZO`, `COCINA`, dos sesiones `CAJA` en el local A, y un `MOZO`/`CAJA` en el local B.
- Pedidos de prueba: entregado sin pagos; entregado con cobro parcial; entregado con descuento autorizado; reabierto; pagado; anulado.
- Carreras con conexiones independientes, siguiendo los scripts `*_concurrency_setup/call/verify/cleanup.sql` existentes.
- Realtime con al menos dos clientes reales (mozo y caja) y, donde se indica, una segunda caja y un segundo dispositivo del mozo.

## 2. Verificaciones focalizadas por tarea (construcción)

| Tarea | Verificación focalizada mínima | No requerido en la tarea |
|---|---|---|
| E10-T02 | Migración aplica sobre la baseline local; TP01 (catálogo de objetos, privilegios, publicación); partes SQL de TP06–TP09 con fixtures que cambian el estado del pedido directamente como `postgres` (cierre por trigger e inmutabilidad). | Replay completo, Node, build. |
| E10-T03 | SQL de la RPC y de la lectura: TP02–TP04, TP12, parte SQL de TP14; carreras reales TP05 (solicitud vs solicitud) y TP10 (solicitud vs cobro final). | UI, regresión E1 completa. |
| E10-T04 | `tests/waiterBoard.test.mjs`, `tests/waiterRealtime.test.mjs`, `tests/kitchenRealtimeService.test.mjs` (cocina conserva 6 enlaces); TP13 y TP17. | SQL, build. |
| E10-T05 | `tests/cashierService.test.mjs`, `tests/cashierPage.test.mjs`, `tests/cashierPrint.test.mjs`; TP18. | SQL, suite completa. |
| E10-T06 | Recorrido local → DEV de TP15 y TP19 con dos dispositivos; replay de la migración E10 sobre la baseline; confirmación de HZ-02. | Matriz completa (queda para T07). |

## 3. Escenarios técnicos finales (E10-T07)

### 3.1 Modelo

| ID | Requisitos | Escenario | Validaciones |
|---|---|---|---|
| E10-TP01 | R03, R12, R15, R16 | Estructura y catálogo. | Tabla, columnas, `ck_solicitud_cuenta_estado_valido`, `ck_solicitud_cuenta_cierre_coherente`, FKs `RESTRICT`, `uq_solicitud_cuenta_pedido_pendiente` parcial, índice por pedido, comentarios; RLS habilitado y sólo `pol_solicitud_cuenta_select_local`; `authenticated` sólo `SELECT`; `public/anon/service_role` sin privilegios en tabla y secuencia; triggers presentes con su `WHEN`; publicación = `detalle_pedido`, `mesa`, `pedido`, `solicitud_cuenta`. |

### 3.2 Solicitud

| ID | Requisitos | Escenario | Validaciones |
|---|---|---|---|
| E10-TP02 | R01–R03 | Solicitud válida. | Pedido `ENTREGADO`/`PENDIENTE_PAGO` sin pagos y otro con cobro parcial: fila `PENDIENTE` con `local_id` y `pedido_id` correctos, `solicitada_por = auth.uid()`, `solicitada_en` de servidor posterior a la transición `→ ENTREGADO`, `ya_existia = false`; `pedido`, `mesa`, `historial_estado`, `cobro`, `pago`, `descuento_pedido` y `auditoria_caja` sin cambios; mesa derivable por `pedido.mesa_id`. |
| E10-TP03 | R01, R05, R15 | Matriz de rechazos. | `ABIERTO`, `ENVIADO`, `RECIBIDO_COCINA`, `EN_PREPARACION`, `LISTO`, reabierto → `PT409`; `PAGADO`, `ANULADO` → `PT409`; `p_pedido_id` nulo → `22023`; otro local, `COCINA`, `CAJA`, `ADMINISTRADOR`, sin sesión → `42501`; sin filas nuevas en todos los casos; ningún `40001`. |
| E10-TP04 | R04 | Idempotencia. | Segunda llamada del mismo mozo y llamada de otro mozo del local → misma `solicitud_id`, misma hora y autor, `ya_existia = true`, sin filas ni eventos nuevos. |
| E10-TP05 | R04, R17 | Solicitud vs solicitud (conexiones reales). | Dos sesiones `MOZO` simultáneas sobre el mismo pedido: exactamente una fila `PENDIENTE`; una respuesta `ya_existia = false` y otra `true`; sin `23505` expuesto ni conexiones residuales. |

### 3.3 Cierre y ciclo de vida

| ID | Requisitos | Escenario | Validaciones |
|---|---|---|---|
| E10-TP06 | R02, R07–R09, R14 | Cierre por cobro. | Cobro `TOTAL` con N medios deja `ATENDIDA`, `cerrada_por` = cajero, `cerrada_en ≥ solicitada_en`, en la misma transacción que `PAGADO`/`LIBRE`; cobro `PARCIAL` deja `PENDIENTE`; parcial + total → `ATENDIDA` una vez; con descuento autorizado el neto E1 no cambia; cobro sin solicitud funciona igual que hoy (DH-01) y no crea filas; un pedido pagado por cada vía histórica aún ejecutable (`registrar_pago_pedido`, `rpc_registrar_pago_total_pedido`, `rpc_registrar_pago_pedido_v2`) también cierra la solicitud; un cobro que falla (suma inválida, sesión cerrada) deja la solicitud `PENDIENTE`. |
| E10-TP07 | R10 | Reapertura. | Agregar producto a un pedido `ENTREGADO` con solicitud: `SIN_EFECTO/REAPERTURA`, `cerrada_por` = mozo, en la misma transacción; retiro del producto nuevo (E7 HZ-01) deja el pedido `LISTO` sin reactivar la solicitud; nueva entrega → nueva solicitud permitida; el pedido conserva ambas filas; tras el primer cobro parcial la reapertura sigue bloqueada por E1-R16 y la solicitud no cambia. |
| E10-TP08 | R11 | Anulación. | `anular_pedido_supervisado` sobre un pedido `ENTREGADO` con solicitud: `SIN_EFECTO/ANULACION`, `cerrada_por` = administrador; mesa `LIBRE`; anulación de un pedido sin solicitud no crea filas. |
| E10-TP09 | R12 | Inmutabilidad. | `INSERT/UPDATE/DELETE` directos de `authenticated` rechazados; `TRUNCATE` de `service_role` rechazado; como owner, el trigger rechaza `DELETE`, cambios de `pedido_id/solicitada_*`, reapertura `ATENDIDA → PENDIENTE` y un segundo cierre. |
| E10-TP10 | R05, R09, R17 | Solicitud vs cobro final (conexiones reales). | En ambos órdenes: si gana la solicitud, el cobro la deja `ATENDIDA`; si gana el cobro, la solicitud recibe `PT409` y no hay filas; sin interbloqueo (`40P01`), sin estados parciales. |
| E10-TP11 | R05, R10, R11, R17 | Otras carreras (conexiones reales). | Solicitud vs reapertura y solicitud vs anulación en ambos órdenes: `PT409` o `SIN_EFECTO` según el orden; dos cajas cobrando total el mismo pedido con solicitud: un solo cobro final, una sola `ATENDIDA`, la otra caja recibe el conflicto E1; sin `40P01` ni `40001`. |

### 3.4 Lecturas

| ID | Requisitos | Escenario | Validaciones |
|---|---|---|---|
| E10-TP12 | R06, R15 | Lectura de Caja extendida. | Columnas H5/E1 previas idénticas en nombre, tipo, orden y valores; nuevas columnas con la solicitud `PENDIENTE` (nulas sin solicitud; nunca muestran `ATENDIDA` o `SIN_EFECTO`); nombre del mozo; `servidor_ahora`; `SECURITY DEFINER`, `search_path`, privilegios y comentario restaurados; otros roles y locales → `42501`. |
| E10-TP13 | R18, R15 | Lectura del mozo embebida. | `getOrderReview` y `getTableBoard` devuelven `cuentaSolicitadaEn` sólo para la pendiente del local; cerradas no aparecen; un `MOZO` de otro local no ve filas; una sola petición por tablero (sin viajes adicionales). |

### 3.5 Seguridad

| ID | Requisitos | Escenario | Validaciones |
|---|---|---|---|
| E10-TP14 | R12, R15 | Matriz rol × operación y catálogo. | `MOZO` crea y lee; `CAJA` lee (tabla y lectura extendida) y no crea; `COCINA`, `ADMINISTRADOR` y `anon` no leen ni crean; otro local sin datos; RPC y triggers con `SECURITY DEFINER`, owner `postgres`, `search_path = pg_catalog`; `EXECUTE` de la RPC sólo `authenticated`; funciones de trigger sin `EXECUTE` cliente; ninguna aparición manual de `40001` en funciones/triggers vigentes. |

### 3.6 Realtime

| ID | Requisitos | Escenario | Validaciones |
|---|---|---|---|
| E10-TP15 | R06, R16 | Mozo ↔ caja (clientes reales). | La solicitud del mozo aparece en Caja sin refresco manual (registrar latencia); el cobro final la retira en Caja y deja la mesa `LIBRE` para el mozo; la reapertura la retira de Caja por la señal `SIN_EFECTO`; segundo dispositivo del mozo muestra “Cuenta solicitada”; segunda caja ve la solicitud y su retiro; `COCINA` no recibe eventos de `solicitud_cuenta`. |
| E10-TP16 | R16 | Robustez. | Eventos duplicados o desordenados no duplican tarjetas ni contadores; pérdida de red y reconexión resincronizan al snapshot; desmontaje/remontaje rápido (StrictMode, `SIGNED_IN`) conserva la suscripción con topic único (regresión E7-T12); cocina mantiene 6 enlaces; sin polling (sin temporizadores periódicos de recarga). |

### 3.7 Interfaz

| ID | Requisitos | Escenario | Validaciones |
|---|---|---|---|
| E10-TP17 | R01, R04, R18, R20 | UI del mozo (Node). | Botón sólo en `ENTREGADO`; confirmación; guard ante doble toque (una sola llamada); estados “Cuenta solicitada · hh:mm” y “ya estaba solicitada”; `PT409` → resync y, si no vigente, vuelta a mesas; aviso de reapertura con solicitud pendiente; etiqueta en la tarjeta de mesa; objetivos ≥ 44 px. |
| E10-TP18 | R06, R19, R20, R22 | UI de Caja (Node). | Orden: solicitudes primero por antigüedad y luego el orden E1; etiqueta con tiempo desde `servidor_ahora`; contador; línea en el panel; `aria-live` sólo para solicitudes nuevas; ninguna acción nueva de cobro; **DH-02 B (aprobada):** una señal que agrega o cierra la solicitud de otro pedido conserva medios, importes y confirmación del pedido seleccionado; un cambio de saldo, estado o la desaparición del seleccionado los invalida con el aviso E1. |

### 3.8 Datos para E8

| ID | Requisitos | Escenario | Validaciones |
|---|---|---|---|
| E10-TP19 | R03, R09, R13, R14 | Recorrido completo con timestamps. | Consulta SQL de verificación (no persistida) sobre un pedido real: `creado_en ≤ enviado_en ≤ … ≤ LISTO → ENTREGADO ≤ solicitada_en ≤ cerrada_en`, con `cerrada_en` en la transacción de `ENTREGADO → PAGADO`; exactamente una `ATENDIDA` por pedido pagado con solicitud; un pedido reabierto muestra `SIN_EFECTO` previa y `ATENDIDA` posterior a la segunda entrega; un pedido pagado sin solicitud es identificable. Se derivan los intervalos de `design.md` E10-D15 sin reglas adicionales. |

### 3.9 Regresión y validación integral

| ID | Requisitos | Escenario | Validaciones |
|---|---|---|---|
| E10-TP20 | R07, R21 | Regresión H3–E7. | Suites SQL `h3_*`, `h4_*`, `h5_*`, `h6_*`, `e1_*`, `e7_*`, `order_audit_trail`, `release_empty_order_table` y pruebas Node de mozo, cocina, caja, impresión, Inicio y Pedidos ADMIN aprobadas sin editar evidencia histórica. Homologaciones documentadas: `h4_t05` (publicación exacta de tres tablas) cubierta por TP01; `h5_t03`/`e1_t10` (firma de `obtener_pedidos_pendientes_pago_caja`) cubiertas por TP12; conteo de enlaces del mozo en `waiterRealtime` cubierto por TP16. |
| E10-TP21 | Todos | Ejecución integral. | Replay limpio de todas las migraciones + seed; todos los SQL de `supabase/tests/` y de E10; suite Node completa; `npm run typecheck`; `npm run build` (limitaciones ambientales documentadas como en E1-TP65/E7); sin conexiones residuales. |

## 4. Pruebas humanas (E10-T08, después de T07)

| ID | Caso | Dispositivos | Resultado esperado |
|---|---|---|---|
| E10-TH01 | Mozo solicita la cuenta de una mesa entregada; Caja la ve sin refrescar y cobra total. | Celular (mozo) + PC (caja) | Aviso visible en Caja en pocos segundos; cobro E1 sin cambios; mesa `LIBRE`; la solicitud desaparece en ambos. |
| E10-TH02 | Doble toque, segundo celular del mismo mozo y otro mozo sobre la misma mesa. | Dos celulares + PC | Una sola solicitud; ambos celulares muestran “Cuenta solicitada” con la misma hora. |
| E10-TH03 | Solicitud seguida de cobro parcial y luego total, con descuento autorizado. | Celular + PC | La solicitud sigue visible tras el parcial y se cierra con el total; documentos E1 idénticos. |
| E10-TH04 | Reapertura tras la solicitud: agregar un producto. | Celular + PC | Aviso previo en el celular; la solicitud desaparece de Caja; tras la nueva entrega se puede solicitar otra vez. |
| E10-TH05 | Caja cobra la mesa A mientras la mesa B pide la cuenta. | Celular + PC | Aviso de B visible; el borrador de cobro de A se conserva (DH-02 B, aprobada). |
| E10-TH06 | Cliente paga directamente en caja sin solicitud. | PC | Cobro idéntico al actual. |
| E10-TH07 | Uso táctil y responsive. | Celular, tablet vertical/horizontal, PC | Objetivos ≥ 44 px; sin desplazamiento horizontal; etiquetas legibles. |

## 5. Criterios de salida

- TP01–TP21 aprobados y TH01–TH07 aprobadas humanamente.
- Ningún defecto bloqueante abierto; defectos no bloqueantes resueltos o aceptados explícitamente por el responsable.
- Evidencia registrada por tarea y de la fase final, incluida la confirmación de HZ-02.
- Sólo después: elaboración y aprobación de `acceptance.md`.
