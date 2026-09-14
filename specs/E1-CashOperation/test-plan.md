# MikuyApp — Evolución 1 — Operación de caja: plan de pruebas

## 1. Estrategia y ambientes

La construcción futura combinará pruebas SQL transaccionales, Node/React, concurrencia en sesiones independientes, RLS con usuarios reales por rol, regresión integral y validación humana. PostgreSQL es el oráculo de montos/estados. Cada caso financiero verificará filas, auditoría y ausencia de efectos parciales.

Mientras PM-002 permanezca `TRANSITIONING`, las pruebas se ejecutarán primero en local/DEV y deployment Preview dirigido a DEV. Este plan no autoriza tocar PROD, Cloudflare Production, variables, datos ni completar PM-002.

### Validación incremental de construcción

La matriz TP01–TP64 permanece íntegra. Durante T03–T12 se ejecutan los TP propios de la tarea y sólo las regresiones directamente afectadas por los archivos, esquema o contratos modificados. Una prueba aprobada no se repite en la misma tarea salvo que un cambio posterior pueda invalidarla, haya requerido una corrección o sea necesaria para comprobar una interacción nueva.

- No se ejecuta automáticamente la suite Node completa tras cada tarea.
- Un cambio exclusivamente SQL no obliga automáticamente a repetir `typecheck` o `build`.
- Las carreras usan conexiones independientes sólo cuando este plan las exige explícitamente para la tarea.
- Los fingerprints completos de datos legacy sólo se repiten cuando la tarea altera datos, esquema o contrato legacy.
- Las comprobaciones incrementales reutilizan una baseline local validada; el replay limpio completo se reserva para migraciones que lo requieran y checkpoints.
- T08 refuerza estructura y compatibilidad legacy por modificar `pago`; los comportamientos de N pagos/parciales permanecen en T09, que es checkpoint ampliado del núcleo financiero T03–T09.
- T13 mantiene la puerta integral definitiva con TP01–TP61, SQL, seguridad, concurrencia, regresión H1–H6/PM-001, `typecheck` y `build`.

## 2. Matriz de pruebas técnicas

### Apertura, sesión y permisos

| ID | Requisitos | Caso | Resultado esperado |
|---|---|---|---|
| E1-TP01 | R01 | Caja física vs sesión. | Varias sesiones históricas pertenecen a una caja; sólo una puede estar abierta. |
| E1-TP02 | R01–R03 | Apertura normal con monto inicial cero/positivo. | Sesión abierta con actor/local/hora servidor y auditoría. |
| E1-TP03 | R02 | Doble apertura secuencial. | La segunda apertura sobre la misma caja devuelve el snapshot autorizado de la sesión vigente, sin error funcional, sin insertar otra sesión y sin alterar `abierta_por`. |
| E1-TP04 | R02 | Doble apertura concurrente. | Sólo una llamada crea la sesión; la otra recupera esa misma sesión. Ambas observan el mismo `sesion_caja.id` y queda exactamente una `ABIERTA`. La RPC resuelve de forma segura cualquier conflicto interno `23505`, sin exponerlo como resultado funcional normal; la restricción única parcial permanece como defensa final. |
| E1-TP05 | R01–R03 | Cajero B accede a la caja con sesión abierta por Cajero A. | Recupera y continúa la misma sesión sin cierre ni arqueo; `abierta_por` permanece Cajero A. |
| E1-TP06 | R02–R03 | Reintento con misma idempotencia tras timeout. | Devuelve la misma apertura; no duplica auditoría. |
| E1-TP07 | R02 | Monto inicial negativo/null/NaN conceptual. | Rechazo servidor sin cambios. |
| E1-TP08 | R01–R04 | Operación sobre sesión cerrada, otra caja, caja inactiva u otro local. | Rechazo servidor sin cambios ni filtración de datos. |
| E1-TP09 | R03–R06/R19 | Cajeros A y B alternan pagos, entradas y salidas en la misma sesión. | Cada operación persiste su actor real; `abierta_por` no cambia. |
| E1-TP10 | R03/R06 | Cajero B cierra la sesión abierta por Cajero A. | Cierre válido sin arqueo intermedio; quedan trazados `abierta_por=A` y `cerrada_por=B` con sus fechas. |
| E1-TP11 | R08 | Histórico por `CAJA` y `ADMINISTRADOR`. | Sólo sesiones del local autorizado, con actores por operación y apertura/cierre. |
| E1-TP12 | R01–R08 | `MOZO`, `COCINA`, `anon` o perfil/rol/local inactivo ejecutan RPC/SELECT. | Denegado por grants/RLS y validación interna. |

### Movimientos y cierre

| ID | Requisitos | Caso | Resultado esperado |
|---|---|---|---|
| E1-TP13 | R04 | Entrada manual normal. | Evento positivo, motivo, actor/hora/sesión y auditoría. |
| E1-TP14 | R04 | **Salida de caja** normal. | Evento `SALIDA` explícito reduce esperado y queda trazable. |
| E1-TP15 | R04 | Importe cero/negativo, motivo vacío o sesión cerrada. | Rechazo sin fila ni auditoría huérfana. |
| E1-TP16 | R04–R05 | Entradas/salidas concurrentes y reintentos. | Todos los eventos válidos se suman una vez; idempotencia impide duplicados. |
| E1-TP17 | R05–R07 | Cierre correcto sin diferencia. | Snapshot por medio/movimiento, esperado=contado, diferencia cero, sesión cerrada. |
| E1-TP18 | R05–R07 | Diferencia, doble cierre y cierre vs cobro/movimiento. | Aplica DF-02; sólo un cierre; operación perdedora falla/recarga sin parcialidad. La carrera cierre-vs-cobro se ejecuta en T05 después de T08, cuando todo pago nuevo ya queda asociado a sesión. |

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
| E1-TP27 | R11 | Anulación en estados avanzados permitidos/no permitidos. | Se aplica la matriz aprobada; nunca transición silenciosa. |
| E1-TP28 | R12 | Anulación con cualquier pago parcial o pedido `PAGADO`. | Bloqueada por regla definitiva; pagos intactos y sin evento de anulación. |
| E1-TP29 | R11–R12 | Anulación vs cobro simultáneo. | Sólo un resultado coherente; no pedido anulado con pago inesperado. |
| E1-TP30 | R11–R12 | Pedido `ANULADO`/`PAGADO` recibe mutaciones H3–H5. | Terminalidad existente conservada. |

### División, pagos y propinas

| ID | Requisitos | Caso | Resultado esperado |
|---|---|---|---|
| E1-TP31 | R13–R16 | Migración de pago legacy. | Filas/importes/medios/usuarios/fechas preservados; legacy identificable sin sesión inventada. |
| E1-TP32 | R13–R16 | Pago total único (regresión H5). | Un pago, `PAGADO`, historial único, mesa `LIBRE`. |
| E1-TP33 | R13–R16 | Dos pagos por importe y medios distintos. | Primer pago conserva `ENTREGADO`/pendiente; segundo completa y libera. |
| E1-TP34 | R13–R16 | Dos pagos `TARJETA + TARJETA` sobre el mismo pedido. | Ambos medios repetidos son válidos; el primero deja saldo y el segundo sólo marca `PAGADO` si completa exactamente el neto. |
| E1-TP35 | R13 | División por selección de productos. | UI calcula importe; servidor valida monto, sin mover/duplicar detalles. |
| E1-TP36 | R13–R16 | Cuatro pagos `EFECTIVO + YAPE + TARJETA + TARJETA`, incluyendo redondeo. | Los medios distintos/repetidos son válidos; N filas conservan actor y el saldo llega exactamente a cero sin sobrepago. |
| E1-TP37 | R14 | Importe cero/negativo/mayor al saldo. | Rechazo servidor sin pago/auditoría. |
| E1-TP38 | R14–R16 | Doble cobro concurrente del saldo final. | Uno confirma; otro observa saldo cero/terminal; no duplica. |
| E1-TP39 | R14–R16 | Dos pagos parciales concurrentes cuya suma excedería saldo. | Serialización; sólo montos compatibles confirman. |
| E1-TP40 | R15 | Doble clic/reintento con idempotency key. | Mismo pago devuelto; una fila/evento. |
| E1-TP41 | R16 | Reapertura H5 antes de cualquier pago. | Sigue permitida y recorre cocina/entrega. |
| E1-TP42 | R16 | Reapertura o mutación después del primer parcial. | Rechazada; saldo y detalles conservados. |
| E1-TP43 | R03/R14–R16 | Cobro con sesión cerrada, otra caja u otro local; y cobro por Cajero B en sesión abierta por A. | Los tres primeros se rechazan; Cajero B puede cobrar en la misma caja/local y el pago registra B como actor. |
| E1-TP44 | R14–R16 | Cobro y cierre concurrentes. | Uno obtiene lock; ningún pago queda asociado a sesión ya cerrada. |
| E1-TP45 | R17 | Pago con propina cero/positiva. | Venta y propina separadas; saldo sólo baja por importe. |
| E1-TP46 | R17 | Propina negativa o importe+propina manipulado. | Rechazo/recálculo servidor; no se confía en total cliente. |
| E1-TP47 | R17 | Propina efectivo vs electrónica. | Sólo propina efectivo aumenta efectivo esperado; reportes separan medios. |
| E1-TP48 | R18 | Recibos parciales y ticket consolidado. | Aplica DF-06; muestra subtotal, descuento, pagos, propinas y saldo sin declararse fiscal. |

### Auditoría, seguridad y aislamiento

| ID | Requisitos | Caso | Resultado esperado |
|---|---|---|---|
| E1-TP49 | R19 | Reconstrucción de sesión compartida completa. | Apertura por A, movimientos/pagos por A y B, autorizaciones, anulación directa y cierre por B aparecen en orden con cada actor/hora. |
| E1-TP50 | R19 | Valores anteriores/nuevos de descuento/anulación/cierre. | Snapshots suficientes y consistentes con tablas de dominio. |
| E1-TP51 | R19–R20 | Cliente intenta INSERT/UPDATE/DELETE directo. | Denegado por privilegios/RLS; RPC única vía de escritura. |
| E1-TP52 | R19–R20 | Manipulación de local/sesión/pedido IDs. | Sin lectura/escritura cruzada; respuesta no filtra datos. |
| E1-TP53 | R20 | Intento de borrar actor/caja/pedido referenciado. | `ON DELETE RESTRICT` conserva trazabilidad. |
| E1-TP54 | R19–R20 | Error a mitad de RPC. | Dominio y auditoría revierten juntos; cero huérfanos. |
| E1-TP55 | R19–R20 | Funciones/owners/search_path/grants/policies. | `SECURITY DEFINER` endurecido; `PUBLIC`/`anon` revocados; mínimo privilegio. |

### Reportes, regresión y responsive

| ID | Requisitos | Caso | Resultado esperado |
|---|---|---|---|
| E1-TP56 | R21 | Reporte de sesión con todos los conceptos. | Apertura, medios, entradas/salidas, esperado, diferencia, descuentos, anulaciones, propinas y parciales concilian. |
| E1-TP57 | R21 | Resumen diario con parciales. | Importes se reflejan correctamente; conteo de pedido se realiza una vez al completar. |
| E1-TP58 | R21 | Fecha Lima, dos locales y exportación. | Corte `America/Lima`, aislamiento y CSV coherente. |
| E1-TP59 | R22 | UI sin caja abierta, vacía, cargando, error y reintento. | Estado inequívoco; acciones financieras deshabilitadas. |
| E1-TP60 | R22 | Doble clic y respuesta obsoleta en todas las acciones sensibles. | Botones bloqueados y snapshot refrescado; sin falso éxito. |
| E1-TP61 | Todos | Regresión H1–H6/PM-001, SQL, typecheck, build y verificaciones de seguridad/concurrencia previstas en las tareas. | Cobro total actual, entrega, terminalidad, reportes, RLS, Realtime e invariantes concurrentes sin regresión. |

## 3. Pruebas humanas

| ID | Escenario | Evidencia requerida |
|---|---|---|
| E1-TP62 | Jornada de Caja en PC: abrir, cobro efectivo/electrónico, entrada, **salida**, parcial, propina, cierre con y sin diferencia. | Capturas/registro; esperado y arqueo conciliados; tiempos/pasos aceptables. |
| E1-TP63 | Descuento solicitado por `CAJA` y autorizado por `ADMINISTRADOR`; anulación ejecutada directamente por `ADMINISTRADOR`, incluidos rechazos. | Descuento conserva solicitante/autorizador; anulación conserva únicamente actor administrador, motivo, fecha/hora y efectos en pedido/mesa/reportes. |
| E1-TP64 | Responsive aplicable: Caja PC principal, tablet como contingencia y regresión del flujo de mozo/cocina. | Acciones críticas visibles sin solapamiento; flujo mesa→pago y Realtime conservados. |

## 4. Datos y concurrencia

Fixtures mínimos: dos locales; dos cajas; dos usuarios `CAJA`; un `ADMINISTRADOR`; `MOZO`/`COCINA`; sesiones abiertas/cerradas; pedidos en cada estado; descuentos; pagos legacy, parciales y finales; movimientos; propinas. Los fixtures se crean y limpian en transacciones o procedimientos aprobados sólo en DEV.

Las pruebas concurrentes usarán conexiones/sesiones distintas y barreras reproducibles; no se simulará concurrencia sólo con llamadas secuenciales. Después de cada caso se verifican conteos, sumas, estados, locks liberados, auditoría y ausencia de residuos.

Para el orden técnico corregido, T08 valida únicamente los aspectos estructurales/legacy aplicables de TP31–TP35: preservación exacta de pagos históricos, ausencia de sesiones retroactivas, columnas/constraints/índices/grants nuevos, asociación de todo pago nuevo con sesión abierta, propina separada, idempotencia y regresión del cobro total H5 modificado. Eliminar la unicidad por pedido prepara el modelo, pero T08 no habilita ni declara aprobados N pagos, pagos parciales, división operativa o selección por productos; esos comportamientos permanecen en T09/T10.

## 5. Criterio de aprobación

- DF-01–DF-04 y DF-06–DF-09 aprobadas y reflejadas en el spec; EC-06–EC-08 conservadas como decisiones cerradas.
- TP01–TP61 automatizadas/técnicas aprobadas y TP62–TP64 aprobadas humanamente.
- Cero sobrepago, doble apertura/cierre/cobro, acceso cruzado o auditoría faltante.
- Regresión vigente completa, migraciones local/DEV alineadas y defectos no bloqueantes clasificados.
- Ninguna aceptación se crea hasta aprobación explícita del usuario.

## 6. Matriz requisito → diseño → tarea → prueba

| Requisitos | Diseño | Tareas | Pruebas |
|---|---|---|---|
| R01–R03 | D02–D03, D13 | T03–T04 | TP01–TP08 |
| R04–R08 | D04–D05, D11–D13 | T04–T05, T12 | TP09–TP18, TP56 |
| R09–R10 | D06, D13 | T06 | TP19–TP25 |
| R11–R12 | D07, D13 | T07 | TP26–TP30 |
| R13–R16 | D08, D13 | T08–T10 | TP31–TP44 |
| R17–R18 | D09 | T08–T10 | TP45–TP48 |
| R19–R20 | D10 | T11 | TP49–TP55 |
| R21 | D11 | T12 | TP56–TP58 |
| R22 | D12 | T10, T13–T14 | TP59–TP64 |

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
