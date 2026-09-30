# MikuyApp — Evolución 10 — Solicitud de cuenta y atención en caja: requisitos

## 1. Estado, objetivo y fuente de verdad

**Estado: SPEC APROBADO (30/09/2026).** El responsable aprobó `requirements.md`, `design.md`, `tasks.md` y `test-plan.md`, con DH-01 = A y DH-02 = B (sección 10). La construcción (E10-T02 en adelante) queda habilitada y todavía no se inició. No existe `acceptance.md`.

> Nota: este documento se redactó en Spec Mode; los requisitos aprobados se conservan sin cambios.

Fuente principal de alcance: `docs/PLAN_MVP.md`, sección 15, **Evolución 10 — Solicitud de cuenta y atención en caja** (incorporada en este Spec Mode) y la exclusión expresa de E7 (“Fuera de E7: solicitud de cuenta del mozo a caja y su atención por caja”). Baseline verificada: `main` = `origin/main` = `ee3c94c` (cierre de E7), sin cambios locales, con H1–H6, PM-001, E1 (incluido el correctivo E1-T18) y E7 cerrados y aceptados. Última migración vigente: `20260924000800_e7_t10_privilegios_supabase.sql`. PM-002 permanece `TRANSITIONING`: construcción y verificación en local/DEV; este spec no toca `mikuyapp-prod`.

**Problema.** Hoy el intervalo `ENTREGADO → PAGADO` mezcla dos tiempos distintos: el tiempo en que el cliente todavía no pide pagar y el tiempo que Caja tarda en atender después de que el cliente pide la cuenta. Además, el mozo no tiene forma de avisar a Caja dentro de la aplicación. Esto impide que Evolución 8 atribuya correctamente tiempos y cuellos de botella a Caja.

**Objetivo.** Incorporar, con el menor cambio posible:

1. que el `MOZO` avise a Caja cuando una mesa desea pagar la cuenta total;
2. que `CAJA` reciba la solicitud en tiempo real (Realtime como señal → refetch autoritativo, sin polling);
3. que Caja atienda reutilizando exactamente el flujo de cobro de E1;
4. que queden eventos y timestamps fiables para que E8 separe tiempo del cliente y tiempo atribuible a Caja.

PostgreSQL permanece como autoridad de estados, permisos y trazabilidad. E10 **no** agrega estados a `pedido`, `detalle_pedido` ni `mesa`, **no** calcula métricas y **no** modifica el modelo financiero de E1.

## 2. Baseline verificable y brechas

| Área | Estado actual verificado en el repositorio | Brecha de E10 |
|---|---|---|
| Estados | `pedido.estado ∈ {ABIERTO…LISTO, ENTREGADO, PAGADO, ANULADO}`; `mesa.estado ∈ {LIBRE, OCUPADA, PEDIDO_LISTO, PENDIENTE_PAGO}`. `ENTREGADO`/`PENDIENTE_PAGO` significa “entregado y pendiente de pago” sin distinguir si el cliente pidió pagar. | No existe representación de la solicitud de cuenta. |
| Entrega | `entregar_pedido` (versión E1-T18) cambia `LISTO → ENTREGADO`, registra `historial_estado` y deja la mesa `PENDIENTE_PAGO`. | Ninguna. Es el inicio del “tiempo del cliente”. |
| Reapertura | Antes del primer pago, agregar un producto a un pedido `ENTREGADO` lo devuelve al flujo operativo (`sincronizar_estado_operativo_pedido`, H5; E1-R16 la bloquea tras el primer cobro). | Una solicitud previa a la reapertura deja de ser válida. |
| Cobro | `rpc_registrar_cobro_pedido` (E1, versión T18) bloquea `sesion_caja → pedido → mesa`; admite cobro `TOTAL`/`PARCIAL` con N medios; sólo el acto que deja saldo 0 cambia `ENTREGADO → PAGADO`, registra `historial_estado` y libera la mesa. Siguen ejecutables las vías históricas `registrar_pago_pedido`, `rpc_registrar_pago_total_pedido` y `rpc_registrar_pago_pedido_v2`. | La atención de la solicitud debe cerrarse con el pago, sin duplicar lógica de pagos. |
| Anulación | `anular_pedido_supervisado` (ADMIN) cambia a `ANULADO` sin pagos y libera la mesa. | Una solicitud pendiente de un pedido anulado debe quedar sin efecto. |
| Lectura de Caja | `obtener_pedidos_pendientes_pago_caja()` (E1-T10) devuelve pedidos `ENTREGADO`/`PENDIENTE_PAGO` con detalle, subtotal, descuento, neto, pagado y saldo; Caja la llama en cada refresco. | Caja no sabe qué mesas pidieron la cuenta ni desde cuándo. |
| Historial | `historial_estado` registra transiciones de cabecera; `historial_detalle_pedido` (E7) registra transiciones de detalle; `cobro` (E1) registra actor/hora de cada acto de cobro. | No existe el instante “cliente pide la cuenta”. |
| Realtime | Publicación `supabase_realtime` con exactamente `detalle_pedido`, `pedido`, `mesa`. `operationsRealtimeService` escucha `INSERT`/`UPDATE` de esas tres tablas con topic propio por suscripción (corrección E7-T12, `bbf9edd`) y recarga snapshots. CAJA sólo recibe `pedido` en `ENTREGADO`/`PAGADO` (`pedido_select_caja_local_cobro`); no tiene política de `mesa`. | Una solicitud no modifica ninguna de las tablas publicadas: hoy no existiría señal para Caja. |
| Seguridad | Contexto `obtener_contexto_autenticado()`; RPC `SECURITY DEFINER`, `search_path = pg_catalog`; tablas nuevas sin privilegios directos, revocadas también a `service_role` (E7-T10); conflictos funcionales con `PT409`, nunca `40001` (E1-R25). | La tabla y la RPC nuevas deben seguir la misma convención. |
| Plan E8 | “Tiempo desde entrega hasta pago” como una sola métrica. | Debe distinguir `ENTREGADO → SOLICITUD_CUENTA` y `SOLICITUD_CUENTA → PAGADO`. |

## 3. Actores y permisos

| Actor | Capacidades en E10 | Restricciones |
|---|---|---|
| `MOZO` | Solicita la cuenta total de un pedido `ENTREGADO` de su local; ve si el pedido y la mesa tienen una solicitud pendiente. | No cobra, no elige productos ni importes, no cierra ni borra solicitudes. |
| `CAJA` | Recibe y visualiza en tiempo real las solicitudes pendientes de su local; las atiende con el flujo de cobro existente. | No crea ni cierra solicitudes manualmente; no existe acción “tomar solicitud”. |
| `ADMINISTRADOR` | Sin capacidades nuevas. Su anulación E1 deja sin efecto una solicitud pendiente. | Consulta analítica de solicitudes queda para E8. |
| `COCINA` | Ninguna. | Sin lectura ni señales de solicitudes. |
| `anon` / otro local | Ninguna. | Sin lectura ni ejecución. |

## 4. Requisitos funcionales

### 4.1 Solicitud de cuenta por el mozo

| ID | Requisito | Prioridad |
|---|---|---|
| E10-R01 | El `MOZO` podrá solicitar la cuenta de un pedido de su local que esté `ENTREGADO` con la mesa `PENDIENTE_PAGO`, tenga o no cobros parciales previos. En cualquier otro estado la solicitud se rechaza. | Must |
| E10-R02 | La solicitud es siempre de **cuenta total** del pedido. No incluye selección de productos, cantidades, importes, división de cuenta, propinas ni medios de pago, y no modifica total, descuento, saldo ni ningún objeto financiero de E1. | Must |
| E10-R03 | Cada solicitud registrará como mínimo: pedido, local, fecha/hora de servidor de la solicitud y usuario `MOZO` que la realizó. La mesa se deriva del pedido (inmutable); ningún dato de identidad, local, mesa u hora se acepta desde el cliente. | Must |
| E10-R04 | Existirá como máximo **una solicitud pendiente por pedido**. Una repetición —doble clic, reintento tras timeout, segundo dispositivo del mismo mozo u otro mozo del local— devolverá la solicitud pendiente existente sin crear otra, sin cambiar su hora ni su autor e indicando que ya existía. | Must |
| E10-R05 | La decisión de aceptar o rechazar se tomará sobre el estado persistido en PostgreSQL al ejecutar. Pedido `PAGADO` o `ANULADO`, pedido no entregado (incluido uno reabierto) o mesa distinta de `PENDIENTE_PAGO` → conflicto funcional `PT409` sin efectos; sin autenticación, rol distinto de `MOZO` o pedido de otro local → `42501`. | Must |

### 4.2 Recepción y atención por Caja

| ID | Requisito | Prioridad |
|---|---|---|
| E10-R06 | `CAJA` verá, sin refrescar manualmente, las solicitudes pendientes de su local: mesa, pedido, hora de la solicitud, mozo solicitante y tiempo transcurrido. Los pedidos con solicitud pendiente se distinguirán visualmente y se priorizarán en la lista de pendientes por antigüedad de la solicitud; se mostrará el número de cuentas solicitadas. | Must |
| E10-R07 | Caja atenderá la solicitud con el flujo de cobro E1 vigente (precuenta, descuento autorizado, cobro total o parcial, N medios, propina, documentos). E10 no agrega una nueva operación de cobro, ni un paso “tomar/atender solicitud”, ni duplica lógica de pagos. | Must |
| E10-R08 | Un pedido `ENTREGADO` sin solicitud podrá cobrarse exactamente como hoy (DH-01, recomendada). La solicitud es un aviso y un dato de trazabilidad, no una precondición del cobro. | Must |

### 4.3 Ciclo de vida de la solicitud

| ID | Requisito | Prioridad |
|---|---|---|
| E10-R09 | La solicitud pendiente quedará **ATENDIDA** automáticamente, en la misma transacción, cuando el pedido pase de `ENTREGADO` a `PAGADO` por cualquier vía de cobro vigente, registrando fecha/hora de servidor y actor del cierre. Un cobro parcial que deja saldo no la cierra. | Must |
| E10-R10 | Si antes del primer pago el pedido se reabre (sale de `ENTREGADO` hacia el flujo operativo), la solicitud pendiente quedará **SIN_EFECTO** con motivo `REAPERTURA`, en la misma transacción. Tras la nueva entrega, el mozo podrá registrar una nueva solicitud; la anterior se conserva como trazabilidad. | Must |
| E10-R11 | Si el `ADMINISTRADOR` anula un pedido `ENTREGADO` con solicitud pendiente, la solicitud quedará **SIN_EFECTO** con motivo `ANULACION`, en la misma transacción. | Must |
| E10-R12 | Una solicitud sólo cambia una vez (de `PENDIENTE` a `ATENDIDA` o `SIN_EFECTO`). No admite borrado, reapertura ni edición posterior, y ningún cliente puede escribirla directamente. | Must |

### 4.4 Trazabilidad y preparación de datos para E8

| ID | Requisito | Prioridad |
|---|---|---|
| E10-R13 | Los datos persistidos permitirán que E8 calcule, sin reinterpretarlos, los intervalos: creación/envío (mozo); envío/recepción/preparación/listo (cocina, E7); listo → entregado (entrega del mozo); **entregado → solicitud** (tiempo del cliente, no atribuible a Caja); **solicitud → pago** (tiempo atribuible al proceso de Caja); creación → pago (total). E10 no calcula, persiste ni muestra métricas, tableros, rankings ni SLA. | Must |
| E10-R14 | No habrá backfill. Los pedidos anteriores a E10 y los pedidos pagados sin solicitud quedarán identificables como “sin solicitud registrada”, de modo que E8 no los mezcle con el tiempo atribuible a Caja. | Must |

### 4.5 Seguridad, Realtime, concurrencia e interfaz

| ID | Requisito | Prioridad |
|---|---|---|
| E10-R15 | Toda operación y lectura nueva validará en servidor identidad, perfil activo, rol y `local_id`. `anon`, `COCINA`, `ADMINISTRADOR` y otros locales no leen ni crean solicitudes. Conflictos funcionales con `PT409`; ninguna operación de E10 usa `40001`. | Must |
| E10-R16 | La solicitud y su cierre se reflejarán entre dispositivos (mozo ↔ caja, caja ↔ caja, mozo ↔ mozo) mediante Realtime como señal y recarga del snapshot autoritativo desde PostgreSQL, tolerando eventos duplicados, desordenados y reconexiones. No se introduce polling y se conserva la corrección E7-T12 (topic propio por suscripción). | Must |
| E10-R17 | Las carreras solicitud vs cobro, solicitud vs reapertura, solicitud vs anulación, solicitud vs solicitud y dos cajas sobre el mismo pedido se serializarán por pedido, sin interbloqueos, sin duplicados y sin estados parciales. | Must |
| E10-R18 | **UI del mozo (celular):** acción “Solicitar cuenta” visible sólo para pedidos `ENTREGADO`, protegida contra doble toque; estado “Cuenta solicitada · hh:mm” tras el éxito o si ya existía; indicador en la tarjeta de la mesa; aviso de que agregar productos deja la solicitud sin efecto. | Must |
| E10-R19 | **UI de Caja (PC/tablet):** indicador y prioridad de solicitudes pendientes (E10-R06) y datos de la solicitud en el panel del pedido seleccionado, sin nuevas acciones de cobro; anuncio accesible no intrusivo al llegar una solicitud nueva. | Must |
| E10-R20 | Objetivos táctiles ≥ 44 px y sin desplazamiento horizontal en celular, tablet vertical/horizontal y PC. | Must |
| E10-R21 | Los flujos aprobados de H3, H4, H5, H6, E1 y E7 continuarán funcionando exactamente como fueron aceptados, salvo las adiciones declaradas en este spec. | Must |
| E10-R22 | **(DH-02 = B, aprobada.)** La llegada o el cierre de una solicitud de **otro** pedido no descartará el borrador ni la confirmación de cobro en curso en Caja; un cambio del pedido seleccionado sí la invalida, como exige E1-R22. | Should |

## 5. Estados propios de la solicitud

No se agregan estados a `pedido`, `detalle_pedido` ni `mesa`. La solicitud tiene su propio ciclo:

| Estado | Significado | Transición |
|---|---|---|
| `PENDIENTE` | El cliente pidió la cuenta; Caja aún no completó el cobro. | Inicial, creada por `MOZO`. |
| `ATENDIDA` | El pedido quedó `PAGADO` (saldo 0). | `PENDIENTE → ATENDIDA`, automática en el cobro final. |
| `SIN_EFECTO` | La solicitud dejó de aplicar: `REAPERTURA` (el pedido volvió al flujo operativo antes del primer pago) o `ANULACION` (ADMIN anuló el pedido). | `PENDIENTE → SIN_EFECTO`, automática. |

`ATENDIDA` y `SIN_EFECTO` son terminales. Un pedido puede acumular varias solicitudes `SIN_EFECTO` y como máximo una `ATENDIDA`.

### 5.1 Matriz de solicitud según estado persistido

| Pedido / mesa | ¿Se puede solicitar? | Resultado |
|---|---|---|
| `ABIERTO`…`LISTO` | No | `PT409` “El pedido todavía no fue entregado”. |
| `ENTREGADO` / `PENDIENTE_PAGO`, sin solicitud pendiente | Sí | Nueva solicitud `PENDIENTE`. |
| `ENTREGADO` / `PENDIENTE_PAGO`, con solicitud pendiente | Sí (idempotente) | Devuelve la existente, `ya_existia = true`. |
| `ENTREGADO` con cobro parcial | Sí | Igual que las dos filas anteriores. |
| `PAGADO` o `ANULADO` | No | `PT409` “El pedido ya no está pendiente de pago”. |

## 6. Flujo funcional objetivo

```text
Pedido ENTREGADO / mesa PENDIENTE_PAGO          (historial_estado LISTO → ENTREGADO)
      ↓  cliente pide pagar
MOZO: Solicitar cuenta                           (solicitud PENDIENTE, solicitada_en/por)
      ↓  Realtime (señal) → refetch autoritativo
CAJA ve “Cuenta solicitada · Mesa X · hace N min”
      ↓  flujo de cobro E1 existente (precuenta, descuento, parciales, medios)
Saldo = 0 → pedido PAGADO, mesa LIBRE            (misma transacción del cobro)
Solicitud ATENDIDA (cerrada_en/por)              (misma transacción del cobro)
```

## 7. Concurrencia y reintentos relevantes

- Doble clic o reintento del mozo; dos dispositivos del mismo mozo; dos mozos: una sola solicitud pendiente (E10-R04).
- Solicitud vs cobro final: si la solicitud confirma primero, el cobro la deja `ATENDIDA` en su transacción; si el cobro confirma primero, la solicitud recibe `PT409` y el mozo vuelve a mesas con el flujo vigente de pedido no vigente (E7-T12).
- Solicitud vs reapertura: si la reapertura confirma primero, la solicitud recibe `PT409`; si la solicitud confirma primero, la reapertura la deja `SIN_EFECTO`.
- Solicitud vs anulación ADMIN: equivalente a la reapertura, con motivo `ANULACION`.
- Dos cajas observando la misma solicitud: ambas la ven; E1 garantiza un único cobro final; la otra caja resincroniza por la señal de `pedido` `PAGADO` y el servidor rechaza su intento con el conflicto E1 vigente.
- Pago realizado mientras llega o se procesa la señal Realtime: la señal sólo provoca un refetch; el snapshot autoritativo ya no muestra el pedido.

## 8. Restricciones

- No crear estados nuevos de `pedido`, `detalle_pedido` ni `mesa`.
- No implementar solicitud parcial, selección de productos o cantidades, nuevos mecanismos de división de cuenta ni propinas; no modificar el modelo financiero ni la lógica de cobro de E1.
- No implementar métricas, dashboards, rankings ni SLA de E8, ni capacidades de E9.
- No introducir polling, backend externo ni librerías nuevas; reutilizar Supabase/PostgreSQL/Realtime.
- No tocar PM-002 ni `mikuyapp-prod`.
- No modificar migraciones históricas ni la evidencia de E1/E7.

## 9. Alcance y fuera de alcance

**Dentro:** E10-R01–E10-R22 (R22 por DH-02 = B); ajuste documental de E8 en `PLAN_MVP.md`.

**Fuera:** solicitud parcial o por comensal; división de cuenta nueva; propinas nuevas; retiro o cancelación manual de una solicitud por el mozo (una solicitud por error se resuelve con el cobro o la reapertura); acción “Caja toma la solicitud” (ver `design.md` E10-D10); avisos sonoros o notificaciones push; reasignación o traslado de mesa; métricas, tableros e históricos (E8); jornada operativa (E9); multirol/multilocal (E6); lectura de solicitudes por `ADMINISTRADOR` (E8); corrección general de la señal de Caja ante reaperturas (HZ-02); cambios de PM-002.

## 10. Decisiones humanas (resueltas)

Resueltas por el responsable el 30/09/2026 al aprobar el spec: **DH-01 = A** (el cobro no exige solicitud previa) y **DH-02 = B** (invalidación acotada al pedido seleccionado). No quedan decisiones pendientes para construir.

| ID | Decisión | Opciones | Recomendación e impacto |
|---|---|---|---|
| DH-01 | ¿El cobro exige una solicitud previa? | **A. No (recomendada):** la solicitud es aviso y traza; el cobro E1 no cambia. **B. Sí:** Caja sólo cobra pedidos con solicitud pendiente. | **A.** No toca ninguna RPC de cobro ni las vías históricas; no bloquea al cliente que paga directamente en caja. B obligaría a modificar `rpc_registrar_cobro_pedido` y las vías históricas de pago (lógica E1), agregaría un paso obligatorio al mozo y un nuevo conflicto funcional en Caja (+2–3 h y regresión E1 ampliada). Con A, E8 trata los pedidos pagados sin solicitud como no desagregables (E10-R14). |
| DH-02 | ¿Una señal de otro pedido debe descartar el borrador de cobro en curso? (HZ-01) | **A. Mantener E1:** todo refresco descarta borrador y confirmación. **B. Acotar (recomendada):** sólo se invalida si cambió el snapshot autoritativo del pedido seleccionado (estado, total, descuento, pagado o saldo) o si desapareció. | **B.** E10 agrega una señal frecuente (una por mesa que pide la cuenta), justo mientras Caja cobra otras mesas; con A cada solicitud borraría medios e importes que el cajero está digitando. B conserva la regla E1-R22 (una confirmación obsoleta se invalida) y sólo cambia `CashierPage` (+0.75 h). Con A, E10-R22 se elimina. |

Decisión analizada y **no** pendiente: no se registra un “comienzo de atención” de Caja; `solicitada_en → pago` basta para la métrica objetivo (`design.md` E10-D10).

## 11. Hallazgos y contradicciones detectados en la inspección

| ID | Hallazgo | Tratamiento |
|---|---|---|
| HZ-01 | `CashierPage.refresh` ejecuta `clearPaymentOptions()` en cada refresco, incluido el disparado por Realtime: cualquier señal visible para Caja (hoy, la entrega o el cobro de **otro** pedido) descarta medios, importes y confirmación en curso. E10 agrega una nueva fuente de señales. | Decisión DH-02. Recomendado: acotar la invalidación al pedido seleccionado. |
| HZ-02 | Inspección estática: la política `pedido_select_caja_local_cobro` sólo expone a `CAJA` pedidos `ENTREGADO`/`PAGADO` y `CAJA` no tiene política sobre `mesa`. Cuando un pedido `ENTREGADO` se reabre (`→ ABIERTO`), la fila nueva no es visible para Caja y, según la semántica de Realtime (evaluación RLS del registro nuevo), Caja no recibiría señal: su lista queda desactualizada hasta la siguiente señal; si intenta cobrar recibe el `PT409` E1 vigente. | Comportamiento heredado de H5, fuera de alcance. E10 lo mitiga sólo para pedidos con solicitud pendiente (la solicitud `SIN_EFECTO` es visible para Caja y produce señal). Confirmar en E10-T06 y registrar; no se corrige en E10. |
| HZ-03 | `PLAN_MVP.md` §4.8 (MVP histórico) declara que Realtime usa `detalle_pedido`, `pedido` y `mesa`; PM-002 (`PM002_T10_EXECUTION.md`) y la prueba `supabase/tests/h4_t05_realtime_publication_rls.sql` esperan exactamente esas tres tablas. | No contradice una decisión vigente: §4 es histórica y E1-D11 ya previó publicar tablas con RLS sin importes. E10 publica `solicitud_cuenta` (sin datos financieros). La aserción de `h4_t05` queda superada y se homologa sin editar evidencia histórica; PM-002 deberá esperar cuatro tablas en su próxima revalidación (dependencia, sin modificar PM-002). |
| HZ-04 | `pedido.modificado_en/por` tiene semántica “pendiente de decisión” (comentario DBSTD) y alimenta `ultima_actualizacion_en` de E1-T17. | Por eso E10 no usa esas columnas como señal (alternativa descartada en E10-D07). |
| HZ-05 | Además de `rpc_registrar_cobro_pedido`, siguen ejecutables por `authenticated` `registrar_pago_pedido`, `rpc_registrar_pago_total_pedido` y `rpc_registrar_pago_pedido_v2`, todas capaces de dejar un pedido `PAGADO`. | El cierre de la solicitud se implementa sobre la transición de `pedido` y no dentro de una RPC concreta, para cubrir todas las vías sin modificarlas (E10-D05). |
| HZ-06 | `PLAN_MVP.md` E8 incluye “Tiempo desde entrega hasta pago” como métrica única. | Ajuste documental mínimo en este Spec Mode (sección E8 del plan). |

## 12. Condición de construcción y cierre

- Spec y DH-01/DH-02 aprobados el 30/09/2026; la construcción puede iniciar en E10-T02.
- Construcción con pruebas focalizadas por tarea y validación integral única en la fase final (mismo modelo de E7).
- E10 sólo podrá cerrarse después de construcción, ejecución completa del plan de pruebas, pruebas humanas y creación/aprobación posterior de `acceptance.md`.

## 13. Trazabilidad

La matriz `Requirement → Design → Task → Test` se mantiene en `tasks.md` (sección 5). Cada requisito E10-R01–E10-R22 tiene al menos una decisión E10-Dxx, una tarea E10-Txx y un escenario E10-TPxx/E10-THxx.
