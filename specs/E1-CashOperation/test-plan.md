# MikuyApp — Evolución 1 — Operación de caja: plan de pruebas

## 1. Estrategia y ambientes

La validación de E1 combinó pruebas SQL transaccionales, Node/React, concurrencia en sesiones independientes, control de acceso con usuarios reales por rol, regresión integral y validación humana. PostgreSQL actuó como autoridad de montos y estados. Cada caso financiero verificó datos persistidos, auditoría y ausencia de efectos parciales.

Mientras PM-002 permanezca `TRANSITIONING`, las pruebas se ejecutarán primero en local/DEV y deployment Preview dirigido a DEV. Este plan no autoriza tocar PROD, Cloudflare Production, variables, datos ni completar PM-002.

### Validación incremental de construcción

La matriz TP01–TP64 permanece íntegra. Durante T03–T12 se ejecutan los TP propios de la tarea y sólo las regresiones directamente afectadas por los archivos, esquema o contratos modificados. Una prueba aprobada no se repite en la misma tarea salvo que un cambio posterior pueda invalidarla, haya requerido una corrección o sea necesaria para comprobar una interacción nueva.

- No se ejecuta automáticamente la suite Node completa tras cada tarea.
- Un cambio exclusivamente SQL no obliga automáticamente a repetir `typecheck` o `build`.
- Las carreras usan conexiones independientes sólo cuando este plan las exige explícitamente para la tarea.
- Los fingerprints completos de datos legacy sólo se repiten cuando la tarea altera datos, esquema o contrato legacy.
- Las comprobaciones incrementales reutilizan una baseline local validada; el replay limpio completo se reserva para migraciones que lo requieran y checkpoints.
- La evidencia original de T08 conserva estructura/compatibilidad legacy de `pago`; el delta T09 revalida sólo los invariantes afectados por `cobro_id` y la agrupación de medios, y vuelve a ser checkpoint ampliado del núcleo financiero.
- T13 mantiene la puerta integral definitiva con TP01–TP61, SQL, seguridad, concurrencia, regresión H1–H6/PM-001, `typecheck` y `build`.

## 2. Matriz de pruebas técnicas

### Apertura, sesión y permisos

| ID | Requisitos | Caso | Resultado esperado |
|---|---|---|---|
| E1-TP01 | R01 | Caja física vs sesión. | Varias sesiones históricas pertenecen a una caja; sólo una puede estar abierta. |
| E1-TP02 | R01–R03/R23 | Apertura normal con monto inicial cero/positivo. | Sesión abierta con actor/local/hora servidor y auditoría; cada `ADMINISTRADOR` activo del mismo local recibe una sola notificación informativa con caja, actor, hora y monto inicial. |
| E1-TP03 | R02 | Doble apertura secuencial. | La segunda apertura sobre la misma caja devuelve el snapshot autorizado de la sesión vigente, sin error funcional, sin insertar otra sesión y sin alterar `abierta_por`. |
| E1-TP04 | R02 | Doble apertura concurrente. | Sólo una llamada crea la sesión; la otra recupera esa misma sesión. Ambas observan el mismo `sesion_caja.id` y queda exactamente una `ABIERTA`. La RPC resuelve de forma segura cualquier conflicto interno `23505`, sin exponerlo como resultado funcional normal; la restricción única parcial permanece como defensa final. |
| E1-TP05 | R01–R03 | Cajero B accede a la caja con sesión abierta por Cajero A. | Recupera y continúa la misma sesión sin cierre ni arqueo; `abierta_por` permanece Cajero A. |
| E1-TP06 | R02–R03/R23 | Reintento con misma idempotencia tras timeout. | Devuelve la misma apertura; no duplica auditoría, notificación ni destinatarios. |
| E1-TP07 | R02 | Monto inicial negativo/null/NaN conceptual. | Rechazo servidor sin cambios. |
| E1-TP08 | R01–R04 | Operación sobre sesión cerrada, otra caja, caja inactiva u otro local. | Rechazo servidor sin cambios ni filtración de datos. |
| E1-TP09 | R03–R06/R19 | Cajeros A y B alternan pagos, entradas y salidas en la misma sesión. | Cada operación persiste su actor real; `abierta_por` no cambia. |
| E1-TP10 | R03/R06/R23 | Cajero B cierra la sesión abierta por Cajero A. | Cierre válido sin arqueo intermedio; quedan trazados `abierta_por=A` y `cerrada_por=B` con sus fechas, y la notificación identifica a B como actor del cierre. |
| E1-TP11 | R08 | Histórico por `CAJA` y `ADMINISTRADOR`. | Sólo sesiones del local autorizado, con actores por operación y apertura/cierre. |
| E1-TP12 | R01–R08 | `MOZO`, `COCINA`, `anon` o perfil/rol/local inactivo ejecutan RPC/SELECT. | Denegado por grants/RLS y validación interna. |

### Movimientos y cierre

| ID | Requisitos | Caso | Resultado esperado |
|---|---|---|---|
| E1-TP13 | R04 | Entrada manual normal y lote de una fila. | Evento positivo, motivo, actor/hora/sesión y auditoría; lectura autorizada devuelve actor_nombre y orden cronológico. |
| E1-TP14 | R04 | **Salida de caja** y lote mixto de varias entradas/salidas. | Cada fila explícita queda trazable; el lote completo actualiza esperado con la fórmula vigente. |
| E1-TP15 | R04 | Importe cero/negativo, motivo vacío, sesión cerrada o una fila inválida dentro del lote. | Rechazo atómico: cero movimientos, auditorías o cabecera idempotente parcial. |
| E1-TP16 | R04–R05 | Entradas/salidas concurrentes, reintento del lote y reutilización conflictiva de clave. | Todos los eventos válidos se suman una vez; misma clave/datos retorna el lote original y otros datos se rechazan. |
| E1-TP17 | R05–R07/R23 | Cierre correcto sin diferencia. | El primer clic no muta; resumen previo muestra componentes, `contado - esperado = 0` y no exige motivo. Sólo confirmar ejecuta una vez la RPC; la sesión queda cerrada, el reporte posterior usa el snapshot persistido y cada administrador activo del local recibe una sola notificación informativa con diferencia cero. |
| E1-TP18 | R05–R07/R23 | Diferencia, Volver, doble cierre y cierre vs cobro/movimiento. | Diferencia visible; motivo obligatorio si es distinta de cero; la UI avisa que se notificará al administrador, pero no exige aprobación. Volver no muta ni notifica; sólo un cierre/notificación. La alerta contiene esperado, contado, diferencia y motivo. El reporte interno conserva actores/fechas/importes del snapshot y permite impresión manual de 80 mm, no fiscal. La carrera cierre-vs-cobro se ejecuta en T05 después de T08. |

### Descuentos y anulaciones

| ID | Requisitos | Caso | Resultado esperado |
|---|---|---|---|
| E1-TP19 | R09–R10 | Descuento autorizado por importe y resolución autoritativa DT-01. | `descuento_pedido` conserva el snapshot; `pedido` no duplica campos de subtotal/descuento/neto; la función PostgreSQL devuelve subtotal, descuento aplicado, total neto y actores correctos. |
| E1-TP20 | R09–R10 | Descuento autorizado por porcentaje. | Redondeo monetario definido y total servidor correcto. |
| E1-TP21 | R09 | `CAJA` intenta autoautorizar o rol no autorizado aplica. | Denegado; frontend no basta para elevar permiso. |
| E1-TP22 | R09–R10 | Motivo vacío, descuento cero/negativo/excesivo o ambos tipos. | Rechazo sin cambios. |
| E1-TP23 | R09–R10 | Descuento después del primer pago. | Rechazo; total histórico/pagos inmutables. |
| E1-TP24 | R09–R10 | Descuento y cobro concurrentes. | Locks serializan; cobro usa descuento confirmado o una operación falla limpiamente. |
| E1-TP25 | R09–R10 | Reintento de autorización. | Un snapshot/evento; sin doble descuento. |
| E1-TP26 | R11 | `ADMINISTRADOR` anula directamente un pedido sin pagos y con motivo. | Pedido `ANULADO`, mesa consistente, actor administrador, fecha/hora y estado anterior/nuevo; sin solicitante/autorizador separados. |
| E1-TP27 | R11 | Anulación sin pagos en cada estado del pedido. | `ABIERTO`, `ENVIADO`, `RECIBIDO_COCINA`, `EN_PREPARACION`, `LISTO` y `ENTREGADO` se anulan; `PAGADO` y `ANULADO` se bloquean. La advertencia futura para `EN_PREPARACION`, `LISTO` y `ENTREGADO` no altera la autorización PostgreSQL; nunca hay transición silenciosa. |
| E1-TP28 | R12 | Anulación con cualquier pago parcial o pedido `PAGADO`. | Bloqueada por regla definitiva; pagos intactos y sin evento de anulación. |
| E1-TP29 | R11–R12 | Anulación vs cobro simultáneo. | Sólo un resultado coherente; no pedido anulado con pago inesperado. |
| E1-TP30 | R11–R12 | Pedido `ANULADO`/`PAGADO` recibe mutaciones H3–H5. | Terminalidad existente conservada. |

### División, pagos y propinas

| ID | Requisitos | Caso | Resultado esperado |
|---|---|---|---|
| E1-TP31 | R13–R16 | Migración de pago legacy. | Filas/importes/medios/usuarios/fechas preservados; legacy identificable sin sesión inventada. |
| E1-TP32 | R13–R16 | Cobro total con un solo medio (regresión H5). | Una cabecera, una línea, una auditoría/documento lógico; pedido `PAGADO`, historial único y mesa `LIBRE`. |
| E1-TP33 | R13–R16 | Un cobro total `EFECTIVO + YAPE`. | Dos líneas pertenecen al mismo `cobro`; una confirmación atómica completa el saldo, genera un documento y libera la mesa. |
| E1-TP34 | R13–R16 | Un cobro total `YAPE + YAPE`. | El medio repetido es válido; dos líneas comparten cabecera y la suma exacta completa el pedido en un solo acto. |
| E1-TP35 | R13 | División por selección de productos. | UI calcula importe; servidor valida monto, sin mover/duplicar detalles. |
| E1-TP36 | R13–R16 | Un cobro con tres o más líneas `EFECTIVO + YAPE + TARJETA + TARJETA`, incluyendo redondeo. | Medios distintos/repetidos son válidos; N líneas comparten una cabecera/actor/documento y el saldo llega exactamente a cero. |
| E1-TP37 | R13–R15 | Validación y atomicidad de líneas: cero/negativo, lista vacía, medio inválido, suma menor para `TOTAL`, suma mayor al objetivo o fallo inducido en una línea. | Faltante no habilita confirmación y servidor lo rechaza para `TOTAL`; exceso/entrada inválida se rechaza; cero cabecera, líneas, auditoría, historial o estado parcial. |
| E1-TP38 | R14–R16 | Dos cobros concurrentes sobre el mismo saldo final. | Uno confirma completo; el otro recalcula saldo cero/terminal y falla sin cabecera ni líneas huérfanas. |
| E1-TP39 | R14–R16 | Dos actos parciales concurrentes cuya suma excedería saldo. | Serialización; sólo totales compatibles confirman y cada ganador conserva su agrupación/documento independiente. |
| E1-TP40 | R15 | Doble clic/retry por timeout con la misma idempotency key de cobro. | Devuelve la misma cabecera y exactamente las mismas N líneas; una auditoría, transición y documento lógico, sin duplicados. |
| E1-TP41 | R16 | Reapertura H5 antes de cualquier pago. | Sigue permitida y recorre cocina/entrega. |
| E1-TP42 | R16 | Reapertura o mutación después del primer parcial. | Rechazada; saldo y detalles conservados. |
| E1-TP43 | R03/R14–R16 | Cobro con sesión cerrada, otra caja u otro local; y cobro por Cajero B en sesión abierta por A. | Los tres primeros se rechazan sin filtrar datos; Cajero B puede cobrar en la misma caja/local y cabecera/líneas registran B como actor. |
| E1-TP44 | R14–R16 | Cobro y cierre concurrentes. | Uno obtiene lock; ningún pago queda asociado a sesión ya cerrada. |
| E1-TP45 | R17 | Cobro multi-medio con propina cero/positiva asociada a sus líneas. | Venta y propina permanecen separadas; saldo sólo baja por suma de importes y la propina total concilia con sus líneas. |
| E1-TP46 | R17 | Propina negativa o totales de importe/propina manipulados. | Rechazo/recálculo servidor; no se confía en totales enviados por cliente. |
| E1-TP47 | R05/R17/R21 | Cobro con líneas efectivo y electrónicas. | Efectivo esperado incorpora sólo importes/propinas `EFECTIVO`; reportes suman cada medio y no duplican la venta del cobro. |
| E1-TP48 | R13–R18 | Documentos por acto: total multi-medio, parcial y dos parciales sucesivos. | Un cobro multi-medio genera un solo documento con todas sus líneas; cada parcial genera su recibo independiente; el acto final genera ticket consolidado sin declararse fiscal. |

### Auditoría, seguridad y aislamiento

| ID | Requisitos | Caso | Resultado esperado |
|---|---|---|---|
| E1-TP49 | R19 | Reconstrucción de sesión compartida completa. | Apertura por A, movimientos/cobros por A y B, medios agrupados por acto, autorizaciones, anulación directa y cierre por B aparecen en orden con cada actor/hora. |
| E1-TP50 | R19 | Valores anteriores/nuevos de descuento/anulación/cierre. | Snapshots suficientes y consistentes con tablas de dominio. |
| E1-TP51 | R19–R20/R23 | Cliente intenta INSERT/UPDATE/DELETE directo, incluso sobre notificaciones/destinatarios. | Denegado por privilegios/RLS; RPC autorizada es la única vía de escritura y sólo permite al administrador marcar su propia entrega como leída. |
| E1-TP52 | R19–R20/R23 | Manipulación de local/sesión/pedido/notificación IDs, incluida lectura/batch de movimientos por CAJA/ADMIN y rechazo a CAJA/MOZO/COCINA/anon para notificaciones. | Sin lectura/escritura cruzada; otro local no puede descubrir ni marcar avisos, la respuesta no filtra datos y no se amplía lectura directa de perfiles. |
| E1-TP53 | R20 | Intento de borrar actor/caja/pedido referenciado. | `ON DELETE RESTRICT` conserva trazabilidad. |
| E1-TP54 | R19–R20/R23 | Error a mitad de RPC, incluida una línea intermedia de un cobro multi-medio o la generación de destinatarios de apertura/cierre. | Cabecera, todas las líneas, dominio, auditoría y notificaciones revierten juntos; cero huérfanos. |
| E1-TP55 | R19–R20/R23 | Funciones/owners/search_path/grants/policies, incluidas RPC de lectura/lote de movimientos y lectura/marcado de notificaciones. | `SECURITY DEFINER` endurecido; `PUBLIC`/`anon` revocados; mínimo privilegio, aislamiento por destinatario/local y escritura directa denegada. |

### Reportes, regresión y responsive

| ID | Requisitos | Caso | Resultado esperado |
|---|---|---|---|
| E1-TP56 | R21 | Reporte de sesión con cobro multi-medio y todos los conceptos. | Apertura, cada medio, entradas/salidas, esperado, diferencia, descuentos, anulaciones, propinas y parciales concilian; venta no se duplica por agrupación. |
| E1-TP57 | R21 | Resumen diario con cobros multi-medio y parciales. | Cada medio suma su parte, cada acto conserva identidad y el pedido se cuenta una sola vez al completar. |
| E1-TP58 | R21 | Fecha Lima, dos locales y exportación. | Corte `America/Lima`, aislamiento y CSV coherente. |
| E1-TP59 | R22–R24 | Estados UI de Caja y Administración: sin caja abierta, vacíos, loading, error/reintento, grilla sin históricos, bandeja sin avisos, Inicio sin actividad, grupos del flujo sin pedidos y `Operación → Pedidos` vacío/error. | Caja conserva estados inequívocos y grilla responsive. Inicio muestra `Todo en orden`, caja cerrada sin desaparecer, KPI/medios en cero sin `NaN` y tarjetas del flujo con cero/estado vacío sin tiempos ficticios; la campana conserva contador, lista reciente y prioridad normal/alerta. Pedidos ADMIN diferencia loading, vacío, error/reintento, anulable y bloqueado por pago; inicia filtrado a anulables, permite mostrar todos y presenta conteo coherente. |
| E1-TP60 | R22–R24 | Interacciones UI: confirmación única, edición de movimientos, lectura de notificaciones, navegación ADMIN, atención accionable, consulta del flujo actual y anulación directa desde `Operación → Pedidos`. | Cobro y lote conservan protecciones. La bandeja permite lectura individual/masiva sólo propia. Sidebar/drawer presenta `Pedidos` antes de `Pendientes por aprobar`; Pendientes contiene sólo descuentos; cierres con diferencia no leídos aparecen en Inicio sin aprobación. `Ver pedidos` del flujo abre/cambia/cierra detalle de sólo consulta y nunca ofrece acciones. La pantalla Pedidos exige motivo, confirma una sola vez, advierte en `EN_PREPARACION`/`LISTO`/`ENTREGADO`, bloquea doble envío y refresca el resultado autoritativo. El filtro cambia entre anulables/todos sin nueva lectura. |
| E1-TP61 | Todos | Regresión H1–H6/PM-001, SQL, typecheck, build, dashboard ADMIN y verificaciones de seguridad/concurrencia previstas en las tareas. | Además de los invariantes financieros existentes, KPI y ventas por medio concilian para el local/corte Lima. La lectura de flujo clasifica y calcula tiempos sin persistir métricas. `rpc_obtener_pedidos_operacion_admin()` conserva aislamiento local y mínimo privilegio, deriva `ultima_actualizacion_en` de timestamps existentes y ordena descendente; `anular_pedido_supervisado` mantiene matriz, bloqueo por cualquier pago, atomicidad de pedido/mesa/historial/auditoría e idempotencia. Caja/Ventas no habilitan cobro ADMIN y navegación/configuración no regresan. |

## 3. Pruebas humanas

| ID | Escenario | Evidencia requerida |
|---|---|---|
| E1-TP62 | **APROBADO HUMANAMENTE.** Jornada de Caja en PC y revisión de Inicio ADMIN: abrir, cobros, propina, movimientos, cierre con/sin diferencia; avisos, KPI, atención, flujo actual de pedidos, ventas por medio y caja del local actual. | Capturas/registro aprobados; el flujo de Caja conserva sus reglas. En Inicio se respeta `KPI → atención → flujo → ventas por medio → caja`; KPI concilian; los tres grupos muestran cantidad, mayor/promedio, mesas y detalle coherentes; descuentos permiten decisión, cierres consulta sin aprobación y el flujo no ofrece acciones operativas. Caja abierta/cerrada, vacíos y campana son comprensibles. |
| E1-TP63 | **APROBADO HUMANAMENTE.** Descuento solicitado por `CAJA` y autorizado/rechazado por `ADMINISTRADOR`; anulación directa desde `Operación → Pedidos`. | Descuento conserva solicitante/autorizador. ADMIN sólo ve pedidos de su local; motivo y confirmación son obligatorios; `EN_PREPARACION`/`LISTO`/`ENTREGADO` advierten impacto. Cada estado anulable sin pagos termina `ANULADO` con mesa consistente, actor/fecha/hora/historial/auditoría; pago parcial/completo y estados terminales muestran bloqueo sin acción ni efectos parciales. Pendientes continúa limitado a descuentos. |
| E1-TP64 | **APROBADO HUMANAMENTE.** Responsive aplicable: Caja PC principal, tablet como contingencia, Inicio y `Operación → Pedidos` ADMIN en desktop/tablet/móvil, y regresión de mozo/cocina. | Caja conserva acciones críticas. ADMIN usa sidebar en desktop y drawer/hamburguesa accesible; la grilla de pedidos adapta columnas/filas sin scroll horizontal ni ocultar estado/acción; tarjetas y detalle del flujo hacen wrap y siguen sin acciones. No aparecen históricos/analítica E8 ni capacidades multilocal; mozo/cocina no regresan. |

## 4. Datos y concurrencia

Fixtures mínimos: dos locales; dos cajas; dos usuarios `CAJA`; dos `ADMINISTRADOR` activos del mismo local, uno inactivo y otro administrador de distinto local; `MOZO`/`COCINA`; sesiones abiertas/cerradas; pedidos en cada estado y con entradas controladas a `ENVIADO`, `RECIBIDO_COCINA`, `EN_PREPARACION` y `LISTO`, incluida la transición interna del grupo de preparación; descuentos; pagos legacy sin cabecera; cobros de uno/N medios, parciales y finales; movimientos; propinas. Los fixtures se crean y limpian en transacciones o procedimientos aprobados sólo en DEV.

Las pruebas concurrentes usarán conexiones/sesiones distintas y barreras reproducibles; no se simulará concurrencia sólo con llamadas secuenciales. Después de cada caso se verifican conteos, sumas, estados, locks liberados, auditoría y ausencia de residuos.

La evidencia original de T08 valida los aspectos estructurales/legacy entonces aplicables de TP31–TP35: preservación exacta de pagos históricos, ausencia de sesiones retroactivas, columnas/constraints/índices/grants, asociación de pagos nuevos con sesión abierta, propina separada e idempotencia por fila. El delta T09 debe revalidar preservación exacta al introducir `cobro_id`, permitir `NULL` sólo para legacy y demostrar que no fabrica cabeceras retroactivas. La idempotencia por acto y la composición de N medios corresponden al nuevo contrato T09/T10.

## 5. Criterio de aprobación

- DF-01–DF-04 y DF-06–DF-10 aprobadas y reflejadas en el spec; EC-06–EC-08 conservadas como decisiones cerradas.
- TP01–TP61 automatizadas/técnicas vigentes quedaron cubiertas por la evidencia incremental; TP62, TP63 y TP64 fueron aprobadas humanamente.
- Cero sobrepago, doble apertura/cierre/cobro, cobro multi-medio parcial, acceso cruzado o auditoría faltante; idempotencia por acto y atomicidad de todas sus líneas.
- Regresión vigente completa, migraciones local/DEV alineadas y defectos no bloqueantes clasificados.
- La aprobación explícita del usuario autoriza `acceptance.md` y el cierre formal de E1.

## 6. Matriz requisito → diseño → tarea → prueba

| Requisitos | Diseño | Tareas | Pruebas |
|---|---|---|---|
| R01–R03 | D02–D03, D13 | T03–T04 | TP01–TP08 |
| R04–R08 | D04–D05, D11–D13 | T04–T05, T12 | TP09–TP18, TP56 |
| R09–R10 | D06, D13 | T06 | TP19–TP25 |
| R11–R12 | D07, D13, D16 | T07, T17 | TP26–TP30, TP59–TP64 aplicables |
| R13–R16 | D08, D13 | T08–T10 | TP31–TP44 |
| R17–R18 | D09 | T08–T10 | TP45–TP48 |
| R19–R20 | D10 | T11 | TP49–TP55 |
| R21 | D11 | T12 | TP56–TP58 |
| R22 | D12 | T10, T13–T14 | TP59–TP64 |
| R23 | D02–D05, D10–D13 | T15 | TP02, TP06, TP10, TP17–TP18, TP51–TP52, TP55, TP59–TP60, TP62 |
| R24 | D11, D16 | T16–T17 | TP59–TP64 aplicables |

## 7. Evidencia incremental de E1-T04

La primera validación aprobada de T04 se ejecutó sobre PostgreSQL local aislado, sin tocar DEV alojado ni PROD. Aplicó T04 sobre la baseline T03, preservó las 12 tablas preexistentes, aprobó **132 comprobaciones SQL**, **tres carreras reales con conexiones independientes** y **22 suites SQL directamente relacionadas o de contratos de base afectados**. En esa misma ejecución ya estaban cubiertos todos los casos aplicables de TP03–TP12.

| TP | Evidencia disponible | Estado para T04 |
|---|---|---|
| TP03 | Segunda apertura secuencial devolvió exactamente el snapshot/ID vigente; quedó una fila `ABIERTA`, sin cambiar `abierta_por`. | Aprobada |
| TP04 | Carreras `different-actors`, `same-key` y recuperación tras `23505` interno: dos respuestas exitosas con el mismo ID, una `ABIERTA`, una auditoría y cero conexiones residuales. | Aprobada |
| TP05 | Cajero B recuperó la sesión abierta por A y la consultó mediante la lectura activa; el snapshot conservó `abierta_por=A`. | Aprobada |
| TP06 | Reintentos del creador y del recuperador devolvieron el mismo resultado; una auditoría de apertura y solicitudes idempotentes sin duplicación. La carrera con la misma clave cubrió el reintento mientras la primera transacción estaba pendiente. | Aprobada |
| TP07 | `null`, negativo, `NaN`, infinitos, exceso de precisión/rango y clave nula fueron rechazados sin apertura. | Aprobada |
| TP08 | Sesión cerrada/esperada incorrecta, otra caja, caja inactiva, caja inexistente y otro local fueron rechazados sin filtrar datos. | Aprobada para T04 |
| TP09 | B recuperó/continuó la sesión de A y `abierta_por` permaneció intacto. Los actores de pagos y movimientos se validarán cuando existan esas operaciones en T05/T09. | Aspecto T04 aprobado; resto diferido por dependencia |
| TP10 | El histórico básico conservó y mostró `abierta_por=A` y `cerrada_por=B` en un fixture estructural. El cierre operativo por B corresponde a T05. | Aspecto T04 aprobado; cierre diferido por dependencia |
| TP11 | Lectura de histórico autorizada para CAJA A, CAJA B y ADMINISTRADOR, paginada y limitada al local; conserva actores de apertura/cierre. | Aprobada |
| TP12 | MOZO, COCINA, `anon`, perfil/rol/local inactivo y contexto sin usuario fueron denegados en RPC/SELECT; se verificaron grants, RLS, `SECURITY DEFINER`, owner y `search_path`. | Aprobada |

Después de esa validación no cambió la migración ni las RPC de T04. Las comprobaciones añadidas posteriormente al archivo de pruebas, aún no ejecutadas y no requeridas por TP03–TP12, se retiraron. Por tanto, **no quedaron casos faltantes ni invalidados y no se ejecutaron pruebas nuevas para cerrar T04**.

Se conservaron deliberadamente sin repetir: las 132 comprobaciones SQL, las tres carreras, las 22 regresiones SQL, los 305 tests Node, `typecheck` y `build`. La razón es que ya habían aprobado y desde entonces no cambió ningún archivo capaz de invalidar sus resultados; repetirlos contradiría la estrategia incremental. Las operaciones pendientes de TP09/TP10 no son una deuda de T04: dependen de T05/T09 y se ejecutarán en sus tareas.

## 8. Evidencia incremental de E1-T05

T05 se validó en PostgreSQL local aislado sobre T03, T04 y T08. La migración preservó exactamente el evento `APERTURA` previo de T04. Se aprobaron 15 grupos de comprobación SQL, la regresión T04 directamente afectada y tres carreras reales con conexiones independientes.

| TP | Evidencia disponible | Estado para T05 |
|---|---|---|
| TP13 | Entrada positiva con motivo persistió sesión, actor Cajero B, hora servidor y una auditoría atómica. | Aprobada |
| TP14 | Salida positiva explícita persistió actor Cajero A y redujo el efectivo esperado. | Aprobada |
| TP15 | Cero, negativo, motivo vacío, sesión cerrada, caja inactiva y otro local fueron rechazados sin residuos; dominio, snapshot y solicitud no admiten edición/borrado. | Aprobada |
| TP16 | Reintento con la misma clave devolvió el mismo movimiento y conservó una fila/auditoría; cierre-vs-movimiento usó locks reales y dejó al perdedor en `40001`. | Aprobada |
| TP17 | Snapshot: inicial 100 + pago EFECTIVO 50 + propina EFECTIVO 5 + entrada 20 − salida 5 = esperado 170. Yape 30 y propina Yape 3 quedaron separados y no afectaron efectivo. Cierre contado 170 produjo diferencia cero. | Aprobada |
| TP18 | Diferencia −10 exigió motivo; cierre supervisor exigió ADMINISTRADOR y motivo. Doble cierre, cierre-vs-movimiento y cierre-vs-cobro bloquearon realmente; un ganador atómico, perdedor `40001`, sin pagos asociados después del cierre. | Aprobada |

Aspectos pendientes de TP09/TP10 aplicables a T05: movimientos por Cajero A/B conservaron su actor sin alterar `abierta_por`; Cajero B cerró la sesión abierta por A y quedaron `abierta_por=A`/`cerrada_por=B`. Los aspectos de pagos múltiples permanecen diferidos a T09.

## 9. Evidencia incremental de E1-T06

T06 se validó en PostgreSQL local aislado sobre T03, T04, T08 y T05. `pedido` conservó exactamente sus columnas previas: no se agregaron snapshots de subtotal, descuento ni total neto. Se aprobaron 8 grupos SQL de T06, cuatro regresiones directamente afectadas y TP24 con conexiones independientes.

| TP | Evidencia disponible | Estado para T06 |
|---|---|---|
| TP19 | Solicitud `IMPORTE=20` por CAJA y autorización por ADMINISTRADOR sobre subtotal 100 produjeron snapshot 100/20/80; solicitante, autorizador y auditorías quedaron trazados. `fn_resolver_total_pedido` devolvió los mismos valores. | Aprobada |
| TP20 | `PORCENTAJE=12.5` sobre 99.99 redondeó el descuento a 12.50 y total neto a 87.49 en PostgreSQL. No existe tope porcentual comercial arbitrario; sólo el límite matemático que impide total negativo. | Aprobada |
| TP21 | CAJA no pudo autoautorizar y MOZO no pudo solicitar; grants, rol y contexto servidor bloquearon elevación de privilegios. | Aprobada |
| TP22 | Sin tipo, ambos tipos, cero, importe mayor al subtotal, porcentaje mayor a 100 y motivo vacío fueron rechazados sin snapshot. | Aprobada |
| TP23 | Una fila de pago confirmada bloqueó la solicitud; el snapshot autorizado tampoco admitió UPDATE/DELETE posterior. | Aprobada |
| TP24 | Carrera real: autorización mantuvo lock del pedido, cobro esperó, leyó el snapshot confirmado y persistió un único pago de 80. Pedido `PAGADO`, snapshot 100/20/80 y cero inconsistencia. | Aprobada |
| TP25 | Reintentos de solicitud/autorización devolvieron la misma fila; un evento de solicitud y uno de autorización. | Aprobada |

El cobro total provisional T08 fue adaptado sólo para consumir `fn_resolver_total_pedido`. Conserva temporalmente su orden `caja → sesion_caja → pedido → mesa`. **Pendiente obligatorio de T09:** adoptar el orden definitivo aprobado `sesion_caja → pedido → mesa` al implementar N pagos/parciales; no se corrigió dentro de T06.

## 10. Evidencia incremental de E1-T07

T07 se validó en PostgreSQL local aislado sobre T03, T04, T08, T05 y T06. Se aprobaron 8 grupos SQL, tres regresiones de auditoría directamente afectadas y TP29 con conexiones independientes y bloqueo reproducible.

| TP | Evidencia disponible | Estado para T07 |
|---|---|---|
| TP26 | ADMINISTRADOR anuló directamente un pedido con motivo obligatorio; pedido `ANULADO`, mesa `LIBRE`, historial y auditoría registraron estado anterior/nuevo, actor y hora servidor. Los detalles conservaron exactamente su fingerprint. | Aprobada |
| TP27 | Se probó individualmente `ABIERTO`, `ENVIADO`, `RECIBIDO_COCINA`, `EN_PREPARACION`, `LISTO` y `ENTREGADO`: todos se anularon sin pagos. `PAGADO` y `ANULADO` fueron rechazados. En cada anulación exitosa la mesa quedó `LIBRE`. | Aprobada |
| TP28 | Un pago confirmado bloqueó la anulación sin alterar pago, pedido, mesa ni auditoría. | Aprobada |
| TP29 | Carrera real: la anulación retuvo locks de pedido/mesa; el cobro esperó y, tras el commit, falló limpiamente con `40001`. Resultado: pedido `ANULADO`, mesa `LIBRE`, cero pagos, un historial y una auditoría de anulación. | Aprobada |
| TP30 | `PAGADO` y `ANULADO` permanecieron terminales ante las mutaciones H3–H5 afectadas: agregar detalle, entregar y cobrar fueron rechazados sin residuos. | Aprobada |

La idempotencia devolvió la misma anulación sin duplicar historial ni auditoría. CAJA, MOZO, otro local y motivo vacío fueron rechazados; RLS/grants permiten lectura local sólo a ADMINISTRADOR y no conceden escritura directa. Las regresiones aprobadas fueron `e1_t04_apertura_sesion`, `e1_t05_movimientos_cierre` y `e1_t06_descuento_pedido`, porque T07 amplió el constraint compartido de `auditoria_caja`.

No se ejecutaron las 305 pruebas Node, `typecheck` ni `build`: T07 modificó exclusivamente SQL, pruebas SQL y documentación. Tampoco se repitieron suites sin relación directa ni pruebas ya aprobadas cuyos contratos no cambiaron.

## 11. Evidencia incremental de E1-T09

> **Evidencia histórica previa al ajuste TP62.** Los resultados siguientes demuestran la seguridad del contrato de pagos sucesivos construido, pero no validan todavía la nueva agrupación `cobro` + N medios. TP32–TP40 y TP43–TP48 deben revalidarse en su redacción vigente; TP31 se repite sólo para invariantes legacy afectados. Esta sección no autoriza considerar completado el delta.

Replay limpio de 35 migraciones aprobado. El constraint conserva todos los eventos anteriores y añade `PAGO`; la RPC bloquea `sesion_caja → pedido → mesa`.

| TP | Evidencia | Estado |
|---|---|---|
| TP31 | Regresión T08: 27 comprobaciones legacy, sin sesiones fabricadas. | Aprobada en aspectos afectados |
| TP32 | Pago total: `PAGADO`, mesa `LIBRE`, historial y saldo cero. | Aprobada |
| TP33–TP34 | Dos medios distintos y `TARJETA + TARJETA`; parcial pendiente y final exacto. | Aprobadas |
| TP35 | Sin persistencia por líneas; corresponde a UI. | Diferida a T10 |
| TP36 | Cuatro pagos mixtos/repetidos sumaron exactamente 100. | Aprobada |
| TP37 | Cero, negativo y sobrepago rechazados sin residuos. | Aprobada |
| TP38–TP39 | Carreras de saldo final y parciales incompatibles: un ganador, sin sobrepago. | Aprobadas |
| TP40 | Reintento devolvió la misma fila y una auditoría. | Aprobada |
| TP41–TP42 | Reapertura previa conservada; mutación posterior al parcial rechazada. | Aprobadas |
| TP43 | Sesión cerrada/otro local rechazados; Cajero B cobró sesión abierta por A. | Aprobada |
| TP44 | Cierre ganó; cobro no dejó pago asociado a sesión cerrada. | Aprobada |
| TP45–TP47 | Propina separada; negativa rechazada; sólo efectivo incrementa esperado. | Aprobadas backend |

Las cuatro carreras (saldo final, parciales incompatibles, cierre-vs-cobro y anulación-vs-cobro) usaron conexiones independientes y bloqueo comprobado con `pg_blocking_pids`. Todas terminaron sin sobrepago, huérfanos, efectos parciales del perdedor ni conexiones residuales.

Checkpoint: T04 132 comprobaciones; T05 15; T06 y T07 8 grupos cada una; T08 27. Se reutilizó T03 porque T09 no cambió caja/sesión. Node, `typecheck`, `build` y regresión integral H1–H6/PM-001 permanecen para T13.

## 12. Prerrequisito técnico de lecturas para E1-T10

Antes de iniciar React, 8 grupos SQL aprobaron: compatibilidad del shape H5 de pendientes; subtotal/descuento/neto; acumulado/saldo con cero, uno y N pagos; pagos con medio, propina, actor y hora; acceso CAJA/ADMINISTRADOR del mismo local; rechazo de otros roles y otro local; visibilidad operacional de `PAGADO`/`ANULADO`. La regresión `h5_t03_cashier_pending_orders_read.sql` también aprobó tras homologar su inspección de metadata al shape aditivo. Estas lecturas no alteraron TP y, por sí solas, no completaban T10; dejaron su implementación frontend desbloqueada.

## 13. Evidencia técnica de E1-T10

La adaptación frontend aprobó 35/35 pruebas Node/React directamente afectadas, `typecheck` y `build`. TP35 confirmó que la selección de productos sólo propone un importe; TP45–TP47 cubrieron captura/visualización separada de propina; TP48 distinguió recibo parcial y ticket consolidado interno no fiscal; TP59–TP60 cubrieron estados operativos, reintento, exclusión de doble envío y resincronización autoritativa.

TP62–TP64 permanecen pendientes de ejecución humana y no se consideran aprobadas. No se repitieron SQL T03–T09, replay, suite Node integral ni regresión H1–H6/PM-001 porque esta intervención no modificó contratos PostgreSQL y esos checkpoints corresponden a T13.

## 14. Evidencia incremental de E1-T11

T11 se validó sobre una copia local aislada de la baseline T10 existente. Se aplicó únicamente `20260917000100_e1_t11_auditoria_financiera.sql`; no fue necesario repetir el replay completo. El catálogo quedó cerrado a `APERTURA`, `ENTRADA`, `SALIDA`, `SOLICITUD_DESCUENTO`, `AUTORIZACION_DESCUENTO`, `RECHAZO_DESCUENTO`, `PAGO`, `ANULACION`, `CIERRE` y `CIERRE_SUPERVISOR`; no existe evento de revocación.

| TP | Evidencia | Estado |
|---|---|---|
| TP49 | Reconstrucción ordenada por sesión/pedido con apertura por Cajero A, movimiento y pago por Cajero B, solicitante y administrador reales. | Aprobada |
| TP50 | Total neto autorizado, saldo anterior/nuevo del pago y estados financieros coincidieron con las tablas de dominio. | Aprobada |
| TP51 | `authenticated` no pudo insertar, actualizar ni eliminar `auditoria_caja`; sólo las RPC insertan eventos. | Aprobada |
| TP52 | Una sesión de otro local produjo conjunto vacío y MOZO fue rechazado sin exposición de datos. | Aprobada |
| TP53 | Eliminación de actor, caja y pedido referenciados fue bloqueada por FK; la trazabilidad quedó preservada. | Aprobada |
| TP54 | Un trigger de fallo inducido durante una RPC revirtió movimiento y auditoría; quedaron cero efectos parciales y cero huérfanos. | Aprobada |
| TP55 | RPC `SECURITY DEFINER`, owner `postgres`, `search_path=pg_catalog`, RLS activa, `PUBLIC`/`anon` revocados y `authenticated` sólo con ejecución de lectura. | Aprobada |

Regresiones directamente afectadas aprobadas: T04 (132 comprobaciones), T05 (15), T06, T07 y T09. No se ejecutaron suite Node integral, `typecheck`, `build`, TP62–TP64 ni la regresión integral T13 porque T11 sólo modificó SQL/documentación y no cambió contratos funcionales T03–T10.

## 15. Evidencia incremental de E1-T12

T12 se validó sobre la baseline local aislada aprobada hasta T11, aplicando una sola vez `20260917000200_e1_t12_reportes_caja.sql`. No se hizo replay integral. Las lecturas derivan local del contexto autenticado, usan corte `America/Lima`, separan venta/propina y contabilizan importes parciales sin inflar el conteo de pedidos completados.

| TP | Evidencia | Estado |
|---|---|---|
| TP56 | Sesión cerrada con apertura por Cajero A, cierre por Cajero B, dos pagos parciales EFECTIVO/YAPE, propinas, entrada, salida, descuento, anulación, esperado, contado y diferencia concilió exactamente. | Aprobada |
| TP57 | Resumen diario sumó 90 de venta y 7 de propina en dos pagos, pero contó un único pedido completado; descuento y anulación quedaron separados. | Aprobada |
| TP58 | Fecha operativa Lima correcta; otro local obtuvo sólo su información; MOZO, COCINA y contexto anónimo fueron rechazados. Los CSV usan exactamente el snapshot cargado sin recalcular totales. | Aprobada |

Regresión `h6_t02_sales_exports.sql`: aprobada. Pruebas Node/React directamente afectadas: 35/35 aprobadas; la prueba focalizada final de reportes aprobó 9/9. `typecheck` y `build` aprobaron; el build sólo emitió la advertencia no bloqueante de tamaño de chunk. No se ejecutaron replay integral, suite SQL T03–T11, regresión integral T13 ni TP62–TP64.

## 16. Puerta técnica integral E1-T13

T13 aprobó nuevamente la matriz técnica completa **TP01–TP61** sobre el delta de cobro. El replay limpio final aplicó las **43 migraciones** y el seed sobre PostgreSQL 17 local, aislado, sin red ni bind mounts. Aprobaron las regresiones SQL aplicables H1–H6/PM-001/E1, los deltas T09–T12, seguridad final, cinco carreras de cobro con conexiones independientes, **311/311 pruebas Node/React**, `typecheck`, `build` y `git diff --check`. Las inspecciones históricas basadas en inventarios/fingerprints exactos se homologaron únicamente para admitir los objetos y columnas aditivos aprobados, conservando sus invariantes de permisos y contratos. No existe script/dependencia de lint, por lo que no se ejecutó ni se incorporó una herramienta nueva. Evidencia detallada: `implementation-t13.md`.

TP62–TP64 y T14 permanecen pendientes de ejecución humana; E1 no está aceptada.

## 17. Evidencia incremental de E1-T15

T15 se validó mediante replay limpio de **45 migraciones** y `supabase/seed.sql` en la base PostgreSQL local aislada `e1_t15_951aac247c5345e1a8943b4d7a78209e`. La migración final es `20260921000100_e1_t15_notificaciones_caja.sql`; fue aplicada manualmente en DEV y no se aplicó en PROD.

| TP | Evidencia T15 | Estado |
|---|---|---|
| TP02/TP06 | Una apertura real creó una notificación; el reintento devolvió la misma sesión sin duplicar notificación ni destinatarios. | Aprobada |
| TP10 | La notificación de cierre conservó como actor al cajero que cerró, aunque fuera distinto de quien abrió. | Aprobada |
| TP17 | Cierre con diferencia cero creó una única notificación `INFORMATIVA` con esperado, contado y diferencia cero. | Aprobada |
| TP18 | Cierre con diferencia creó una única `ALERTA` con diferencia y motivo, sin aprobación administrativa; reintento sin duplicados. | Aprobada |
| TP51/TP52 | Escritura directa denegada; CAJA/MOZO/COCINA/anon y otro local no pudieron leer ni marcar entregas. | Aprobada |
| TP54 | Fallo inducido al insertar destinatarios revirtió sesión, auditoría, notificación y entregas; cero huérfanos. | Aprobada |
| TP55 | RPC `SECURITY DEFINER`, owner `postgres`, `search_path=pg_catalog`, grants mínimos y RLS activa. ADMIN no pudo leer directamente el perfil del cajero; el nombre se resolvió dentro de la RPC. | Aprobada |
| TP59/TP60 | Campana, contador, vacío/error, prioridades informativa/alerta y marcado individual persistente cubiertos por SQL y frontend. | Aprobada técnicamente |

Dos administradores activos del local recibieron una entrega cada uno; el administrador inactivo y el de otro local no recibieron ninguna. La lectura de un administrador no alteró la entrega del otro. Las regresiones SQL directamente afectadas T04, T05 y T11 aprobaron. Aprobaron **58/58 pruebas Node/React afectadas**, `typecheck` y `build`; el único warning fue el tamaño de chunk de Vite. TP62 no se ejecutó ni se marcó aprobado.

## 18. Evidencia técnica de E1-T16

T16 aplicó en PostgreSQL local aislado un replay limpio de **47 migraciones + seed** y validó `rpc_obtener_flujo_actual_pedidos_admin()`: tres grupos siempre presentes, clasificación de estados, exclusión de terminales, mayor/promedio con hora servidor, detalle descendente, aislamiento entre locales, vacíos y continuidad temporal durante `RECIBIDO_COCINA → EN_PREPARACION`. La RPC es `SECURITY DEFINER`, owner `postgres`, `search_path=pg_catalog`, sin ejecución para `PUBLIC`/`anon`, sin grants directos nuevos y rechaza `CAJA`, `MOZO` y `COCINA`.

Las regresiones SQL directamente afectadas `h4_t04_derived_order_table_state` y `e1_t12_reportes_caja` aprobaron. Aprobaron **28/28 pruebas frontend afectadas**, `typecheck`, `build` y `git diff --check`; el build mantuvo sólo el warning no bloqueante de tamaño de chunk. TP62–TP64 continúan pendientes de validación humana, por lo que T16 no se considera completada ni E1 aceptada.

## 19. Evidencia técnica de E1-T17

La entrega inicial de T17 reutilizó `rpc_obtener_pedidos_operacion_admin()` y `anular_pedido_supervisado(...)` sin cambiar sus reglas. La ruta ADMIN, sidebar y drawer incorporan `Pedidos` antes de `Pendientes por aprobar`. La pantalla distingue loading, vacío, error/reintento, anulable y bloqueo por pago/estado terminal; exige motivo, advierte el impacto operativo en `EN_PREPARACION`/`LISTO`/`ENTREGADO`, conserva una clave de idempotencia por intento, bloquea doble envío y refresca el snapshot autoritativo tras éxito o error. El ajuste posterior de última actualización amplió únicamente la salida de la lectura administrativa mediante una migración aditiva.

Aprobaron **52/52 pruebas frontend directamente afectadas** de navegación, Inicio, Caja y T17, además de **14/14 pruebas responsive**, `typecheck` y `build`. El delta `20260921000400_e1_t17_pedidos_admin_ultima_actualizacion.sql` compiló y se aplicó correctamente sólo en PostgreSQL local, después de las migraciones locales pendientes T15/T16; no se aplicó a DEV remoto ni PROD. La RPC conserva contexto servidor, aislamiento local, `SECURITY DEFINER`, `search_path` endurecido y grants mínimos, y ahora ordena por `ultima_actualizacion_en DESC`. El build mantuvo sólo el warning no bloqueante de tamaño de chunk de Vite. La grilla cambia a distribución apilada en anchos menores sin scroll horizontal. TP63 continúa en ejecución humana y TP64 permanece pendiente; esta evidencia técnica no completa T14 ni acepta E1.

## 20. Cierre humano de E1

El usuario aprobó formalmente E1 el **21/09/2026**. TP62, TP63 y TP64 quedaron **APROBADAS HUMANAMENTE**. Con la evidencia técnica acumulada y la aceptación explícita registrada en `acceptance.md`, E1 queda **APROBADA Y CERRADA**. Las referencias a pruebas pendientes dentro de secciones de evidencia anteriores se conservan como registro histórico del estado que existía durante cada ejecución.
