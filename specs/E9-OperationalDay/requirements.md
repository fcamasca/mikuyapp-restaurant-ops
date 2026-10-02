# MikuyApp — Evolución 9 — Jornada operativa del local: requisitos

## 1. Estado, objetivo y fuente de verdad

**Estado de E9: CERRADA, VALIDADA Y ACEPTADA (01/10/2026).** DH-01, DH-02 y DH-03 fueron resueltas por el responsable y se registran como DC-10, DC-11 y DC-12 (§10.2); no quedan decisiones humanas pendientes. Construcción y aceptación completadas. El paquete incluye [evidencia técnica](implementation.md) y [aceptación](acceptance.md): seis pruebas humanas ejecutadas/aprobadas y TH02/TH07 no ejecutadas, aceptadas por dispensa explícita del responsable.

Fuente principal de alcance: `docs/PLAN_MVP.md`, sección 15, **Evolución 9 — Jornada operativa del local**, más las decisiones funcionales tomadas en el análisis previo a este Spec Mode (registradas en §10 como decisiones cerradas). Baseline inspeccionada: `main` local en `5e3b40b` (“docs(e10): cerrar aceptación humana y documental”), sin cambios locales y declarada al día con `origin/main`; no fue posible consultar el remoto desde la sesión de inspección, por lo que la igualdad con GitHub debe reconfirmarse al iniciar la construcción. H1–H6, PM-001, E1 (incluido E1-T18), E7 y E10 están cerrados y aceptados. Última migración vigente: `20260930000200_e10_t03_solicitar_cuenta_lectura_caja.sql`. PM-002 permanece `TRANSITIONING`; este spec no toca `mikuyapp-prod`.

**Problema.** Hoy cualquier usuario autenticado de un rol operativo puede abrir pedidos, abrir caja y operar en cualquier momento. No existe una representación del “local abierto”: no hay forma de impedir operaciones fuera de la atención, ni de saber quién y cuándo inició y terminó la operación del día, ni de agrupar pedidos y sesiones de caja por periodo real de atención (que puede cruzar la medianoche o repetirse en una misma fecha).

**Objetivo.** Incorporar, con el menor cambio posible:

1. una **jornada operativa** transaccional que el `ADMINISTRADOR` abre y cierra explícitamente, con trazabilidad de actor y hora;
2. el bloqueo de toda operación del restaurante cuando no existe jornada abierta, visible en la interfaz y **autoritativo en PostgreSQL**;
3. la pertenencia obligatoria e inmutable de cada `pedido` y cada `sesion_caja` a la jornada en la que nacen, asignada por PostgreSQL;
4. un cierre de jornada que sólo procede cuando no queda operación pendiente;
5. historial consultable de jornadas.

PostgreSQL permanece como autoridad de estados, permisos e invariantes. E9 **no** agrega estados a `pedido`, `detalle_pedido`, `mesa` ni `sesion_caja`, **no** modifica reglas financieras de E1, **no** calcula métricas y **no** es un sistema de horarios.

## 2. Baseline verificable y brechas

| Área | Estado actual verificado en el repositorio | Brecha de E9 |
|---|---|---|
| Local | `local(id, codigo, nombre, activo, creado_en)`; un local operativo. | No existe estado “abierto/cerrado” ni jornada. |
| Contexto | `obtener_contexto_autenticado()` resuelve perfil activo, rol y `local_id`; todas las RPC lo usan. | Ninguna RPC conoce la jornada. |
| Creación de pedido | `crear_o_recuperar_pedido_mesa(uuid)` (MOZO) bloquea la mesa, recupera el pedido vigente o inserta uno nuevo. Sigue existiendo y ejecutable la vía heredada `h3_abrir_o_recuperar_pedido(uuid)`, que también inserta pedidos. | Un pedido puede nacer sin jornada; no hay pertenencia a periodo de atención. |
| Pedido | `pedido(id, local_id, mesa_id, creado_por, estado, creado_en, enviado_en, modificado_*)`; `PAGADO` y `ANULADO` terminales; `ENTREGADO` reabrible antes del primer pago. | Falta `jornada_operativa_id` obligatorio e inmutable. |
| Caja | E1: `caja` física; `sesion_caja` `ABIERTA`/`CERRADA`, a lo sumo una abierta por caja (`uq_sesion_caja_abierta`); apertura por `rpc_abrir_sesion_caja` (orden de locks `caja → sesión`); cierre normal (CAJA) y supervisor (ADMIN) con arqueo; DF-01 permite cerrar caja con pedidos `ENTREGADO` pendientes. | La sesión puede abrirse en cualquier momento y no pertenece a ningún periodo de atención. |
| Cobro | `rpc_registrar_cobro_pedido` (`sesion_caja → pedido → mesa`), más vías heredadas aún ejecutables (`registrar_pago_pedido`, `rpc_registrar_pago_total_pedido`, `rpc_registrar_pago_pedido_v2`); todas insertan `pago` con `sesion_caja_id`. | Nada garantiza que pedido y sesión de cobro pertenezcan al mismo periodo. |
| Otras operaciones | Detalles, envío, cocina, cancelación, entrega, solicitud de cuenta (E10), liberación de mesa vacía, descuentos, anulación, movimientos y cierre de caja: todas requieren un pedido no terminal o una sesión `ABIERTA`. | Deben quedar inoperables sin jornada abierta. |
| Reportes | Resumen del día y reportes de Caja por fecha calendario `America/Lima` (H6/E1); Inicio ADMIN con snapshot actual (E1-R24). | Sin cambios en E9 (ver HZ-03). |
| Realtime | Publicación `supabase_realtime` = `detalle_pedido`, `mesa`, `pedido`, `solicitud_cuenta`; servicio `operationsRealtimeService` con topic único por suscripción (E7-T12); cocina con `kitchenRealtimeService`. | Ninguna señal informa apertura o cierre del local. |
| Frontend | `App.tsx` resuelve ruta por rol (`appRoutes.ts`); ADMIN usa `AdminShell` con Inicio, Operación, Reportes y Configuración; MOZO `/mozo/*`, COCINA `/cocina`, CAJA `/caja` y `/ventas`. | No existe pantalla de local cerrado ni administración de jornada. |
| Seguridad | RPC `SECURITY DEFINER` con `search_path = pg_catalog`; tablas nuevas sin escritura directa; `service_role` revocado (E7-T10); conflictos funcionales `PT409`, nunca `40001` (E1-R25). | Objetos nuevos deben seguir exactamente la misma convención. |

## 3. Conceptos

| Concepto | Definición |
|---|---|
| **Jornada operativa** | Entidad transaccional que representa un periodo real de atención del local. Nace sólo cuando un `ADMINISTRADOR` ejecuta **Abrir jornada** y termina cuando un `ADMINISTRADOR` ejecuta **Cerrar jornada**. No es una maestra, un calendario, un horario ni un turno preconfigurado. |
| **Local abierto / cerrado** | El local está **abierto** si y sólo si existe una jornada `ABIERTA` para él; en cualquier otro caso está **cerrado**. No existe otro indicador. |
| **Fecha operativa** | Fecha calendario `America/Lima` del instante de apertura (hora del servidor). No cambia aunque la jornada cruce la medianoche. |
| **Número de jornada** | Correlativo `N ≥ 1` dentro de la combinación local + fecha operativa, asignado automáticamente al abrir. |
| **Identificación visible** | `Jornada YYYY-MM-DD (N)`, p. ej. `Jornada 2026-10-01 (2)`. El identificador técnico (PK) no se muestra ni se pide al usuario. |
| **Operación del restaurante** | Toda acción que crea o hace avanzar pedidos, sesiones de caja y su dinero: abrir/recuperar pedido, agregar/editar/retirar/cancelar detalles, enviar, recibir y preparar en cocina, imprimir comandas, entregar, solicitar cuenta, liberar mesa, descuentos, anulaciones, abrir caja, movimientos, cobrar y cerrar caja. |
| **Función administrativa no operativa** | Configuración (carta, mesas), consultas y reportes históricos (ventas, caja, auditoría), notificaciones, administración de la jornada misma y consulta de su historial. No crea ni hace avanzar operación del restaurante. |

## 4. Actores y permisos

| Actor | Capacidades en E9 | Restricciones |
|---|---|---|
| `ADMINISTRADOR` | Consulta el estado del local y la jornada abierta; abre y cierra jornadas; consulta qué impide el cierre; consulta el historial de jornadas de su local. Conserva todas sus funciones administrativas no operativas con el local abierto o cerrado. | No existe cierre forzado, reapertura, edición ni borrado de jornadas. Sus acciones operativas existentes (anulación, decisión de descuentos, cierre supervisor de caja) sólo tienen objeto mientras existe operación pendiente, es decir, con jornada abierta. |
| `MOZO`, `COCINA`, `CAJA` | Se autentican normalmente. Con local abierto operan exactamente como hoy. Con local cerrado ven “Local cerrado — el sistema no se encuentra aperturado” y pueden cerrar sesión. Ven el cambio de estado sin refrescar. | No abren ni cierran jornadas, no tienen vista de historial ni de pendientes de cierre, no acceden funcionalmente a pantallas operativas ni ejecutan operaciones con el local cerrado. A nivel de datos pueden leer las filas de jornada de su local (identificadores y horas, sin nombres ni importes), lo que es necesario para recibir por Realtime la señal de cierre (`design.md` E9-D11). |
| `anon` / otro local | Ninguna. | Sin lectura ni ejecución. |

## 5. Requisitos funcionales

### 5.1 Apertura

| ID | Requisito | Prioridad |
|---|---|---|
| E9-R01 | Sólo el `ADMINISTRADOR` activo del local podrá abrir una jornada. Otro rol, perfil inactivo, sin sesión u otro local → rechazo `42501` sin efectos. | Must |
| E9-R02 | Abrir una jornada sólo procede si el local no tiene una jornada `ABIERTA`. Existirá **como máximo una jornada `ABIERTA` por local** en todo momento, garantizado en PostgreSQL. | Must |
| E9-R03 | Al abrir, PostgreSQL registrará local, fecha operativa, número correlativo, estado `ABIERTA`, usuario que abre y fecha/hora de servidor. Ninguno de esos datos se acepta desde el cliente. | Must |
| E9-R04 | La fecha operativa será la fecha `America/Lima` del instante de apertura. El número será el siguiente correlativo para ese local y esa fecha operativa (1 si es la primera). Pueden existir varias jornadas con la misma fecha operativa y fechas sin ninguna jornada. | Must |
| E9-R05 | Apertura idempotente: un doble clic, un reintento tras timeout o dos administradores que abren a la vez producen **una sola** jornada. El llamador que no la creó recibe la jornada abierta existente indicando que ya existía, sin error. Un reintento con la misma clave de solicitud devuelve siempre la misma jornada, aun si entretanto fue cerrada, y nunca abre otra. | Must |

### 5.2 Identificación, fecha operativa y medianoche

| ID | Requisito | Prioridad |
|---|---|---|
| E9-R06 | Toda vista que muestre una jornada la identificará como `Jornada YYYY-MM-DD (N)`. La identificación se deriva de fecha operativa y número; es única por local. | Must |
| E9-R07 | La jornada **no se cierra automáticamente** a medianoche ni por tiempo transcurrido. Puede cruzar uno o más cambios de día calendario y conserva su fecha operativa y su número. Ejemplo: abierta 01/10 21:00 y cerrada 02/10 02:30 sigue siendo `Jornada 2026-10-01 (2)`. | Must |
| E9-R08 | Si el local cierra y vuelve a abrir (p. ej. cierre 18:00 y nueva apertura 21:00 por un evento), se crea una **nueva** jornada con el siguiente número; la anterior no se reabre. | Must |

### 5.3 Local cerrado

| ID | Requisito | Prioridad |
|---|---|---|
| E9-R09 | Con el local cerrado, `MOZO`, `COCINA` y `CAJA` podrán autenticarse. Tras el login verán **únicamente** la pantalla **“Local cerrado — el sistema no se encuentra aperturado”**, con el nombre del local y su usuario, y podrán **cerrar sesión**. No accederán funcionalmente a ninguna pantalla operativa ni de consulta propia de esos roles, incluidas `/ventas` y `/tecnica` (DC-11). | Must |
| E9-R10 | La apertura y el cierre de la jornada se reflejarán en los dispositivos de `MOZO`, `COCINA` y `CAJA` sin refrescar manualmente (desbloqueo al abrir, bloqueo al cerrar). | Must |
| E9-R11 | El bloqueo visual no es la protección autoritativa: con el local cerrado, **toda operación del restaurante (§3) será rechazada por PostgreSQL** aunque se invoque directamente la API, sin efectos parciales. La creación de pedidos y la apertura de caja se rechazan con conflicto funcional `PT409` y el mensaje “Local cerrado — el sistema no se encuentra aperturado”; el resto de operaciones resultan inaplicables porque no puede existir objeto operativo vigente sin jornada abierta (E9-R20). | Must |
| E9-R12 | Si el estado del local no puede determinarse (error de red o de lectura), la interfaz de `MOZO`, `COCINA` y `CAJA` no mostrará la pantalla operativa: mostrará un estado de verificación con **Reintentar** y **Cerrar sesión**. | Must |
| E9-R13 | Con el local abierto o cerrado, el `ADMINISTRADOR` conservará sus funciones administrativas no operativas (configuración, reportes, historial, notificaciones) y la capacidad de consultar el estado y abrir una nueva jornada. | Must |

### 5.4 Asociación de pedidos y sesiones de caja

| ID | Requisito | Prioridad |
|---|---|---|
| E9-R14 | Todo `pedido` pertenecerá obligatoriamente a exactamente una jornada: aquella `ABIERTA` del mismo local en el momento de su creación. PostgreSQL la obtiene y asigna; el cliente no la decide ni la suministra, y un valor distinto suministrado por cualquier vía se rechaza. | Must |
| E9-R15 | Crear un pedido sin jornada abierta en su local se rechaza (E9-R11) por cualquier vía de creación, incluida la heredada. | Must |
| E9-R16 | La jornada de un pedido es **inmutable**: no puede cambiarse ni anularse después de la creación. No existe traslado de pedidos entre jornadas. | Must |
| E9-R17 | Toda `sesion_caja` pertenecerá obligatoriamente a la jornada `ABIERTA` del local en el momento de su apertura, asignada por PostgreSQL e inmutable. Abrir caja sin jornada abierta se rechaza (E9-R11). La recuperación idempotente de una sesión ya existente (E1-R02) no cambia. | Must |
| E9-R18 | Un cobro sólo podrá registrarse si el pedido y la sesión de caja usada pertenecen a la **misma jornada**; en caso contrario se rechaza con `PT409` sin efectos, por cualquier vía de cobro vigente. | Must |
| E9-R19 | No se duplicará `jornada_operativa_id` en tablas que lo derivan inequívocamente de `pedido` o `sesion_caja` (detalles, historiales, comandas, solicitudes de cuenta, descuentos, anulaciones, cobros, pagos, movimientos, cierres, auditoría, notificaciones). | Must |

### 5.5 Cierre

| ID | Requisito | Prioridad |
|---|---|---|
| E9-R20 | Sólo el `ADMINISTRADOR` activo del local podrá cerrar la jornada abierta, y sólo si se cumplen simultáneamente, sobre el estado persistido al ejecutar: (1) ninguna `sesion_caja` de la jornada está `ABIERTA`; (2) todos los pedidos de la jornada están en `PAGADO` o `ANULADO`. Si no se cumplen, el cierre se rechaza con `PT409`, sin efectos, indicando cuántos pedidos y sesiones lo impiden. | Must |
| E9-R21 | Al cerrar, PostgreSQL registrará estado `CERRADA`, usuario que cierra y fecha/hora de servidor (posterior o igual a la apertura). Una jornada cerrada queda **cerrada definitivamente**: no se reabre, no se edita y no se borra. | Must |
| E9-R22 | El `ADMINISTRADOR` podrá consultar, antes de intentar cerrar, qué impide el cierre: pedidos no terminales (mesa, pedido, estado) y sesiones de caja abiertas (caja, quién la abrió, desde cuándo), sin importes. La consulta es informativa; la decisión autoritativa la toma el cierre. | Must |
| E9-R23 | Cierre idempotente: repetir el cierre de una jornada ya cerrada devuelve la jornada cerrada indicando que ya lo estaba, sin error y sin cambiar actor ni hora. Cerrar una jornada distinta de la indicada, inexistente o de otro local no procede. | Must |
| E9-R24 | E9 **no** implementa cierre forzado, cierre automático, traslado de pedidos pendientes a otra jornada, ni cobro o anulación implícitos al cerrar. Los pendientes se resuelven con las operaciones vigentes (cobro E1, anulación E1, liberación de mesa vacía H3, cierre de caja normal o supervisor E1). | Must |

### 5.6 Historial y trazabilidad

| ID | Requisito | Prioridad |
|---|---|---|
| E9-R25 | El `ADMINISTRADOR` consultará el historial de jornadas de su local, de la más reciente a la más antigua, con identificación, estado, quién y cuándo abrió, y quién y cuándo cerró. Sin totales, ventas, conteos analíticos ni duraciones agregadas (E8). | Must |
| E9-R26 | Los datos persistidos permitirán reconstruir, para cada pedido y cada sesión de caja, la jornada a la que pertenece, y para cada jornada su apertura y cierre (actor y hora de servidor). E9 no crea vistas, agregaciones ni reportes por jornada. | Must |

### 5.7 Seguridad, concurrencia, Realtime e interfaz

| ID | Requisito | Prioridad |
|---|---|---|
| E9-R27 | Toda operación y lectura nueva validará en servidor identidad, perfil activo, rol y `local_id`. Ninguna escritura directa de cliente sobre la jornada. Conflictos funcionales con `PT409`; ninguna operación de E9 genera `40001`. | Must |
| E9-R28 | Las carreras apertura vs apertura, cierre vs cierre, cierre vs creación de pedido, cierre vs apertura de caja y cierre vs cobro/anulación/cierre de caja se serializarán sin interbloqueos, sin duplicados y sin estados parciales: nunca quedará un pedido o una sesión asociados a una jornada cerrada en un estado no permitido por E9-R20. | Must |
| E9-R29 | Realtime se usará sólo como señal para recargar el estado autoritativo desde PostgreSQL, tolerando eventos duplicados, desordenados y reconexiones; sin polling y conservando la corrección E7-T12 (topic propio por suscripción). Cocina conserva sus enlaces actuales para la operación. | Must |
| E9-R30 | **UI ADMIN:** en Inicio, un bloque “Jornada operativa” muestra el estado del local, la jornada abierta (identificación, quién y desde cuándo) y las acciones **Abrir jornada** y **Cerrar jornada**, ambas con confirmación, protección contra doble clic y estados de carga/error/reintento; ante un cierre impedido muestra los pendientes (E9-R22). Una vista de historial de jornadas en la navegación ADMIN. | Must |
| E9-R31 | **UI CAJA:** con jornada abierta, la estación de Caja muestra la identificación de la jornada junto al estado de la caja. Mozo y Cocina no cambian con el local abierto. | Should |
| E9-R32 | Objetivos táctiles ≥ 44 px y sin desplazamiento horizontal en celular, tablet vertical/horizontal y PC, incluida la pantalla de local cerrado. | Must |
| E9-R33 | Con el local abierto, los flujos aprobados de H3, H4, H5, H6, E1, E7 y E10 continuarán funcionando exactamente como fueron aceptados, salvo las adiciones declaradas en este spec. | Must |

## 6. Estados propios de la jornada

No se agregan estados a `pedido`, `detalle_pedido`, `mesa` ni `sesion_caja`.

| Estado | Significado | Transición |
|---|---|---|
| `ABIERTA` | El local está operando. | Inicial, creada por `ADMINISTRADOR`. |
| `CERRADA` | La jornada terminó sin operación pendiente. | `ABIERTA → CERRADA` por `ADMINISTRADOR`, sólo si se cumple E9-R20. Terminal. |

### 6.1 Invariantes que E9 garantiza en PostgreSQL

| ID | Invariante |
|---|---|
| I-1 | A lo sumo una jornada `ABIERTA` por local. |
| I-2 | Todo pedido no terminal (`ABIERTO`…`ENTREGADO`) pertenece a la jornada `ABIERTA` de su local. Equivalente: sin jornada abierta no existe ningún pedido no terminal. |
| I-3 | Toda `sesion_caja` `ABIERTA` pertenece a la jornada `ABIERTA` de su local. Equivalente: sin jornada abierta no existe ninguna sesión de caja abierta. |
| I-4 | Todo pago registrado con sesión de caja pertenece, a través de pedido y sesión, a una misma jornada. |
| I-5 | La jornada de un pedido o de una sesión nunca cambia; una jornada cerrada nunca vuelve a abrirse. |

I-2 e I-3 se sostienen porque sólo se crean pedidos y sesiones en la jornada abierta (E9-R14, E9-R17), un pedido terminal no vuelve a un estado operativo (EC-02 de E1) y una jornada no se cierra con pedidos no terminales ni sesiones abiertas (E9-R20).

### 6.2 Matriz de operaciones según el estado del local

| Operación | Local abierto | Local cerrado |
|---|---|---|
| Login / logout de cualquier rol | Permitido | Permitido |
| Abrir jornada (ADMIN) | Idempotente: devuelve la abierta | Crea nueva jornada |
| Cerrar jornada (ADMIN) | Permitido si E9-R20 | Idempotente sobre la ya cerrada |
| Consultar estado, pendientes de cierre e historial (ADMIN) | Permitido | Permitido |
| Configuración, reportes, auditoría, notificaciones (ADMIN) | Permitido | Permitido |
| Abrir/recuperar pedido (MOZO), por cualquier vía | Permitido | `PT409` “Local cerrado…” |
| Abrir caja (CAJA) | Permitido | `PT409` “Local cerrado…” |
| Resto de operaciones sobre pedidos o sesiones existentes | Reglas vigentes | Inaplicables: no existe pedido no terminal ni sesión abierta (I-2, I-3); se rechazan con los conflictos vigentes |
| Pantallas operativas de MOZO, COCINA, CAJA | Visibles | Reemplazadas por “Local cerrado” |

## 7. Flujo funcional objetivo

```text
Local cerrado (sin jornada ABIERTA)
   │  MOZO/COCINA/CAJA: login → “Local cerrado — el sistema no se encuentra aperturado”
   ▼
ADMIN: Abrir jornada → Jornada 2026-10-01 (1) ABIERTA (abierta_por/en)
   │  Realtime (señal) → los dispositivos recargan el estado y desbloquean sus pantallas
   ▼
CAJA abre caja (sesión ∈ jornada) · MOZO abre pedidos (pedido ∈ jornada)
cocina → entrega → solicitud de cuenta → cobro E1 (pedido y sesión ∈ misma jornada)
   ▼
Fin de atención: cobrar o anular pendientes → cerrar caja (arqueo E1)
   ▼
ADMIN: Cerrar jornada → valida 0 sesiones abiertas y 0 pedidos no terminales
   │  CERRADA (cerrada_por/en) · Realtime → dispositivos muestran “Local cerrado”
   ▼
(nueva atención el mismo día → Jornada 2026-10-01 (2))
```

## 8. Concurrencia y reintentos relevantes

- Doble clic o reintento de **Abrir jornada**; dos administradores a la vez: una sola jornada; los demás reciben la existente con “ya existía” (E9-R05).
- Doble clic o reintento de **Cerrar jornada**; dos administradores a la vez: un solo cierre; el resto recibe “ya estaba cerrada” (E9-R23).
- Cierre vs creación de pedido o apertura de caja: si la creación confirma primero, el cierre ve el pendiente y se rechaza; si el cierre confirma primero, la creación se rechaza con “Local cerrado”.
- Cierre vs cobro final, anulación, liberación de mesa o cierre de caja aún en curso: el cierre ve el estado confirmado; si todavía hay pendiente se rechaza y el administrador reintenta. Nunca queda una jornada cerrada con pendientes.
- Apertura vs creación de pedido: sin jornada confirmada la creación se rechaza; tras la confirmación de la apertura procede.

## 9. Restricciones

- No introducir horarios, turnos configurables, calendario laboral, días laborables, eventos programados, jornadas nocturnas preconfiguradas, cierre automático, reapertura ni traslado de pedidos entre jornadas.
- No crear estados nuevos de `pedido`, `detalle_pedido`, `mesa` ni `sesion_caja`; no modificar reglas financieras, documentos, auditoría ni reportes de E1.
- No implementar métricas, tableros, comparaciones, totales por jornada ni otras capacidades analíticas de E8.
- No introducir polling, backend externo ni librerías nuevas; reutilizar Supabase/PostgreSQL/Realtime.
- Sin backfill ni estrategias legacy: no existe data histórica que deba asociarse a jornadas (decisión del análisis previo, DC-07). La migración aborta explícitamente si encuentra filas incompatibles y la preparación o limpieza de ambientes es una acción separada y autorizada por el responsable (DC-12, HZ-02).
- No tocar PM-002 ni `mikuyapp-prod`. No modificar migraciones históricas ni la evidencia de H1–H6, E1, E7 y E10.

## 10. Decisiones

### 10.1 Cerradas en el análisis funcional previo (no se reabren en este spec)

| ID | Decisión |
|---|---|
| DC-01 | La jornada es una entidad transaccional, no maestra ni calendario; sólo existe si un ADMIN la abre explícitamente. |
| DC-02 | No se configuran horarios, turnos, días laborables, eventos ni jornadas nocturnas. Puede haber fechas sin jornada y varias jornadas por fecha. |
| DC-03 | Una sola jornada `ABIERTA` por local; una jornada cerrada no se reabre. |
| DC-04 | Identificación `Jornada YYYY-MM-DD (N)`; `N` correlativo por local + fecha operativa, asignado al abrir; PK técnica no visible. |
| DC-05 | Fecha operativa = fecha de apertura; sin cierre automático a medianoche; puede cruzar al día siguiente; reabrir el local crea una jornada nueva. |
| DC-06 | MOZO, COCINA y CAJA pueden autenticarse con el local cerrado y ven “Local cerrado — el sistema no se encuentra aperturado”; logout siempre posible; bloqueo visual no autoritativo; PostgreSQL revalida. |
| DC-07 | `pedido.jornada_operativa_id` y `sesion_caja.jornada_operativa_id` obligatorios, asignados por PostgreSQL, inmutables; sin backfill. |
| DC-08 | Pedido y sesión de cobro de la misma jornada; no duplicar la jornada en tablas derivables. |
| DC-09 | Cierre sólo sin sesiones de caja abiertas y con todos los pedidos `PAGADO`/`ANULADO`; sin cierre forzado ni traslado. |

### 10.2 Decisiones humanas resueltas en la revisión del spec

| ID | Decisión adoptada | Comportamiento cerrado |
|---|---|---|
| DC-10 (ex DH-01, opción A) | Validación autoritativa de la jornada sólo en los puntos donde nace o se cruza la operación. | PostgreSQL valida la jornada en: (1) la creación de `pedido`; (2) la apertura de `sesion_caja`; (3) la coherencia de jornada en `pago`; (4) el cierre de jornada, condicionado a que no existan pedidos no terminales ni sesiones de caja abiertas. **No** se agregan validaciones repetidas de jornada a las ≈25 RPC operativas existentes ni a las políticas de escritura directa de `detalle_pedido`: por I-2/I-3 esas operaciones no encuentran objeto operativo con el local cerrado y se rechazan con su conflicto vigente (`design.md` E9-D05). |
| DC-11 (ex DH-02, opción A) | Con el local cerrado, los roles operativos sólo pueden cerrar sesión. | `MOZO`, `COCINA` y `CAJA` se autentican y ven únicamente “Local cerrado — el sistema no se encuentra aperturado”; pueden cerrar sesión; no acceden funcionalmente a `/ventas`, `/tecnica` ni a otras pantallas operativas o de consulta propias de esos roles. `ADMINISTRADOR` conserva sus funciones administrativas no operativas y la administración de la jornada. |
| DC-12 (ex DH-03, opción A) | Sin backfill ni compatibilidad con datos históricos. | `pedido.jornada_operativa_id` y `sesion_caja.jornada_operativa_id` permanecen `NOT NULL`. La migración aborta de forma explícita si encuentra filas existentes incompatibles. La preparación o limpieza de ambientes se realiza únicamente mediante una acción separada y autorizada por el responsable del proyecto, fuera de E9. No se toca `mikuyapp-prod`. |

No quedan decisiones humanas pendientes en este spec.

## 11. Hallazgos e interacciones detectados en la inspección

| ID | Hallazgo | Tratamiento |
|---|---|---|
| HZ-01 | En `supabase/tests/`, 41 archivos insertan pedidos directamente como `postgres`, 26 insertan `sesion_caja`, 61 crean su propio `local` y 10 scripts de carreras (`*_setup`/`*_cleanup`) borran locales. Con `jornada_operativa_id` obligatorio y FK `RESTRICT`, esos tests fallarían sin cambios. | Homologación mínima directamente en el repositorio durante la construcción (`design.md` E9-D16, E9-T07): el fixture crea primero una jornada abierta válida y ajusta sólo las limpiezas estrictamente necesarias, sin alterar comportamiento, datos relevantes, aserciones ni objetivo del test; sin mecanismos de base de datos exclusivos para tests; la evidencia histórica de aceptación no se modifica. |
| HZ-02 | El proyecto Supabase actual (`TRANSITIONING`) es DEV y a la vez presta Production, y contiene pedidos y sesiones de las validaciones de E1/E7/E10 (p. ej. `e10-dev-verificacion.log`). Una columna `NOT NULL` sin backfill no puede agregarse sobre filas existentes. | Precondición explícita de la migración (aborto con mensaje). Sin backfill (DC-07, DC-12); la preparación del ambiente es una acción separada y autorizada por el responsable. |
| HZ-03 | `obtener_resumen_ventas_hoy`, `rpc_obtener_resumen_diario_caja` e Inicio ADMIN agregan por fecha calendario `America/Lima`. Una jornada que cruza la medianoche reparte su venta en dos “días” en esos reportes. | Sin cambios en E9 (reportes fuera de alcance). Reportes por jornada quedan para E8 u otra evolución; los datos para hacerlos existen (E9-R26). |
| HZ-04 | E1 DF-01 permite cerrar caja con pedidos `ENTREGADO` pendientes; E1-R12 impide anular pedidos con pagos. | Compatible: esos pedidos sólo pueden cerrarse cobrándolos en una nueva sesión de caja **de la misma jornada**; mientras tanto la jornada no puede cerrarse. Secuencia de cierre documentada (§7) y probada (E9-TH05). |
| HZ-05 | Siguen ejecutables vías de cobro heredadas (E10 HZ-05) y la creación heredada `h3_abrir_o_recuperar_pedido(uuid)`. | Las reglas de E9 se implementan sobre las tablas (`pedido`, `sesion_caja`, `pago`) y no dentro de RPC concretas, para cubrir toda vía sin modificarlas. |
| HZ-06 | `waiterOrderService.openOrder` traduce cualquier error de `crear_o_recuperar_pedido_mesa` a “No pudimos abrir el pedido…”. | Ajuste mínimo: un `PT409` de local cerrado provoca la resincronización del estado del local. |
| HZ-07 | `rpc_abrir_sesion_caja`, `rpc_obtener_sesion_caja_activa` y `rpc_obtener_historial_sesiones_caja` devuelven `to_jsonb(sesion_caja)`; incorporarán `jornada_operativa_id` automáticamente. | Cambio aditivo compatible; los consumidores ignoran claves desconocidas. Los tests vigentes que fijen exactamente esas claves se actualizan mínimamente en el repositorio (E9-D16). |
| HZ-08 | La publicación `supabase_realtime` pasa de cuatro a cinco tablas. `h4_t05_realtime_publication_rls.sql`, `h5_t06_realtime_cashier_signal.sql` y PM-002 fijan la lista publicada. | Ambos tests vigentes se actualizan en el repositorio para esperar `jornada_operativa` (E9-D16); la próxima revalidación de PM-002 deberá esperar cinco tablas (dependencia, sin modificar PM-002). |
| HZ-09 | Solicitudes de cuenta (E10), descuentos pendientes (E1) y comandas (E7) dependen de pedidos no terminales. | Quedan resueltos automáticamente cuando todos los pedidos son terminales; no agregan condiciones de cierre propias. |

## 12. Alcance y fuera de alcance

**Dentro:** E9-R01–E9-R33; invariantes I-1–I-5; lecturas y pantallas mínimas para ADMIN, pantalla de local cerrado para MOZO/COCINA/CAJA, señal Realtime de jornada.

**Fuera:** horarios, turnos, calendario, eventos y cierre automático; reapertura y edición de jornadas; cierre forzado; traslado de pedidos; notificaciones de apertura/cierre de jornada (el plan no las exige; E1 sólo notifica caja); totales, ventas, conteos o duraciones por jornada y cualquier analítica (E8); cambio de reportes por fecha calendario a reportes por jornada; varios locales o selector de local (E5/E6); avisos sonoros o push; cambios de PM-002.

## 13. Trazabilidad

La matriz `Requirement → Design → Task → Test` se mantiene en `tasks.md` §5. Cada requisito E9-R01–E9-R33 tiene al menos una decisión E9-Dxx, una tarea E9-Txx y un escenario E9-TPxx/E9-THxx.
