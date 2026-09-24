# MikuyApp — Evolución 7 — Mejoras operativas de pedidos: plan de pruebas

**Estado: SPEC MODE — BORRADOR PENDIENTE DE APROBACIÓN.** Ninguna prueba de este plan se ha ejecutado. No se crea `acceptance.md`.

## 1. Estrategia

La experiencia de E1 mostró que ejecutar repetidamente la suite completa después de cada tarea consumía una parte desproporcionada del tiempo de construcción. E7 separa explícitamente dos momentos:

1. **Construcción (E7-T02–E7-T10):** cada tarea ejecuta **sólo** las verificaciones focalizadas que confirman que su cambio funciona y que es seguro continuar (sección 2).
2. **Fase final (E7-T11):** se ejecuta **una vez** todo este plan: suite automatizada completa, regresión H3/H4/H5/E1, replay limpio de migraciones, pruebas SQL integrales, seguridad, `typecheck` y `build`. Después, E7-T12 ejecuta las pruebas humanas.

Reglas obligatorias durante la construcción:

- Si se modifica una RPC, se ejecutan las pruebas SQL específicas de esa RPC.
- Si se crea o modifica una migración, se valida que aplica sobre la baseline local vigente (sin replay completo desde cero).
- Si se modifica un componente o servicio frontend, se ejecuta sólo su prueba Node focalizada (`node --experimental-strip-types --test tests/<archivo>.test.mjs`).
- Si se modifica una transición crítica, se prueba específicamente esa transición (incluida la carrera si el caso la exige).
- **No** se exige tras cada tarea: suite Node completa, toda la regresión, todos los tests SQL, `build` repetido, todas las pruebas de seguridad ni la matriz histórica.
- Un cambio exclusivamente SQL no obliga a ejecutar `typecheck`/`build`; un cambio exclusivamente de UI no obliga a repetir SQL.
- Una prueba aprobada no se repite en la misma tarea salvo que un cambio posterior pueda invalidarla.
- **Defectos bloqueantes** (impiden continuar o invalidan una invariante) se corrigen inmediatamente dentro de la tarea.
- **Defectos no bloqueantes** se registran en la evidencia de la tarea y deben resolverse antes del cierre de E7.

Esto no reduce la cobertura: sólo cambia el momento de la validación integral. E7 no puede cerrarse con pruebas pendientes, y las pruebas automatizadas no sustituyen la validación humana.

### Ambientes y datos

- Local aislado con la baseline de migraciones vigente (hasta `20260922000100`) y `supabase/seed.sql`; luego DEV/Preview conforme a PM-002 `TRANSITIONING`. Nunca PROD.
- Fixtures SQL dentro de transacción con `ROLLBACK` o limpieza verificable, siguiendo el patrón `set_config('request.jwt.claim.sub', …)` de `supabase/tests/`.
- Usuarios activos `ADMINISTRADOR`, `MOZO`, `COCINA`, `CAJA` en dos locales; productos con y sin cocina (p. ej. “Ceviche clásico” con cocina, “Chicha morada” sin cocina).
- Carreras con conexiones independientes, siguiendo los scripts `*_concurrency_setup/call/verify/cleanup.sql` existentes.
- Dos dispositivos o navegadores para Realtime; para las pruebas humanas de impresión, la impresora que el sistema operativo del dispositivo `COCINA` tenga accesible y configurada (DH-02).

## 2. Verificaciones focalizadas por tarea (construcción)

Cada tarea ejecuta sólo la **parte** de los escenarios indicada, en el nivel indicado (SQL focal o prueba Node focal). Los escenarios completos se ejecutan una única vez en E7-T11.

| Tarea | Verificación focalizada mínima | No requerido en la tarea |
|---|---|---|
| E7-T02 | Migración aplica sobre la baseline local; consultas de catálogo de checks, FKs, índices, triggers y grants de objetos nuevos. Partes estructurales de TP02, TP21 y TP26. | Replay completo, Node, build. |
| E7-T03 | SQL de `agregar_detalle_pedido` y `enviar_pedido_cocina`: TP03 (snapshot/consolidación), partes SQL de TP05 y TP06, TP22, parte `ENVIO` de TP20. | Cocina, cancelación, UI. |
| E7-T04 | SQL de tablero y recepción: TP08, parte SQL de TP09, parte de tablero de TP05; carrera real TP10 (dos recepciones); `PT409` de detalle inexistente. | Suite H4 completa. |
| E7-T05 | SQL de cancelación: TP14–TP17; carrera real TP18 (cancelación vs `EN_PREPARACION`); parte `CANCELACION` de TP20. | Impresión, UI. |
| E7-T05B | SQL de edición/retiro: TP11, TP12; carrera real TP13 (retiro vs envío); prueba Node focal del servicio del mozo para edición/retiro. | Resto de H3. |
| E7-T06 | `tests/productAdministration.test.mjs`, `tests/catalogService.test.mjs`; parte UI de TP01. | SQL, build. |
| E7-T07 | `tests/waiterBoard.test.mjs`, `tests/waiterRealtime.test.mjs`: indicador sin cocina, cancelación, “Cancelados” (parte mozo de TP19). | Suite completa. |
| E7-T08 | `tests/kitchenBoard.test.mjs`, `tests/kitchenRealtimeService.test.mjs`: snapshot unificado, guard de recepción (parte UI de TP09), conflicto tras cancelación, parte cocina de TP19. | Suite completa. |
| E7-T09 | SQL de `rpc_registrar_impresion_comanda` (TP23, parte SQL de TP24, parte comanda de TP21); prueba Node del componente de comanda (acciones `Imprimir`/`Reimprimir`, “COPIA n”, líneas canceladas). | Impresión física (queda para humanas). |
| E7-T10 | Integración local → DEV: un recorrido de TP06, TP07 y TP27 entre dos dispositivos; replay de las migraciones E7 sobre la baseline. | Matriz completa (queda para T11). |

## 3. Escenarios técnicos finales (E7-T11)

Los escenarios agrupan variantes relacionadas. Cada fila enumera todas las validaciones que deben comprobarse; ninguna validación del borrador anterior se eliminó, sólo se agruparon.

### 3.1 Catálogo y snapshot

| ID | Requisitos | Escenario | Validaciones |
|---|---|---|---|
| E7-TP01 | R01, R21, R29 | Configuración de la condición de cocina y privilegios. | ADMIN crea sin indicar (default `true`), crea “sin cocina”, edita un existente y lo ve en la carta administrativa; `MOZO`, `COCINA`, `CAJA`, `anon` y ADMIN de otro local no pueden modificar `requiere_cocina`. |
| E7-TP02 | R02, R21 | Migración y coherencia estructural. | Backfill `true` en todos los detalles existentes; `ck_detalle_pedido_sin_cocina_estado` validado y rechaza un detalle sin cocina en estado de cocina; FKs/índices/checks de tablas nuevas. |
| E7-TP03 | R02, R03 | Snapshot, consolidación y cambios de catálogo. | El detalle copia la condición al crearse; mismo producto/observación con condiciones distintas no se consolida; producto con cocina → sin cocina con detalles `ENVIADO`/`EN_PREPARACION` que siguen en cocina; sin cocina → con cocina con detalles `LISTO` que no aparecen en cocina; cambio mientras está `ABIERTO` respeta el snapshot de creación al enviar; nuevos agregados usan la condición nueva. |

### 3.2 Flujos de pedido

| ID | Requisitos | Escenario | Validaciones |
|---|---|---|---|
| E7-TP04 | R31 | Pedido sólo con productos de cocina hasta el cobro. | Uno y varios productos (observaciones distintas) recorren `ENVIADO → RECIBIDO_COCINA → EN_PREPARACION → LISTO` individualmente; agregado correcto en cada paso; pedido `LISTO`/mesa `PEDIDO_LISTO`; comanda 1; entrega, cobro, `PAGADO` y mesa `LIBRE` sin cambios H5/E1. |
| E7-TP05 | R04, R05, R08 | Pedido sólo con productos sin cocina hasta el cobro. | Envío deja detalles `LISTO` con `enviado_en`; historial de cabecera `ABIERTO → LISTO` una vez; mesa `PEDIDO_LISTO`; sin comanda; ausente en tablero nuevo y legado; recepción completa no lo procesa; transición de cocina rechazada; entrega y cobro funcionan. |
| E7-TP06 | R06, R07, R08, R23 | Pedido mixto ceviche + bebida. | Tras el envío ceviche `ENVIADO`, bebida `LISTO`, pedido `ENVIADO`, mesa `OCUPADA`; comanda sólo con el ceviche; pedido `LISTO`/`PEDIDO_LISTO` sólo cuando el ceviche termina; el mozo ve la bebida identificada como sin cocina en la carta y el pedido y, tras el envío, como lista para servir. |
| E7-TP07 | R08, R24 | Reapertura de pedido `ENTREGADO` con productos nuevos. | Nueva bebida: reapertura H5 y tras el envío `LISTO`/`PEDIDO_LISTO`, nueva entrega, sin comanda; nuevo ceviche + bebida: ceviche en cocina, bebida `LISTO`, comanda 2 sólo con el ceviche, nueva entrega al terminar. |

### 3.3 Recepción completa

| ID | Requisitos | Escenario | Validaciones |
|---|---|---|---|
| E7-TP08 | R05, R09, R10, R19 | Recepción completa con combinaciones de estados. | Varios `ENVIADO` pasan juntos a `RECIBIDO_COCINA` en una transacción con historial `RECEPCION_COMPLETA`; con `RECIBIDO_COCINA`, `EN_PREPARACION` y `LISTO` presentes sólo cambia el `ENVIADO`, nada retrocede; bebidas `LISTO` no se procesan ni registran; después cada detalle avanza individualmente como en H4. |
| E7-TP09 | R11, R22, R29 | Doble clic, reintento y validaciones. | Guard de UI: una sola solicitud y botones del grupo deshabilitados; reintento tras éxito devuelve 0 recibidos sin historial ni derivación duplicados y sin `40001`; pedido `ENTREGADO`/`PAGADO`/`ANULADO` → `PT409`; otro local o rol distinto de `COCINA` → `42501`, sin cambios. |
| E7-TP10 | R09, R11, R15 | Concurrencia de la recepción completa (conexiones reales). | Dos sesiones `COCINA` simultáneas: una procesa N, la otra 0, historial con exactamente N filas; vs transición individual del mismo detalle: un solo cambio (la perdedora `PT409` o la completa lo omite); vs nuevo envío del mozo: resultado coherente según orden; sin conexiones residuales. |

### 3.4 Edición y retiro de detalles `ABIERTO` (HZ-01)

| ID | Requisitos | Escenario | Validaciones |
|---|---|---|---|
| E7-TP11 | R33, R31 | Edición vía RPC con semántica H3. | Cantidad y observación se actualizan; cantidad < 1 o no entera → `22023`; observación vacía → sin observación; valores esperados obsoletos o detalle ya enviado → `PT409` sin cambios; no consolida con otra línea; total recalculado desde persistencia; auditoría `pedido.modificado_*` igual que H3; `UPDATE` directo del cliente denegado. |
| E7-TP12 | R32, R33, R31 | Retiro vía RPC y corrección HZ-01. | Retiro normal de un borrador; detalle inexistente o enviado → `PT409`; `DELETE` directo del cliente denegado; retiro del último detalle deja `ABIERTO` vacío/`OCUPADA` y `liberar_mesa_pedido_vacio` funciona; reproducción de HZ-01: pedido `ENTREGADO` reabierto cuyo producto nuevo se retira vuelve a `LISTO`/`PEDIDO_LISTO` y puede entregarse; pedido con otros detalles enviados queda con la cabecera derivada correcta. |
| E7-TP13 | R32, R33 | Concurrencia edición/retiro vs envío (conexiones reales). | Retiro vs envío y edición vs envío del mismo pedido en ambos órdenes: serialización sin interbloqueo (`40P01`), sin estados inconsistentes; el perdedor recibe `PT409` o procesa el estado resultante. |

### 3.5 Cancelación

| ID | Requisitos | Escenario | Validaciones |
|---|---|---|---|
| E7-TP14 | R12–R14, R19 | Cancelación permitida con recálculo y trazabilidad. | Cancelar `ENVIADO` y `RECIBIDO_COCINA` con motivo; línea con cantidad > 1 se cancela completa (DH-04); evento `CANCELACION` con pedido, detalle, producto, cantidad, precio, observación, estado anterior, motivo, actor y hora; total excluido en mozo, precuenta y lecturas de caja; pedido mixto cuyo único detalle de cocina pendiente se cancela queda `LISTO`/`PEDIDO_LISTO` y entregable. |
| E7-TP15 | R12, R13, R18 | Cancelaciones rechazadas. | `EN_PREPARACION` y `LISTO` → `PT409`; `ABIERTO` → `PT409` indicando retirar; bebida sin cocina enviada (`LISTO`) rechazada (DH-03); motivo nulo, vacío o excesivo → `22023`; pedido `PAGADO`, `ANULADO` o con pago parcial rechazado; ningún cambio en todos los casos. |
| E7-TP16 | R14 | Cancelación del último detalle. | Pedido `ABIERTO` vacío con historial, mesa `OCUPADA`; `liberar_mesa_pedido_vacio` y agregar productos funcionan. |
| E7-TP17 | R16 | Reintento de cancelación. | Mismo resultado con `ya_cancelado = true`; sin segundo evento ni recálculo. |
| E7-TP18 | R15, R18 | Concurrencia de la cancelación (conexiones reales). | Mozo cancela `RECIBIDO_COCINA` mientras cocina lo pasa a `EN_PREPARACION`, en ambos órdenes: exactamente una confirma, la otra `PT409`, sin efectos parciales, historial coherente; anulación ADMIN E1 en carrera: si gana, la cancelación falla sin estados inconsistentes. |
| E7-TP19 | R17 | Visibilidad de cancelaciones. | Cocina ve el producto cancelado dentro del grupo o como grupo de sólo lectura; el mozo ve la sección “Cancelados” de su pedido. |

### 3.6 Trazabilidad

| ID | Requisitos | Escenario | Validaciones |
|---|---|---|---|
| E7-TP20 | R19, R20 | Historial completo de un recorrido. | Envío con/sin cocina, transición individual, recepción completa y cancelación generan una fila por transición real con operación `ENVIO`, `TRANSICION_COCINA`, `RECEPCION_COMPLETA` o `CANCELACION` y actor correcto; `historial_estado` sólo con cambios reales de cabecera, sin duplicados. |
| E7-TP21 | R19, R21, R23 | Inmutabilidad de historial y comanda. | `INSERT`/`UPDATE`/`DELETE` directos sobre `historial_detalle_pedido` y `comanda` rechazados por privilegios y triggers; `lineas` de comanda no modificables. |

### 3.7 Comandas

| ID | Requisitos | Escenario | Validaciones |
|---|---|---|---|
| E7-TP22 | R23, R24 | Generación y numeración. | Primer envío con dos productos de cocina y una bebida → comanda 1 sólo con las líneas de cocina, mesa, mozo y hora; envío posterior → comanda 2 sólo con líneas nuevas; envío repetido sin `ABIERTO` o sólo de bebidas → sin comanda. |
| E7-TP23 | R25–R27 | Imprimir, deduplicar y reimprimir. | Cada comanda ofrece `Imprimir` (marcada “Sin imprimir”) y `Reimprimir`; la primera solicitud de impresión registra `primera_impresion_*` e `impresiones = 1`; una segunda solicitud de primera impresión desde otra sesión → `PT409` y ofrece reimprimir; dos reimpresiones → `impresiones = 3`, `ultima_impresion_*` y “COPIA n”; reimpresión con línea cancelada la marca “CANCELADO”. |
| E7-TP24 | R28 | Impresión sin efecto en el flujo digital. | Estados de detalle/pedido/mesa idénticos antes y después de imprimir; impresora no disponible o diálogo cancelado: documento visible, estados intactos, reimpresión posible. |

### 3.8 Seguridad

| ID | Requisitos | Escenario | Validaciones |
|---|---|---|---|
| E7-TP25 | R29 | Aislamiento por local y matriz rol × operación. | Todas las RPC y lecturas nuevas con otro local → `42501`/sin datos; `MOZO` no recibe ni imprime; `COCINA` no cancela, no edita ni retira; `CAJA` y `ADMINISTRADOR` no reciben, cancelan, editan, retiran ni imprimen (ADMIN sólo configura productos); `anon` sin acceso. |
| E7-TP26 | R21, R22, R29 | Catálogo de seguridad y escrituras directas. | Funciones nuevas/modificadas `SECURITY DEFINER`, owner `postgres`, `search_path = pg_catalog`, `EXECUTE` sólo `authenticated`; triggers sin `EXECUTE`; RLS habilitado y sin grants directos en tablas nuevas; `authenticated` sin `UPDATE`/`DELETE` sobre `detalle_pedido` y sin las dos políticas eliminadas; cliente no puede cambiar `estado`, `requiere_cocina`, historial ni comanda; ninguna aparición manual de `40001` en funciones/triggers vigentes. |

### 3.9 Realtime

| ID | Requisitos | Escenario | Validaciones |
|---|---|---|---|
| E7-TP27 | R30 | Reflejo entre dispositivos. | Mozo/cocina en dos dispositivos: envío mixto, envío sólo bebidas, recepción completa, edición/retiro y cancelación se reflejan sin refresco manual; cocina nunca muestra bebidas; la cancelación llega por la señal `UPDATE` de `pedido` y aparece en “Cancelados”. |
| E7-TP28 | R30 | Robustez de la sincronización. | Eventos duplicados o fuera de orden no duplican tarjetas; pérdida de red y reconexión durante una cancelación resincronizan al snapshot autoritativo. |

### 3.10 Regresión y validación integral

| ID | Requisitos | Escenario | Validaciones |
|---|---|---|---|
| E7-TP29 | R10, R31 | Regresión H3 y H4. | Suites SQL `h3_*`, `order_audit_trail`, `release_empty_order_table`, `h4_*` y pruebas Node de mozo/cocina aprobadas sin editar evidencia histórica; las aserciones de `h3_t04` sobre grants/políticas de mutación directa se documentan como superadas por E7-D15 y quedan cubiertas por TP11/TP12/TP26. |
| E7-TP30 | R18, R31 | Regresión H5 y E1 con interacción indirecta. | Suites `h5_*`, `e1_delta_t09`, `e1_t07`, `e1_t10`, `e1_t16` y Node de caja/impresión/Inicio/Pedidos ADMIN aprobadas: entrega, reapertura, cobro, precuenta/ticket, anulación, flujo actual y bloqueo por pago coherentes con pedidos sin cocina, cancelaciones y edición/retiro vía RPC. |
| E7-TP31 | Todos | Ejecución integral. | Replay limpio de todas las migraciones + seed; todos los SQL de `supabase/tests/` y de E7; suite Node completa; `npm run typecheck`; `npm run build` (limitaciones ambientales documentadas como en E1-TP65); sin conexiones residuales. |

## 4. Pruebas humanas (E7-T12, después de T11)

| ID | Caso | Resultado esperado |
|---|---|---|
| E7-TH01 | ADMIN configura productos con y sin cocina desde celular y PC. | Configuración clara y persistida. |
| E7-TH02 | Mozo registra un pedido mixto en celular, edita y retira borradores y distingue productos sin cocina. | Pedido comprensible; edición/retiro iguales a H3; bebida lista al enviar. |
| E7-TH03 | Cocina en tablet: recibir pedido completo y continuar individualmente; doble toque. | Una sola recepción; flujo individual intacto. |
| E7-TH04 | Mozo cancela un producto recibido mientras cocina opera en otra tablet; intento sobre producto en preparación. | Cocina ve la cancelación; bloqueo comprensible. |
| E7-TH05 | Impresión real de comanda desde el dispositivo `COCINA` con la impresora configurada en su sistema operativo: primera impresión, nuevos productos, reimpresión e impresora apagada. | Compatibilidad física confirmada; papel legible de 80 mm; copia identificada; flujo digital sin bloqueo. |
| E7-TH06 | Flujo completo mixto hasta entrega y cobro en caja. | Sin regresiones visibles. |
| E7-TH07 | Uso táctil y responsive en celular, tablet vertical/horizontal y PC. | Objetivos ≥ 44 px; sin scroll horizontal. |

## 5. Criterios de salida

- TP01–TP31 aprobados y TH01–TH07 aprobadas humanamente.
- Ningún defecto bloqueante abierto; defectos no bloqueantes resueltos o aceptados explícitamente por el responsable.
- Evidencia registrada por tarea y de la fase final.
- Sólo después: elaboración y aprobación de `acceptance.md`.
