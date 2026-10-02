# MikuyApp — Evolución 9 — Jornada operativa del local: plan de pruebas

**Estado de E9: CERRADA, VALIDADA Y ACEPTADA (01/10/2026).** Incorpora DC-10, DC-11 y DC-12; no quedan decisiones humanas pendientes. Evidencia técnica aprobada en [implementation.md](implementation.md). Aceptación humana: seis pruebas ejecutadas/aprobadas y TH02/TH07 no ejecutadas, aceptadas por dispensa explícita; [acceptance.md](acceptance.md).

## 1. Estrategia

Se mantiene el modelo aprobado en E7 y E10:

1. **Construcción (E9-T02–E9-T06):** cada tarea ejecuta **sólo** las verificaciones focalizadas de la sección 2.
2. **Fase final (E9-T07):** se ejecuta **una vez** todo este plan: SQL integral, matriz de operaciones con local cerrado, concurrencia, seguridad/RLS, Realtime, suite Node completa, regresión H3/H4/H5/H6/E1/E7/E10 con los tests vigentes homologados en el repositorio, replay limpio de migraciones, `typecheck` y `build`. Después, E9-T08 ejecuta las pruebas humanas, únicas que usan dispositivos físicos.

Reglas:

- Si se modifica una RPC, trigger o lectura, se ejecutan sus pruebas SQL específicas.
- Si se crea o modifica una migración, se valida que aplica sobre la baseline local vigente (sin replay completo).
- Si se modifica un componente o servicio frontend, se ejecuta sólo su prueba Node focalizada (`node --experimental-strip-types --test tests/<archivo>.test.mjs`).
- Un cambio sólo SQL no obliga a `typecheck`/`build`; un cambio sólo UI no obliga a repetir SQL.
- Las suites E9 incluyen desde el inicio su precondición de jornada. Los tests vigentes que crean `pedido` o `sesion_caja` directamente se homologan mínimamente en el repositorio en T07, antes de la regresión (`design.md` E9-D16), sin mecanismos de base de datos exclusivos para tests, sin tests duplicados y sin editar evidencia histórica de aceptación.
- Ningún fallo se acepta por haber existido antes: un fallo que se sostenga ajeno a E9 se demuestra contra la baseline anterior a E9, se documenta individualmente y se informa al responsable antes de finalizar T07.
- No se duplican pruebas equivalentes: cada comportamiento se verifica en un único escenario TP o TH.
- Defectos bloqueantes se corrigen dentro de la tarea; no bloqueantes se registran y se resuelven antes de T07.
- Ningún escenario debe producir `40001` ni `40P01`.

### Ambientes y datos

- Local aislado con la baseline vigente (hasta `20260930000200`) y `supabase/seed.sql`, usando la emulación de plataforma de E10 (`scripts/e10_local_platform.sql`, `scripts/e10_local_replay.sh`); las pruebas humanas usan un ambiente remoto sin filas en `pedido`/`sesion_caja`, preparado mediante una acción separada y autorizada por el responsable (DC-12). Nunca `mikuyapp-prod`.
- Fixtures SQL en transacción con `ROLLBACK` o limpieza verificable, con el patrón `set_config('request.jwt.claim.sub', …)` de `supabase/tests/`.
- Usuarios activos en el local A: dos `ADMINISTRADOR`, dos `MOZO`, `COCINA`, dos `CAJA`; en el local B: un `ADMINISTRADOR`, un `MOZO`, un `CAJA`; un perfil inactivo.
- Escenarios de jornada: local sin jornadas; jornada abierta; jornada cerrada; dos jornadas en la misma fecha; jornada con `abierta_en` el día anterior a las 21:00 (fixture como `postgres`, coherente con `ck_jornada_operativa_fecha_operativa`) para simular el cruce de medianoche.
- Pedidos de prueba en cada estado: `ABIERTO` vacío, `ABIERTO` con detalles, `ENVIADO`, `RECIBIDO_COCINA`, `EN_PREPARACION`, `LISTO`, `ENTREGADO` sin pagos, `ENTREGADO` con cobro parcial, `ENTREGADO` con solicitud de cuenta y con descuento pendiente, `PAGADO`, `ANULADO`.
- Carreras con conexiones independientes, siguiendo los scripts `*_concurrency_setup/call/verify/cleanup.sql` y el patrón `race` de `scripts/e10_local_sql_suite.sh`.
- Realtime técnico (T04–T07) con clientes Realtime programáticos autenticados por rol (ADMIN, mozo, cocina, caja y un segundo ADMIN), como en la verificación de E10; los dispositivos físicos se reservan para TH01–TH08.

## 2. Verificaciones focalizadas por tarea (construcción)

| Tarea | Verificación focalizada mínima | No requerido en la tarea |
|---|---|---|
| E9-T02 | Migración aplica sobre la baseline local; TP01; TP02 (precondición); TP06 y TP07 con fixtures directas (jornada insertada como `postgres`); TP09 (coherencia de cobro). | RPC E9, replay completo, Node, build. |
| E9-T03 | SQL de las RPC y lecturas: TP03–TP05, TP10–TP12, TP14, TP15; carreras reales TP16 (apertura vs apertura) y TP17 (cierre vs creación, ambos órdenes). | UI, regresión completa. |
| E9-T04 | Pruebas Node nuevas del gate y del servicio; `tests/appRoutes.test.mjs`, `tests/waiterBoard.test.mjs`, `tests/cashierPage.test.mjs`, `tests/kitchenRealtimeService.test.mjs` (cocina conserva sus enlaces); TP19 y la parte Node de TP21. | SQL, build. |
| E9-T05 | `tests/adminHome.test.mjs`, `tests/appRoutes.test.mjs`, prueba Node nueva del historial; TP20. | SQL, suite completa. |
| E9-T06 | TP22 y TP23 en local con clientes programáticos; replay de las migraciones E9 sobre la baseline. | Dispositivos físicos (T08); homologación y regresión histórica (T07); matriz completa (T07). |

## 3. Escenarios técnicos finales (E9-T07)

### 3.1 Modelo y migración

| ID | Requisitos | Escenario | Validaciones |
|---|---|---|---|
| E9-TP01 | R02, R19, R21, R27, R29 | Estructura y catálogo. | Tabla, columnas y tipos; `ck_jornada_operativa_estado_valido`, `ck_jornada_operativa_numero_positivo`, `ck_jornada_operativa_cierre_coherente`, `ck_jornada_operativa_fecha_operativa`; FKs `RESTRICT`; `uq_jornada_operativa_local_abierta` parcial, `uq_jornada_operativa_local_fecha_numero`, `uq_jornada_operativa_idempotencia`, `uq_jornada_operativa_id_local_id`, índice de historial; comentarios. `pedido.jornada_operativa_id` y `sesion_caja.jornada_operativa_id` `NOT NULL` con FK compuesta e índice `(jornada_operativa_id, estado)`. Ninguna otra tabla recibe `jornada_operativa_id` (R19). RLS habilitado con sólo `pol_jornada_operativa_select_local`; `authenticated` sólo `SELECT`; `public/anon/service_role` sin privilegios en tabla y secuencia. Triggers presentes (asignación en `pedido` y `sesion_caja`, coherencia en `pago`, inmutabilidad) con funciones `SECURITY DEFINER`, owner `postgres`, `search_path = pg_catalog`, sin `EXECUTE` cliente. Publicación = `detalle_pedido`, `jornada_operativa`, `mesa`, `pedido`, `solicitud_cuenta`. |
| E9-TP02 | R14, R17, DC-12 | Precondición de la migración. | Sobre una base con al menos una fila en `pedido` o en `sesion_caja`, la migración aborta con el mensaje explícito y no deja objetos parciales; sobre la baseline vacía, aplica. No se crean jornadas ni se modifican filas existentes. |

### 3.2 Apertura

| ID | Requisitos | Escenario | Validaciones |
|---|---|---|---|
| E9-TP03 | R01, R03, R04 | Apertura válida y rechazos. | ADMIN del local A sin jornada abierta: fila `ABIERTA` con `local_id` del contexto, `abierta_por = auth.uid()`, `abierta_en` de servidor, `fecha_operativa` = fecha Lima de `abierta_en`, `numero = 1`, `ya_existia = false`. `MOZO`, `COCINA`, `CAJA`, perfil inactivo, sin sesión → `42501`; clave nula → `22023`; sin filas nuevas en los rechazos; ningún `40001`. |
| E9-TP04 | R02, R05 | Idempotencia de apertura. | Misma clave → misma jornada, `ya_existia = true`, sin filas nuevas; otra clave u otro ADMIN con jornada abierta → la abierta, `ya_existia = true`; misma clave tras cerrar la jornada → devuelve la jornada `CERRADA` y no abre otra; otra clave tras cerrar → nueva jornada. |
| E9-TP05 | R04, R07, R08 | Fecha operativa, correlativo y medianoche. | Abrir, cerrar y volver a abrir el mismo día → `numero` 1, 2, 3 con la misma fecha; el local B numera de forma independiente. Jornada fixture abierta el día anterior a las 21:00: sigue `ABIERTA`, los pedidos y sesiones creados “hoy” se asignan a ella, su identificación conserva la fecha anterior, puede cerrarse hoy con `cerrada_en > abierta_en`; la siguiente apertura de hoy recibe `numero = 1` de la fecha de hoy. Ningún proceso cierra jornadas por tiempo. |

### 3.3 Asociación y rechazo con local cerrado

| ID | Requisitos | Escenario | Validaciones |
|---|---|---|---|
| E9-TP06 | R11, R14, R15, R17 | Creación con y sin jornada. | Con jornada abierta: `crear_o_recuperar_pedido_mesa`, `h3_abrir_o_recuperar_pedido` y `rpc_abrir_sesion_caja` asignan la jornada abierta. Sin jornada: las tres → `PT409` “Local cerrado — el sistema no se encuentra aperturado”, sin `pedido`, `historial_estado`, cambio de mesa, `sesion_caja`, `solicitud_apertura_caja`, `auditoria_caja` ni notificaciones residuales. Un `INSERT` directo como `postgres` sin jornada abierta también se rechaza. La recuperación idempotente de una sesión ya abierta (E1-R02) sigue funcionando. |
| E9-TP07 | R14, R16, R17 | Asignación por servidor e inmutabilidad. | `INSERT` con `jornada_operativa_id` distinto de la abierta → `42501`; igual → aceptado; `UPDATE` de `jornada_operativa_id` en `pedido` o `sesion_caja` (incluso como owner) → `23514`; transiciones normales del pedido (reapertura H5, cobro, anulación) no alteran la jornada. |
| E9-TP08 | R11, R13, R15, DC-10 | Matriz de operaciones con local cerrado. | Con el local cerrado y datos terminales de una jornada anterior, cada función de la tabla de `design.md` E9-D05 (y las políticas de escritura directa de `detalle_pedido`) se rechaza sin efectos con su conflicto vigente; se verifica además que ninguna de esas funciones fue modificada por E9 (definición idéntica a la de la baseline anterior a E9). En la misma condición, `ADMINISTRADOR` ejecuta sin cambios las funciones no operativas: lecturas de carta/mesas y su administración, reportes de ventas y caja, auditoría, notificaciones, historial de jornadas y apertura. |
| E9-TP09 | R18 | Coherencia pedido / sesión en el cobro. | Fixture que deshabilita temporalmente el trigger de asignación dentro de una transacción con `ROLLBACK` para fabricar un pedido y una sesión de jornadas distintas: `rpc_registrar_cobro_pedido`, `registrar_pago_pedido`, `rpc_registrar_pago_total_pedido` y `rpc_registrar_pago_pedido_v2` → `PT409`, sin `cobro`, `pago`, auditoría ni cambio de estado. **DV-01 aprobada:** `pago` sin `sesion_caja_id` conserva las reglas E1 vigentes; E9 no agrega una prohibición de nulos. Con pedido y sesión de la misma jornada, los cuatro cobros funcionan como hoy. |

### 3.4 Cierre

| ID | Requisitos | Escenario | Validaciones |
|---|---|---|---|
| E9-TP10 | R20, R21, R23, R24 | Cierre y sus rechazos. | Jornada sin pedidos, o con todos `PAGADO`/`ANULADO`, y sin sesiones abiertas → `CERRADA`, `cerrada_por = auth.uid()`, `cerrada_en ≥ abierta_en`, `ya_estaba_cerrada = false`. Rechazo `PT409` con conteos correctos y sin efectos ante cada bloqueo por separado: pedido `ABIERTO` vacío, cada estado `ENVIADO`…`ENTREGADO`, `ENTREGADO` con cobro parcial, con solicitud de cuenta pendiente y con descuento pendiente, sesión de caja abierta. Repetir el cierre de una cerrada → `ya_estaba_cerrada = true`, mismo actor y hora. Jornada de otro local, inexistente o id nulo → `42501`/`22023`. Roles no ADMIN → `42501`. Tras resolver los pendientes con operaciones vigentes (cobro total, anulación, liberación de mesa vacía, cierre de caja normal o supervisor) el cierre procede. |
| E9-TP11 | R22 | Pendientes de cierre. | La lectura devuelve exactamente los pedidos no terminales (mesa, pedido, estado, creación) y las sesiones abiertas (caja, quién abrió, desde cuándo) de la jornada abierta; sin importes; vacía con local cerrado o sin pendientes; roles no ADMIN → `42501`; otro local sin filas. |

### 3.5 Lecturas, inmutabilidad, seguridad y trazabilidad

| ID | Requisitos | Escenario | Validaciones |
|---|---|---|---|
| E9-TP12 | R06, R25 | Estado actual e historial. | `rpc_obtener_jornada_operativa_actual`: cero filas con local cerrado; con local abierto una fila con identificación `Jornada YYYY-MM-DD (N)`, nombre del administrador y `servidor_ahora`, para los cuatro roles del local; otro local sin filas; `anon` sin ejecución. Historial: orden descendente, paginación válida e inválida (`22023`), identificación, apertura y cierre con nombres; sin totales ni conteos; roles no ADMIN → `42501`. |
| E9-TP13 | R21, R27 | Inmutabilidad de la jornada. | `INSERT/UPDATE/DELETE` directos de `authenticated` rechazados; `TRUNCATE` de `service_role` rechazado; como owner, el trigger rechaza `DELETE`, `CERRADA → ABIERTA`, cambios de `local_id`, `fecha_operativa`, `numero`, `abierta_*`, `idempotency_key` y un segundo cierre. |
| E9-TP14 | R01, R27 | Matriz rol × operación y catálogo. | ADMIN abre, cierra y lee todo; MOZO/COCINA/CAJA sólo ejecutan la lectura del estado actual y leen por RLS las filas de jornada de su local (sin nombres ni importes), no las RPC de pendientes ni de historial; `anon` nada; otro local sin datos; RPC con `SECURITY DEFINER`, owner `postgres`, `search_path = pg_catalog`, `EXECUTE` sólo `authenticated`; funciones de trigger e internas sin `EXECUTE` cliente; ninguna aparición manual de `40001` en funciones y triggers vigentes. |
| E9-TP15 | R26 | Trazabilidad reconstruible. | Consulta SQL de verificación (no persistida) sobre un recorrido completo: todo pedido, detalle, historial, comanda, solicitud de cuenta, descuento, cobro, pago, movimiento y resumen de cierre de la jornada se alcanza por `pedido.jornada_operativa_id` o `sesion_caja.jornada_operativa_id`; apertura y cierre de la jornada con actor y hora; I-2, I-3 e I-4 se cumplen en toda la base. |

### 3.6 Concurrencia (conexiones reales)

| ID | Requisitos | Escenario | Validaciones |
|---|---|---|---|
| E9-TP16 | R02, R05, R28 | Apertura vs apertura. | Dos ADMIN simultáneos (claves distintas) y doble envío con la misma clave: exactamente una jornada `ABIERTA`; un `ya_existia = false` y el resto `true`; numeración sin saltos; sin `23505` expuesto ni conexiones residuales. |
| E9-TP17 | R20, R23, R28 | Cierre vs creación y cierre vs cierre. | Cierre vs `crear_o_recuperar_pedido_mesa` y cierre vs `rpc_abrir_sesion_caja`, en ambos órdenes: si gana la creación, el cierre recibe `PT409` y la jornada sigue abierta con el pedido/sesión asignado; si gana el cierre, la creación recibe `PT409` “Local cerrado” sin residuos. Dos cierres simultáneos: uno cierra y el otro devuelve `ya_estaba_cerrada = true`. En ningún caso queda una jornada `CERRADA` con pedidos no terminales o sesiones abiertas. |
| E9-TP18 | R28 | Otras carreras. | Cierre vs cobro final, cierre vs cierre de caja, cierre vs anulación y cierre vs liberación de mesa vacía, en ambos órdenes: el cierre procede sólo si al obtener el lock todos los pendientes ya confirmaron; si no, `PT409` y procede al reintentar. Apertura vs creación de pedido: la creación sólo procede tras la confirmación de la apertura. Sin `40P01` ni `40001`. |

### 3.7 Interfaz

| ID | Requisitos | Escenario | Validaciones |
|---|---|---|---|
| E9-TP19 | R09, R12, R31, R32, DC-11 | Gate y pantalla “Local cerrado” (Node). | Para MOZO, COCINA y CAJA en cada ruta suya (incluidas `/ventas` y `/tecnica`, DC-11): `loading` → verificación; `closed` → texto exacto “Local cerrado — el sistema no se encuentra aperturado”, local, usuario, **Cerrar sesión** funcional y **Actualizar**, sin elementos operativos; `error` → **Reintentar** y **Cerrar sesión**, sin pantalla operativa; `open` → pantalla solicitada sin cambios. ADMIN, `/login` y `/403` no pasan por el gate. Un `PT409` de local cerrado en abrir pedido o abrir caja dispara `resync`. Caja muestra la identificación de la jornada. Objetivos ≥ 44 px; sin desplazamiento horizontal. |
| E9-TP20 | R06, R13, R22, R25, R30, R32 | UI ADMIN (Node). | Bloque de jornada como primer bloque de Inicio sin alterar los demás; abrir y cerrar con confirmación y guard (una sola llamada ante doble clic); `ya_existia`/`ya_estaba_cerrada` informados sin error; cierre impedido muestra pendientes y enlaces; ítem `OPERACIÓN → Jornadas` y ruta `/admin/jornadas` sólo para ADMIN; historial con identificación y “Cargar más”; sin totales. |

### 3.8 Realtime

| ID | Requisitos | Escenario | Validaciones |
|---|---|---|---|
| E9-TP21 | R10, R29 | Robustez (Node + cliente Realtime programático). | Señales duplicadas o desordenadas producen el mismo estado; pérdida de red y reconexión resincronizan; desmontaje/remontaje rápido (StrictMode, `SIGNED_IN`) conserva una suscripción con topic único (regresión E7-T12); cocina mantiene sus enlaces operativos; sin temporizadores periódicos de recarga. |
| E9-TP22 | R10, R29 | Señal multi-cliente (clientes Realtime programáticos). | ADMIN abre: mozo, cocina y caja pasan de “Local cerrado” a su pantalla sin refrescar (registrar latencia). ADMIN cierra: los tres pasan a “Local cerrado”. Un segundo ADMIN recibe ambos cambios. Clientes de otro local no reciben eventos. |

### 3.9 Integración, regresión y validación integral

| ID | Requisitos | Escenario | Validaciones |
|---|---|---|---|
| E9-TP23 | R07, R08, R18, R20, R24 | Recorrido técnico integrado (local, sin dispositivos físicos). | Local cerrado → apertura → caja abierta → pedido completo con cocina, entrega, solicitud de cuenta, cobro parcial → cierre de caja con el pedido pendiente (DF-01) → cierre de jornada rechazado → nueva sesión de caja en la misma jornada → cobro total → cierre de caja → cierre de jornada → segunda jornada de la misma fecha con `(2)` → jornada con cruce de medianoche simulado (fixture local). Todos los objetos derivan la jornada correcta. |
| E9-TP24 | R33 | Regresión H3–E10 con tests vigentes homologados. | Suites SQL `h3_*`, `h4_*`, `h5_*`, `h6_*`, `e1_*`, `e7_*`, `e10_*`, `order_audit_trail`, `release_empty_order_table`, `dbstd_*`, `tp*` y pruebas Node de mozo, cocina, caja, impresión, Inicio, Pedidos ADMIN, ventas y rutas, en su versión del repositorio. Los tests impactados por E9 ya fueron homologados en el repositorio en T07 (E9-D16): jornada abierta válida antes de la primera inserción de `pedido`/`sesion_caja`, limpiezas que cierran la jornada y dejan de borrar las filas que ella referencia, `h4_t05`/`h5_t06` esperando la publicación con `jornada_operativa`, aserciones de claves de `to_jsonb(sesion_caja)` con `jornada_operativa_id`. Revisión del diff de cada test homologado: sólo agrega la precondición de E9 y las limpiezas necesarias, sin cambiar datos relevantes, pasos, aserciones ni objetivo. **Criterio: los tests afectados por E9 pasan.** Todo fallo restante se corrige o, si se sostiene que es ajeno a E9, se ejecuta también contra la baseline anterior a E9 para demostrarlo, se documenta individualmente (test, error, causa, resultado en la baseline) y se informa al responsable antes de finalizar T07; ningún fallo se considera aprobado por haber existido antes. Sin triggers, funciones, roles ni configuraciones exclusivos para tests; sin desactivar la inmutabilidad; evidencia histórica de aceptación sin cambios. |
| E9-TP25 | Todos | Ejecución integral. | Replay limpio de todas las migraciones + seed; todos los SQL de `supabase/tests/` (incluidos los homologados en el repositorio y los de E9); suite Node completa; `npm run typecheck`; `npm run build` (limitaciones ambientales documentadas como en E7/E10); sin conexiones residuales. Todo fallo, con el mismo tratamiento de TP24. |

## 4. Pruebas humanas (E9-T08)

| ID | Caso | Dispositivos | Resultado esperado |
|---|---|---|---|
| E9-TH01 | Con el local cerrado y mozo, cocina y caja en “Local cerrado”, el ADMIN abre la jornada. | PC (ADMIN) + celular + tablet + PC (caja) | Inicio muestra `Jornada AAAA-MM-DD (1)` con quién y cuándo; los tres dispositivos se habilitan solos en pocos segundos. |
| E9-TH02 | Doble clic en “Abrir jornada” y dos administradores abriendo a la vez. | Dos PC | Una sola jornada; ambos ven la misma identificación; ningún error. |
| E9-TH03 | Login de cada rol con el local cerrado; cerrar sesión desde la pantalla; ADMIN usa carta, mesas y reportes con el local cerrado. | Celular, tablet, PC | Mensaje “Local cerrado — el sistema no se encuentra aperturado” claro; logout funciona; ADMIN opera sus funciones administrativas. |
| E9-TH04 | Atención completa con jornada abierta: pedido, cocina, entrega, solicitud de cuenta y cobro. | Celular + tablet + PC | Flujo idéntico al aceptado en H3–E10; Caja muestra la jornada junto al estado de caja. |
| E9-TH05 | Cierre con pendientes: pedido entregado con cobro parcial y caja abierta. Ver pendientes, cobrar el saldo, cerrar caja, cerrar jornada. | PC (ADMIN) + PC (caja) + celular | El primer intento se rechaza y lista exactamente lo pendiente; tras resolverlo, la jornada cierra y los dispositivos pasan a “Local cerrado”. |
| E9-TH06 | Cerrar y volver a abrir el mismo día (evento nocturno); si el horario de la prueba lo permite, mantener una jornada abierta pasada la medianoche. | PC | La nueva jornada es `(2)` de la misma fecha; la jornada que cruza la medianoche conserva su fecha (si no se puede ejecutar en vivo, queda cubierto por TP05/TP23 y así se registra). |
| E9-TH07 | Un dispositivo queda sin red mientras el ADMIN cierra la jornada; al recuperar la red intenta operar. | Celular + PC | Al reconectar muestra “Local cerrado”; cualquier intento de abrir pedido es rechazado por el servidor. |
| E9-TH08 | Uso táctil, responsive e historial. | Celular, tablet vertical/horizontal, PC | Pantalla de local cerrado, bloque de jornada e historial legibles, objetivos ≥ 44 px, sin desplazamiento horizontal; historial con las jornadas probadas en orden. |

## 4.1 Resultados humanos finales — 01/10/2026

Las definiciones originales de TH01–TH08 de la tabla anterior se conservan. El responsable comunica los siguientes resultados y aprueba explícitamente el cierre:

| Prueba | Resultado final | Registro |
|---|---|---|
| TH01 | EJECUTADA Y APROBADA | Confirmada por el responsable |
| TH02 | NO EJECUTADA — ACEPTADA POR DISPENSA DEL RESPONSABLE | No se dispone de un segundo ADMIN; dispensa explícita, no PASS ejecutado |
| TH03 | EJECUTADA Y APROBADA | Confirmada por el responsable |
| TH04 | EJECUTADA Y APROBADA | Confirmada por el responsable |
| TH05 | EJECUTADA Y APROBADA | Confirmada por el responsable |
| TH06 | EJECUTADA Y APROBADA | Confirmada por el responsable; no se infiere ejecución del cruce de medianoche opcional |
| TH07 | NO EJECUTADA — ACEPTADA POR DISPENSA DEL RESPONSABLE | Frontend aún no desplegado en un entorno adecuado para validar pérdida/recuperación real de conectividad; no PASS ejecutado |
| TH08 | EJECUTADA Y APROBADA | Confirmada por el responsable |

**Total: 6 ejecutadas y aprobadas; 2 no ejecutadas, aceptadas por dispensa.** Las dispensas constituyen la decisión humana de aceptación para TH02 y TH07 y no se presentan como cobertura ejecutada. No se repiten pruebas técnicas ni se ejecutan ambos escenarios retroactivamente. Véase [aceptación](acceptance.md).

## 5. Criterios de salida

- TP01–TP25 aprobados y TH01–TH08 aprobadas humanamente.
- Ningún defecto bloqueante abierto; DC-10, DC-11 y DC-12 reflejadas en la implementación.
- Tests afectados por E9 pasando tras su homologación en el repositorio, con cada test homologado y su motivo registrados.
- Ningún fallo aceptado automáticamente; cualquier fallo ajeno a E9 demostrado contra la baseline anterior, documentado individualmente e informado al responsable, que decidió su tratamiento antes de finalizar T07.
- Evidencia histórica de aceptación de H1–H6, E1, E7 y E10 sin cambios.
- Evidencia registrada por tarea y de la fase final.
- Aprobación humana explícita del cierre; recién entonces se redacta `acceptance.md`.

**Resultado de salida:** cierre aprobado el 01/10/2026 con la evidencia técnica registrada y las dos dispensas humanas explícitas de §4.1. Los 21 fallos SQL preexistentes permanecen como FAIL fuera de alcance, no como PASS.
