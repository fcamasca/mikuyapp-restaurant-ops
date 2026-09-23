# MikuyApp — Plan y evidencia de prueba de capacidad (E1-T18)

**Estado: CERRADO.** Este documento cubre el diseño de la prueba de capacidad sobre `feature/E1-CashOperation`, el hallazgo de causa raíz que originó el correctivo E1-T18 (SQLSTATE `40001` interpretado por PostgREST 14 como fallo transitorio reintentable), y la evidencia completa de la campaña de capacidad ejecutada en DEV tras aplicar el correctivo (niveles 5/10/20/40 clientes concurrentes — secciones 11–22). No se modificó código productivo, migraciones, RPC, índices ni configuración de Supabase salvo la migración correctiva de T18 (sección 16–18), ya incorporada al repositorio por separado. Documento incorporado al repositorio como evidencia técnica de cierre de E1-T18.

## 0. Verificación de entorno (léase primero)

### 0.1 Qué dice la documentación del repo, con precisión

- **T09** (`docs/PM002_T09_EXECUTION.md`): crea `mikuyapp-prod` (ref `snfm…pavp`) vacío — sin migraciones, sin esquema, sin datos.
- **T10** (`docs/PM002_T10_EXECUTION.md`): aplica ahí las 28 migraciones versionadas y reconcilia el baseline técnico completo — 10 tablas, RLS 10/10, 27 policies, 17 funciones, 2 triggers, 15 índices explícitos, publicación `supabase_realtime` con `detalle_pedido`/`mesa`/`pedido`. El propio documento es explícito en que **no** se cargó `seed.sql`, cero locales/perfiles/pedidos/pagos y "Auth dashboard: cero usuarios". Es decir: **`mikuyapp-prod` no está vacío — tiene el esquema completo — pero no tiene datos ni usuarios**, así que no sirve como sustituto de DEV sin antes sembrarlo (fuera del alcance de esta tarea sin tu autorización, ya que implicaría escribir datos ahí).
- **T12** (`docs/PM002_T12_EXECUTION.md`): PM-002 sigue en `TRANSITIONING`. Cloudflare Preview quedó configurado contra DEV (proyecto compartido); **Cloudflare Production permaneció sin cambios sobre el proyecto actual compartido** (`ibfr…uinf`). No hubo cutover.
- No existe ningún documento posterior a T12 en el repo que registre un cutover ni declare el estado `SEPARATED`.

Conclusión de solo-documentación: la evidencia escrita no demuestra que el cutover de Production haya ocurrido, pero tampoco lo descarta con certeza — un cutover pudo haberse hecho fuera de este flujo documentado y no quedar registrado.

### 0.2 Verificación objetiva (no solo documental)

Pediste verificar si Cloudflare Production apunta hoy a `ibfrrifvhvtgcxfxuinf`, y detenerme si no podía comprobarlo objetivamente. Sí pude comprobarlo: abrí la URL productiva real (`https://mikuyapp.pages.dev/`, la misma que declara `README.md` como "Producción actual") en el navegador integrado y extraje, del bundle JS que el propio Cloudflare Pages Production sirve ahora mismo, cualquier referencia a un proyecto Supabase:

```
1) preview_start → https://mikuyapp.pages.dev/
2) document.querySelectorAll('script[src]') → https://mikuyapp.pages.dev/assets/index-5vrb77kv.js
3) fetch(esa URL) → texto del bundle (510 905 caracteres)
4) texto.match(/[a-z0-9]{15,25}\.supabase\.co/gi) → único resultado:
   "ibfrrifvhvtgcxfxuinf.supabase.co"
```

**Resultado objetivo, reproducible ahora mismo: el bundle que Cloudflare Production sirve hoy en `https://mikuyapp.pages.dev/` solo contiene el project ref `ibfrrifvhvtgcxfxuinf`. No aparece `snfm…pavp` (`mikuyapp-prod`) en ninguna parte del bundle.** Esto confirma, con evidencia directa y no solo documental, que **Cloudflare Production sigue sirviendo desde el mismo proyecto que usamos como DEV** — no hubo cutover, contradice la premisa de "DEV y PROD ya están separados".

Esto no significa necesariamente que haya tráfico real de clientes ahí — el único `local` sembrado en `ibfr…uinf` sigue siendo `MIKUY-DEMO` según `supabase/seed.sql`, y no tengo forma de saber desde aquí si se cargó algo más desde que se sembró. Pero si algo en este proyecto se rompe o se satura durante la prueba, el efecto no queda contenido en "DEV" — también es, hoy, el proyecto que sirve `mikuyapp.pages.dev`.

Dejo esto registrado como hecho verificado, no como bloqueo de mi parte: sigo el diseño sobre `ibfrrifvhvtgcxfxuinf` como me indicaste. Lo que pido en el checklist (sección 7) es que confirmes que autorizas la ejecución sabiendo esto — con esta evidencia ya no es "no se puede verificar", es "se verificó y Production está ahí".

## 1. Arquitectura relevante

### 1.1 Mapa de flujo

```
acción usuario (mozo/cocina/caja)
  → RPC de mutación (Postgres, SECURITY DEFINER, RLS + obtener_contexto_autenticado())
  → UPDATE/INSERT en detalle_pedido | pedido | mesa
  → Postgres emite evento de replicación lógica (publicación supabase_realtime)
  → Supabase Realtime reenvía el evento a TODO canal suscrito a esa tabla/evento,
    sin filtrar por fila ni por local_id
  → cada cliente conectado con un canal activo sobre esa tabla ejecuta su propio
    scheduleRefresh() (debounce ~80ms, por cliente) y dispara su propia RPC de
    lectura (obtener_tablero_cocina, getOrderDetails+getOrderReview, listado de
    caja, etc.)
  → cada una de esas RPC vuelve a evaluar RLS (obtener_contexto_autenticado())
    y a ejecutar el join correspondiente
```

Este es el hallazgo central para el diseño de la prueba: **el fan-out no está acotado por local_id en el registro de la suscripción** (`channel.on('postgres_changes', { event, schema: 'public', table }, callback)` en `src/services/operationsRealtimeService.ts`, sin cláusula `filter`). Un solo `UPDATE` legítimo en `detalle_pedido` puede convertirse en tantas RPC adicionales como clientes distintos tengan un canal abierto sobre esa tabla — mozo, cocina, caja y, potencialmente, otro local si compartiera el mismo proyecto. La cantidad de peticiones a Supabase no crece con la cantidad de clics, crece con `clics × clientes conectados`.

### 1.2 Canales Realtime por tipo de pantalla

| Pantalla | Archivo | Canal | Tablas/eventos escuchados | `initialRefresh` | Lectura disparada por señal |
|---|---|---|---|---|---|
| Cocina | `KitchenBoardPage.tsx` → `kitchenRealtimeService.ts` | `kitchen-board-signals` | `detalle_pedido`, `pedido`, `mesa` · INSERT/UPDATE | true (+ refresco en `SUBSCRIBED` y en reconexión) | RPC `obtener_tablero_cocina()` (join 4 tablas + RLS) |
| Mozo — pedido abierto | `WaiterOrderPage.tsx` | `waiter-order-{orderId}-signals` | mismas 3 tablas | false | `getOrderDetails` + `getOrderReview` (2 llamadas) |
| Mozo — tablero de mesas | `WaiterTablesPage.tsx` | `waiter-tables-signals` | mismas 3 tablas | false | listado de mesas/pedidos del local |
| Caja | `CashierPage.tsx` | `cashier-orders-signals` | mismas 3 tablas | false | listado de pedidos pendientes de cobro |
| Admin (`AdminOrdersPage.tsx`, `CashAdministrationPanel.tsx`) | — | — sin suscripción Realtime — | — | — | recarga manual (`load()`/botón) |

Los 4 primeros comparten exactamente las mismas 3 tablas y los mismos 2 eventos (`INSERT`, `UPDATE`), cada uno en su propio canal (`channel.subscribe` independiente), es decir, **4 suscripciones activas por cada combinación de 1 cocina + 1 mozo con pedido abierto + 1 tablero de mesas + 1 caja abiertos simultáneamente** — y eso antes de contar que puede haber varios mozos y varias cocinas a la vez.

### 1.3 Acción de negocio → RPC

| Acción | RPC | Notas |
|---|---|---|
| Mozo abre/recupera mesa | `crear_o_recuperar_pedido_mesa` | |
| Mozo agrega producto | `agregar_detalle_pedido` | guard de doble clic por producto (`pendingProductIds`) |
| Mozo cambia cantidad / observación / retira detalle | `actualizar_detalle_abierto` (vía `updateOpenDetail`) / `eliminar_detalle_abierto` (vía `removeOpenDetail`) | guard por `detail.id` |
| Mozo envía a cocina | `enviar_pedido_cocina` | guard `sendingRef` |
| Cocina recibe / inicia preparación / marca listo | `actualizar_estado_detalle_cocina` | `UPDATE ... FOR UPDATE` con concurrencia optimista (SQLSTATE `40001`); guard `pendingTransitions` por `detalle_id` |
| Mozo entrega pedido | `entregar_pedido` | guard `deliveringRef` |
| Mozo libera mesa vacía | `liberar_mesa_pedido_vacio` | guard `releasingRef` |
| Caja cobra / abre sesión / registra movimiento | RPC internas de `cashierService.ts` (wrapper genérico `client.rpc(name, args)`) | fuera del alcance de E1 revisar en detalle para esta prueba, pero disparan `UPDATE` en `pedido` igual que el resto |
| Admin anula pedido / decide descuento | `anular_pedido_supervisado`, `rpc_decidir_descuento_pedido` | sin Realtime propio, pero sus `UPDATE` sí disparan el fan-out hacia cocina/mozo/caja |

Cada fila de esta tabla es una RPC `SECURITY DEFINER` que empieza con una llamada a `obtener_contexto_autenticado()` (join simple por `auth.uid()`, cubierto por la PK de `perfil_usuario`) antes de la lógica propia.

### 1.4 Protecciones ya existentes (confirmadas en la revisión anterior de este mismo hilo)

- **Guard de doble clic por id**, síncrono, antes del primer `await`, en todos los botones de mutación (mozo/cocina/caja/admin) — no relanzan la misma operación si ya está en curso.
- **Coalescing de refresh en vuelo por cliente**: `operationsRealtimeService.ts` colapsa refrescos repetidos del mismo cliente en una sola llamada en curso + como máximo una encolada (`refreshInFlight`/`refreshAgain`). Esto protege contra clics repetidos en "Actualizar", pero **no protege entre clientes distintos** — cada cliente coalesce sus propias señales, no las de los demás.
- **Debounce de 80ms** entre la señal de Postgres y el refresh, también por cliente.

Ninguna de estas protecciones acota el fan-out entre clientes descrito en 1.1. Es la hipótesis más fuerte hasta ahora, pero sigue siendo una hipótesis: no la voy a dar por buena sin la prueba.

### 1.5 Índices y consultas

Revisé `supabase/migrations/20260823235106_h1_initial_schema.sql` contra las columnas usadas en los `WHERE`/`JOIN` de `obtener_tablero_cocina()` y `actualizar_estado_detalle_cocina()`: existen índices sobre `pedido(local_id, estado, creado_en)`, `pedido(mesa_id, estado)`, `detalle_pedido(pedido_id)` y `detalle_pedido(producto_id)`. No encontré un filtro de esas RPC sobre una columna sin índice evidente. No descarto costos por el volumen de RLS (`obtener_contexto_autenticado()` se re-evalúa en cada llamada), pero no vi nada estructuralmente costoso a simple lectura. Esto lo confirma o lo descarta mejor `pg_stat_statements` durante la prueba (sección 3).

### 1.6 Restricción de datos existente

`supabase/seed.sql` siembra un único local (`MIKUY-DEMO`) con **6 mesas** (`M01`–`M06`) y 4 usuarios de prueba (`H2_ADMIN_*`, `H2_MOZO_*`, `H2_COCINA_*`, `H2_CAJA_*` en `.env.local`, ya pensados para "verificaciones" según `PM002_ENVIRONMENTS.md`). Esto acota el diseño: no puedo tener 40 pedidos abiertos simultáneos distintos con los datos actuales — cada mesa exige liberarse antes de reabrirse. El diseño de la sección 2 separa por eso dos variables en vez de una sola "concurrencia".

## 2. Diseño de la prueba

### 2.1 Tres métricas separadas, no mezcladas

Todo el diseño de aquí en adelante distingue tres cosas que no deben mezclarse en un solo número:

1. **Conexiones Realtime activas** — cuántos canales/suscripciones hay abiertos, independientemente de si generan tráfico.
2. **Refresh/RPC generadas** — cuántas lecturas dispara el fan-out (sección 1.1) como consecuencia de señales Realtime recibidas, separado de:
3. **Operaciones de negocio ejecutadas** — cuántas mutaciones reales (crear pedido, enviar a cocina, transicionar detalle, entregar, cobrar) se ejecutaron, con su propia latencia.

Cada tabla de resultados (sección 5) reporta las tres por separado, nunca combinadas en un total único, para poder atribuir un aumento de CPU/latencia a una de las tres y no a "más carga" en general.

### 2.2 Dos variables independientes

- **Conexiones Realtime activas** (pantallas suscritas, no necesariamente dueñas de un pedido): es la variable que prueba la hipótesis de fan-out. Escala 5 → 10 → 20 → 40.
- **Throughput de negocio** (pedidos/min, transiciones de cocina/min): acotado por las 6 mesas existentes en un ciclo cerrado continuo (abrir → agregar → enviar → recibir → preparar → listo → entregar → cobrar → liberar → repetir). No necesita 40 mesas para generar carga sostenida de eventos.

### 2.3 Baseline en reposo y enfriamiento entre niveles

Antes de cada escenario (A, B, C), y antes del primer nivel de cada uno, corro una ventana de **baseline en reposo** (~60s, ajustable): se abren las conexiones Realtime que ese nivel necesita, pero no se ejecuta ninguna operación de negocio. Esto mide el costo de mantener N conexiones abiertas sin tráfico (latencia base, RPC generadas — debería ser ~0 si no hay señales —, y si el Dashboard lo permite, CPU en reposo con esas conexiones). Sirve como línea de comparación para cada nivel de carga posterior.

Entre el nivel N y el nivel N+1 de cualquier escenario, inserto un **período de enfriamiento** (propongo 60–120s, ajustable según lo que se observe): se detienen las operaciones de negocio nuevas, se deja drenar lo que esté en vuelo, y se vuelve a tomar una lectura corta de reposo antes de subir el nivel. El objetivo es no atribuir al nivel N+1 carga residual (conexiones cerrando, RPC en cola, locks) que en realidad viene del nivel N. Si el enfriamiento muestra que las métricas no vuelven cerca del baseline en el tiempo esperado, lo registro como hallazgo en sí mismo (posible degradación sostenida) antes de continuar.

Separarlas permite responder la pregunta que pediste sin asumir la respuesta: si el CPU sube con conexiones y el throughput de negocio se mantiene fijo, el cuello de botella es el fan-out de Realtime; si sube con el throughput y las conexiones se mantienen fijas, el cuello de botella está en las RPC/queries; si sube con ambas por separado, es una combinación.

### 2.4 Escenarios

| Escenario | Qué mide | Diseño |
|---|---|---|
| **A — Fan-out** | Efecto multiplicador de Realtime | Throughput de negocio fijo y modesto (1 bot mozo + 1 bot cocina + 1 bot caja operando un ciclo lento, ~1 transición cada 2s). Se escala el número de clientes "oyentes" adicionales conectados en niveles 5 → 10 → 20 → 40 — ver 2.5 para el comportamiento exacto que deben reproducir (no es un contador pasivo de eventos). |
| **B — Throughput de negocio** | Costo real de las RPC bajo uso legítimo | Número de clientes conectados fijo y realista (6–8: 2 mozo, 2 cocina, 2 caja, 1 admin). Se escala la tasa de operaciones de negocio (pedidos creados/min, detalles transicionados/min) usando las 6 mesas en ciclo cerrado continuo, cada vez más rápido. |
| **C — Réplica del incidente** | Reproducir la forma del incidente original | Número de clientes moderado (~6–10, similar a lo que habría en pruebas reales) + ráfaga: varios pedidos creados casi simultáneamente y cocina transicionando varios detalles en rápida sucesión (sin doble clic sobre el mismo detalle, ya que ese guard existe — sí clics rápidos sobre detalles *distintos*, que es lo que el guard no impide). |

### 2.5 Comportamiento exacto de los "clientes oyentes" (escenario A)

Corrección importante sobre el borrador anterior: un cliente oyente **no se limita a contar eventos Realtime** — eso mediría solo conexiones/eventos, no el costo real del patrón que queremos investigar (`cambio DB → evento Realtime → N clientes → N refresh/RPC`). Cada bot oyente del escenario A debe comportarse exactamente como la pantalla real que impersona:

- se suscribe al mismo canal, mismas tablas (`detalle_pedido`, `pedido`, `mesa`) y mismos eventos (`INSERT`, `UPDATE`) que esa pantalla real (`kitchen-board-signals` / `waiter-tables-signals` / `waiter-order-{id}-signals` / `cashier-orders-signals`, repartidos entre los N oyentes en la misma proporción con que se usarían en operación real);
- al recibir una señal, aplica el **mismo debounce y coalescing** que `operationsRealtimeService.ts` (`scheduleRefresh` con el mismo `debounceMs`, y el mismo patrón `refreshInFlight`/`refreshAgain` para colapsar señales repetidas mientras una lectura está en curso) — reutilizo esa lógica tal cual, no una reimplementación aproximada;
- tras el debounce, ejecuta **la misma RPC de lectura** que ejecutaría esa pantalla real (`obtener_tablero_cocina()` para un oyente-cocina; `getOrderDetails`+`getOrderReview` para un oyente-mozo-pedido; la consulta de tablero de mesas para un oyente-mozo-mesas; el listado de pendientes de cobro para un oyente-caja);
- **nunca ejecuta una mutación** — ni transiciona pedidos, ni agrega productos, ni cobra. Es oyente puro, igual que una pantalla real que nadie está tocando en ese momento.

Con este diseño, la cuenta de "refresh/RPC generadas" del escenario A (métrica 2 de la sección 2.1) es el dato central: si crece linealmente con el número de oyentes para un mismo throughput de negocio fijo, confirma la hipótesis de fan-out con evidencia real, no supuesta.

### 2.6 Script de carga (aislado, no forma parte del repo)

Propongo un script Node/TypeScript usando `@supabase/supabase-js` (ya es dependencia del proyecto, misma versión), que:

- corre **fuera del repo**, en mi entorno de trabajo en la nube (no en tu máquina ni en `feature/E1-CashOperation`), y habla por HTTPS a `VITE_SUPABASE_URL` con `VITE_SUPABASE_PUBLISHABLE_KEY` — las mismas credenciales públicas que usa la app, nada nuevo ni administrativo;
- autentica bots como los usuarios de prueba `H2_MOZO_*`/`H2_COCINA_*`/`H2_CAJA_*` ya existentes en DEV (pensados para esto según `PM002_ENVIRONMENTS.md`);
- reproduce las RPC reales de la tabla 1.3 en el orden real del flujo (no inventa endpoints ni pega directo a las tablas);
- para los "clientes oyentes" del escenario A, replica el comportamiento descrito en 2.5 (debounce/coalescing + RPC de lectura real, cero mutaciones) — no un contador de eventos;
- mide, por separado, las tres métricas de 2.1: conexiones activas, refresh/RPC generadas (con su latencia, p50/p95 por ventana), y operaciones de negocio ejecutadas (con su propia latencia);
- toma la lectura de baseline en reposo y respeta el enfriamiento entre niveles descritos en 2.3;
- se detiene solo (sección 4) si ve errores/timeouts crecientes, sin necesidad de que yo lo mire en tiempo real.

No lo voy a escribir dentro de tu carpeta de trabajo ni lo voy a commitear. Si más adelante quieres conservarlo, te lo entrego aparte y decides tú si lo integras (p. ej. como herramienta de desarrollo, no como parte de `src/`).

## 3. Métricas: qué puedo medir yo y qué necesito que observes tú

Con la clave pública (`VITE_SUPABASE_PUBLISHABLE_KEY`, nivel cliente/anon + RLS) puedo medir desde el script: latencia por RPC, tasa de error/timeout por nivel, cantidad de eventos Realtime recibidos, reconexiones del lado cliente, y — indirectamente — si `actualizar_estado_detalle_cocina` empieza a devolver `40001` (conflicto de concurrencia) con más frecuencia de la esperada.

**No puedo obtener programáticamente** (la clave pública no tiene permisos de administración ni acceso a catálogos del sistema):

- % de CPU del compute — solo visible en **Supabase Dashboard → Reports/Database**.
- `pg_stat_activity`, `pg_stat_statements`, locks, conexiones activas del pooler — requieren el **SQL Editor del Dashboard** o una conexión directa con credenciales administrativas que no tengo ni voy a pedir por este medio.

Si apruebas el plan, te dejo preparadas 3–4 consultas SQL cortas (contra vistas que ya trae Supabase: `pg_stat_statements`, `pg_stat_activity`) para que las corras tú en el SQL Editor en paralelo a cada nivel de carga, y me pegues el resultado — o, si prefieres, cuando lleguemos a ese punto intento abrir el Dashboard con el navegador integrado (si ya tienes sesión iniciada) y leerlas yo mismo. Lo decidimos en el checklist de la sección 7, no ahora.

## 4. Criterio de parada

Detengo o bajo el nivel de carga de inmediato si el script observa, sostenido por más de ~10s:

- tasa de error/timeout de RPC por encima de un umbral bajo (propongo 5%, ajustable);
- crecimiento de p95 más allá de ~3× el p95 del nivel anterior;
- desconexiones/reconexiones de canal Realtime;
- SQLSTATE inesperado distinto de `PT409` (que es el conflicto funcional esperado desde el correctivo E1-T18, 22/09/2026 — ver sección 17). **Cualquier `40001` observado a partir de esta fecha se trata como error/regresión, no como conflicto esperado** (antes del correctivo era al revés; ver sección 16 para el porqué).

Y me detengo también si tú, mirando el Dashboard en paralelo, me dices que el CPU ronda u supera 80%, aunque el script todavía no vea señales — tu observación manda sobre la del script.

No subo de 5→10→20→40 automáticamente: cada salto lo doy solo si el nivel anterior terminó limpio.

## 5. Qué voy a entregar al terminar cada nivel

Por cada nivel ejecutado, reporto las tres métricas de 2.1 siempre por separado, nunca mezcladas en un total:

| Categoría | Qué incluye |
|---|---|
| Conexiones Realtime | canales activos, reconexiones, baseline en reposo del nivel |
| Refresh/RPC generadas | total, desglosadas por pantalla/tipo de oyente, latencia media y p95, errores/timeouts |
| Operaciones de negocio | pedidos/transiciones ejecutados, duración, latencia media y p95 de la mutación, errores |

Además: duración del nivel, resultado del enfriamiento previo (¿volvió al baseline?), y — cuando tú me las compartas — lo que muestre `pg_stat_activity`/`pg_stat_statements` en ese momento. Al final separo explícitamente **hechos medidos** de **hipótesis** y ordeno las hipótesis por evidencia, sin asumir de entrada que el problema es el doble clic, el fan-out de Realtime, o el compute — dejo que los datos lo digan.

## 6. Restricciones que respeto

Trabajo sobre `feature/E1-CashOperation`, sin tocar `main`. No cambio comportamiento funcional de E1. No implemento optimizaciones. No toco queries, RPC, índices ni Realtime. No toco migraciones existentes ni aplico nuevas. No cambio configuración de Supabase. No subo el compute. Solo contra DEV. No uso datos productivos reales (el único local sembrado es demo). El script de carga queda aislado y no se commitea sin tu autorización. Al terminar, el repositorio funcional queda igual que hoy — solo entrego este plan y, después, el informe de resultados.

## 7. Checklist para autorizar la ejecución

Antes de correr nada, necesito que confirmes:

1. Adelante contra `ibfrrifvhvtgcxfxuinf` tal como está, sabiendo — con evidencia verificada, no solo documental (sección 0.2) — que Cloudflare Production sigue sirviendo desde este mismo proyecto hoy.
2. Los niveles de "clientes concurrentes" del escenario A (5→10→20→40) son conexiones Realtime oyentes que replican el comportamiento real de cada pantalla (debounce + RPC de lectura, sección 2.5), no pedidos abiertos simultáneos.
3. Cómo prefieres cubrir las métricas de Dashboard (sección 3): te paso las queries y las corres tú en paralelo, o intento yo con el navegador integrado.
4. Umbral de error/timeout para detener automáticamente (propuse 5%; dime si prefieres otro).

Con eso confirmado, ejecuto el nivel 1 (5 clientes) y te muestro el resultado antes de subir al siguiente.

### 7.1 Aprobación registrada (2026-09-22)

El usuario aprobó explícitamente la ejecución, con esta justificación textual:

> "Confirmado por el usuario: actualmente no existe operación productiva real en MikuyApp. Aunque Cloudflare Production apunte a `ibfrrifvhvtgcxfxuinf`, ese proyecto puede utilizarse para las pruebas de capacidad porque hoy funciona como entorno de desarrollo/pruebas y no existen datos ni usuarios productivos que debamos proteger. El plan de capacidad queda aprobado para ejecución progresiva sobre `ibfrrifvhvtgcxfxuinf`."

Resolución de los 4 puntos del checklist con esa aprobación:

1. **Confirmado.** Se ejecuta contra `ibfrrifvhvtgcxfxuinf` pese a que Production sirve hoy desde el mismo proyecto (evidencia objetiva de la sección 0.2), porque el usuario confirma que no hay datos ni usuarios productivos reales que proteger en este momento.
2. **Confirmado.** Los "clientes concurrentes" del escenario A son conexiones Realtime oyentes fieles al comportamiento de cada pantalla (sección 2.5), no pedidos simultáneos.
3. **Resuelto:** preparo las consultas SQL (sección 3) para que el usuario las corra en el SQL Editor del Dashboard en paralelo a la ejecución; no se abre el Dashboard con el navegador integrado en esta ronda.
4. **Sin cambios:** se mantiene el umbral propuesto de 5% de error/timeout como disparador automático de parada (sección 4), salvo indicación contraria.

Alcance autorizado para esta ejecución: únicamente **baseline en reposo + nivel 1 (5 clientes)**. No se avanza a 10 clientes sin una aprobación explícita adicional del usuario, revisando primero los resultados del nivel 1.

## 8. Consultas SQL para el Dashboard (SQL Editor)

Para correr en paralelo a cada nivel de carga, en `Supabase Dashboard → SQL Editor` del proyecto `ibfrrifvhvtgcxfxuinf`. No modifican nada (todas son `select`).

### 8.1 Snapshot de conexiones activas (detalle)

```sql
select
  pid,
  usename,
  application_name,
  client_addr,
  backend_type,
  state,
  wait_event_type,
  wait_event,
  now() - query_start as query_duration,
  now() - state_change as state_duration,
  left(query, 120) as query_preview
from pg_stat_activity
where datname = current_database()
order by query_start asc nulls last;
```

### 8.2 Conteo de conexiones por tipo/estado

```sql
select
  backend_type,
  state,
  count(*) as conexiones
from pg_stat_activity
where datname = current_database()
group by backend_type, state
order by conexiones desc;
```

### 8.3 Top RPC del flujo por tiempo total (requiere `pg_stat_statements` habilitado)

```sql
select
  calls,
  round(total_exec_time::numeric, 2) as total_ms,
  round(mean_exec_time::numeric, 2) as mean_ms,
  round(max_exec_time::numeric, 2) as max_ms,
  rows,
  left(query, 150) as query_preview
from pg_stat_statements
where query ilike any (array[
  '%obtener_tablero_cocina%',
  '%actualizar_estado_detalle_cocina%',
  '%crear_o_recuperar_pedido_mesa%',
  '%agregar_detalle_pedido%',
  '%enviar_pedido_cocina%',
  '%entregar_pedido%',
  '%obtener_pedidos_pendientes_pago_caja%',
  '%rpc_registrar_cobro_pedido%',
  '%rpc_obtener_sesion_caja_activa%',
  '%rpc_abrir_sesion_caja%',
  '%rpc_obtener_resumen_sesion_caja%',
  '%rpc_obtener_movimientos_sesion_caja%',
  '%rpc_obtener_reportes_sesion_caja%'
])
order by total_exec_time desc
limit 20;
```

### 8.4 Locks/esperas (bloqueos entre conexiones)

```sql
select
  blocked.pid as blocked_pid,
  blocked.query as blocked_query,
  blocking.pid as blocking_pid,
  blocking.query as blocking_query,
  blocked.wait_event_type,
  blocked.wait_event
from pg_stat_activity blocked
join pg_locks bl on bl.pid = blocked.pid and not bl.granted
join pg_locks kl on kl.locktype = bl.locktype
  and kl.database is not distinct from bl.database
  and kl.relation is not distinct from bl.relation
  and kl.page is not distinct from bl.page
  and kl.tuple is not distinct from bl.tuple
  and kl.transactionid is not distinct from bl.transactionid
  and kl.granted
join pg_stat_activity blocking on blocking.pid = kl.pid
where blocked.datname = current_database();
```

Sugerencia de uso: corre 8.1/8.2 una vez en el baseline en reposo (guarda el resultado como referencia), y de nuevo durante el nivel 1. 8.3 acumula desde que se resetee `pg_stat_statements` o desde el último reinicio del compute, así que lo más útil es compararlo antes/después del nivel, no en un instante puntual. 8.4 solo importa si aparecen filas (si vuelve vacío, no hay bloqueos en ese momento).

## 9. Bloqueo encontrado al intentar ejecutar (2026-09-22)

Al intentar autenticar los bots con los usuarios de prueba de `.env.local` (`H2_MOZO_*`, `H2_COCINA_*`, `H2_CAJA_*`, y también `H2_ADMIN_*` como control) contra `https://ibfrrifvhvtgcxfxuinf.supabase.co/auth/v1/token`, **las 4 cuentas devuelven `400 invalid_credentials`** ("Invalid login credentials"). Esto no es un error de red ni de proxy: es una respuesta 400 válida y completa del propio servidor de Auth de Supabase.

**Hecho medido:** ninguna de las 4 credenciales de `.env.local` autentica hoy contra este proyecto.

**Lo que NO hice:** no intenté un `signUp` de prueba para diferenciar "usuario no existe" de "contraseña incorrecta", porque un `signUp` exitoso crearía una cuenta real en el proyecto — eso es una modificación de datos/estado que no está autorizada y que además excede lo que un intento de login debería hacer. Tampoco intenté ningún flujo de reseteo de contraseña.

**Por qué me detengo aquí:** no puedo ejecutar ni el baseline ni el nivel 1 sin bots autenticados como mozo/cocina/caja (las RPC de negocio y varias de lectura exigen rol autenticado vía `obtener_contexto_autenticado()`). Necesito que confirmes una de estas opciones antes de continuar:

1. Las credenciales en `.env.local` están desactualizadas (se rotaron en el Dashboard) — si es así, ¿me compartes las vigentes o las actualizas tú en el archivo?
2. Estas cuentas nunca se crearon como usuarios de Auth en `ibfrrifvhvtgcxfxuinf` (solo existen filas de `perfil_usuario`/seed, sin su contraparte en `auth.users`) — si es así, ¿las creas tú desde el Dashboard (Authentication → Users) o me autorizas a hacerlo yo mismo con `supabase.auth.signUp` sabiendo que eso sí crea cuentas reales?
3. Prefieres que use otras credenciales de prueba distintas a las de `.env.local`.

En cuanto confirmes, ejecuto baseline + nivel 1 tal como se aprobó en la sección 7.1.

## 10. Pausa solicitada (2026-09-22)

El usuario pidió detener toda ejecución hasta validar credenciales, con estas restricciones explícitas: no `signUp`, no crear usuarios Auth, no modificar `perfil_usuario`, no cambiar UUID, no modificar configuración de Supabase, no continuar con baseline ni nivel 1 hasta validar los correos vigentes en Supabase DEV. Motivo señalado: los correos de `.env.local` podrían ser antiguos por una homologación posterior de correos DEV/PROD, y las cuentas de prueba ya provisionadas deben conservar su UUID de Auth asociado a `perfil_usuario` (no recrearse).

Variables de `.env.local` usadas en el intento de login de esta ronda (solo nombres de variable y correo, sin contraseñas):

| Rol | Variable de correo | Valor usado | Variable de contraseña |
|---|---|---|---|
| mozo | `H2_MOZO_EMAIL` | `mozo@mikuy.com` | `H2_MOZO_PASSWORD` (no se muestra) |
| cocina | `H2_COCINA_EMAIL` | `cocina@mikuy.com` | `H2_COCINA_PASSWORD` (no se muestra) |
| caja | `H2_CAJA_EMAIL` | `caja@mikuy.com` | `H2_CAJA_PASSWORD` (no se muestra) |
| admin (control) | `H2_ADMIN_EMAIL` | `admin@mikuy.com` | `H2_ADMIN_PASSWORD` (no se muestra) |

Queda en pausa: no se ejecuta baseline ni nivel 1, no se toca Auth/`perfil_usuario`/configuración de Supabase, hasta que el usuario confirme los correos vigentes.

## 11. Resultados — Baseline en reposo + Nivel 1 (5 clientes) (2026-09-22)

Ejecutado contra `ibfrrifvhvtgcxfxuinf`, tras corregir los correos de `.env.local` a `*@dev.mikuyapp.com` (contraseñas sin cambios). Login de control confirmado: `admin`, `mozo`, `cocina`, `caja` autentican correctamente con los correos nuevos.

**Duración real de cada tramo:** baseline en reposo ≈ 89s · carga de nivel 1 ≈ 112s · enfriamiento ≈ 93s (duración total de la corrida ≈ 4 min 54 s).

### 11.1 Conexiones Realtime

- 5/5 conexiones oyentes (2 cocina, 2 mozo-mesas, 1 caja) alcanzaron `SUBSCRIBED` sin errores.
- **0 reconexiones** durante todo el ensayo (baseline + carga + enfriamiento).
- Las 5 se cerraron limpiamente (`CLOSED`) al terminar, sin quedar colgadas.

### 11.2 Refresh/RPC generadas (fan-out)

| Fase | Total refresh/RPC | Desglose | Latencia media | p95 | Errores |
|---|---|---|---|---|---|
| Baseline en reposo | 9 | 1 por cada uno de los 5 oyentes al conectar (caja generó 5, por tener ya una sesión abierta de actividad previa) | 588 ms | 1187 ms | 0 |
| Nivel 1 (carga) | 172 | cocina 66 · mozo-mesas 66 · caja 40 (8 invocaciones × 5 RPC c/u) | 408 ms | 784 ms | 0 |
| Enfriamiento | 4 | residual, cayó a ~0 rápido tras detener el ciclo de negocio | 484 ms | 813 ms | 0 |

**Hecho medido, no hipótesis:** con throughput de negocio fijo (un ciclo cada ~18s: 10 pasos a 2s cada uno), 5 oyentes generaron **172 refresh/RPC frente a 42 operaciones de negocio** — una razón de ≈4.1 lecturas disparadas por cada mutación real. Esto es consistente con la hipótesis de fan-out (cambio → N oyentes → N refresh), pero **con un solo nivel no alcanza para confirmar que escala linealmente con N**; eso lo decide comparar contra los niveles 10/20/40 cuando se autoricen.

**Hallazgo aparte, no relacionado con concurrencia:** la lectura del tablero de mesas de mozo (`read:mozo:table_board`) fue sistemáticamente la más lenta de las tres — 1160 ms de media en baseline (sin carga) y 655 ms de media en el nivel 1 — más lenta que el tablero de cocina (519 ms / 255 ms) y que las lecturas de caja (~230–540 ms) en las mismas condiciones. Como esto se observa incluso en baseline (0 tráfico de negocio, solo 2 oyentes), **no es un efecto de la carga de este nivel**: es un costo estructural de esa lectura en particular (2 consultas en paralelo + 2 adicionales condicionales cuando hay pedidos vigentes). Queda como hipótesis a revisar con `pg_stat_statements`, no como hecho explicado.

### 11.3 Operaciones de negocio

- **4 ciclos completos** (abrir mesa M01 → agregar producto → enviar a cocina → 3 transiciones de cocina → entregar → cobrar TOTAL en efectivo) + 2 pasos de un 5º ciclo en curso al momento de detener.
- 42 operaciones de negocio ejecutadas, **0 errores, 0 `40001` de conflicto** (no hubo concurrencia sobre el mismo pedido/detalle, como se esperaba con un solo bot de negocio).
- Latencia: media 296 ms · p50 256 ms · p95 413 ms.
- Solo se usó la mesa M01 (estaba `LIBRE`); no se tocaron M02, M03 ni M06, que ya estaban en `PENDIENTE_PAGO`/`PEDIDO_LISTO` por actividad previa al test (dato observado, no generado por este ensayo).

### 11.4 Errores, timeouts, criterio de parada

Ningún criterio de parada de la sección 4 se activó: 0% de error/timeout, sin crecimiento anómalo de p95 entre baseline y carga, sin desconexiones de canal, sin SQLSTATE inesperado. **No fue necesario detener ni bajar el nivel.**

### 11.5 Lo que no pude medir yo — pendiente de tu lado

No tengo acceso a CPU% ni a `pg_stat_activity`/`pg_stat_statements` (sección 3). Las 4 consultas de la sección 8 quedaron listas; si las corriste en paralelo a esta ejecución (aprox. `17:30:05` a `17:35:00` UTC del 2026-09-22), compárteme el resultado o el % de CPU que viste en Dashboard → Reports/Database para esa ventana. Sin eso, esta sección del informe queda con hechos de cliente únicamente.

### 11.6 Hechos medidos vs. hipótesis — resumen

**Hechos medidos (nivel 1, 5 oyentes):** conexión limpia sin reconexiones; 0 errores en 42 operaciones de negocio y 172 refresh/RPC; razón fan-out ≈4.1x lecturas por mutación; el tablero de mozo es la lectura más lenta de las tres en toda condición observada; sistema completo (mozo→cocina→caja) se mantiene consistente y sin conflictos de concurrencia con un solo bot de negocio.

**Hipótesis aún no confirmadas ni descartadas:** (a) que la razón de fan-out (≈4.1x en este nivel) escale linealmente con el número de oyentes — requiere niveles 10/20/40; (b) que el costo estructural del tablero de mozo sea por las 2 consultas condicionales adicionales (detalle_pedido + `obtener_creadores_pedidos_vigentes`) y no por falta de índice — requiere `pg_stat_statements`; (c) que el incidente original de CPU alto se explique por fan-out, por el volumen de RPC, o por una combinación — con un solo nivel limpio todavía no hay evidencia de estrés real, así que ninguna hipótesis del incidente se confirma ni se descarta con este resultado.

**No avanzo a nivel 2 (10 clientes) sin tu aprobación explícita, según lo acordado.**

## 12. Escenario C — Réplica del incidente (ráfagas de cocina, 5 clientes) (2026-09-22)

Motivo, según lo señalado: el incidente no fue un doble clic repetido sobre el mismo producto, sino ráfagas de transiciones rápidas de cocina sobre **detalles distintos** (`Recibir → En preparación → Listo` pulsado rápido sobre varios productos seguidos). El guard por `detalle_id` no protege contra ese patrón porque cada llamada apunta a un detalle diferente. Este escenario reproduce exactamente eso, sin tocar el guard ni fabricar dobles envíos sobre el mismo detalle.

**Diseño:** se mantuvieron las 5 conexiones oyentes del nivel 1 (2 cocina, 2 mozo-mesas, 1 caja). Se prepararon 3 pedidos reales (mesas M01, M04, M05) con múltiples productos distintos cada uno, enviados a cocina, y luego se ejecutaron las transiciones de cocina **por oleadas concurrentes** (`Promise.all` sobre todos los `detalle_id` a la vez, no una llamada cada 2s): oleada 1 = todos los detalles `ENVIADO→RECIBIDO_COCINA` a la vez, oleada 2 = todos `RECIBIDO_COCINA→EN_PREPARACION`, oleada 3 = todos `EN_PREPARACION→LISTO`. Cada detalle recibe cada transición **una sola vez**, en su orden válido — no hay reenvío duplicado sobre el mismo detalle en ningún punto.

### 12.1 Ráfaga B1 — moderada (15 detalles)

| Oleada | Detalles | OK | Fallidas | Duración | Ops/seg |
|---|---|---|---|---|---|
| ENVIADO→RECIBIDO_COCINA | 15 | 15 | 0 | 601 ms | 25.0 |
| RECIBIDO_COCINA→EN_PREPARACION | 15 | 15 | 0 | 325 ms | 46.1 |
| EN_PREPARACION→LISTO | 15 | 15 | 0 | 239 ms | 62.8 |

Total: 45 transiciones en ~1.17 s (además de las 3 llamadas de apertura/envío previas, no contadas como ráfaga). Latencia de las transiciones: media 340 ms, p50 239 ms, p95 582 ms. **0 errores, 0 `40001`, 0 reconexiones.**

Refresh/RPC generadas por la ráfaga (con el debounce de 80 ms ya asentado): **8 en total** — 4 de `obtener_tablero_cocina()` (2 oyentes cocina) + 4 de tablero de mozo (2 oyentes mozo) — **0 de caja** (ver 12.3). Latencia de esas 8 lecturas: media 302 ms, p50 359 ms, p95 539 ms.

### 12.2 Ráfaga B2 — mayor (30 detalles, el doble de B1)

Se agregaron 30 detalles nuevos (10 productos × 3 pedidos), sin tocar ninguno de los 15 de B1, y se repitieron las 3 oleadas.

| Oleada | Detalles | OK | Fallidas | Duración | Ops/seg |
|---|---|---|---|---|---|
| ENVIADO→RECIBIDO_COCINA | 30 | 30 | 0 | 591 ms | 50.8 |
| RECIBIDO_COCINA→EN_PREPARACION | 30 | 30 | 0 | 342 ms | 87.7 |
| EN_PREPARACION→LISTO | 30 | 30 | 0 | 328 ms | 91.5 |

Total: 90 transiciones en ~1.26 s. Latencia de las transiciones: media 349 ms, p50 303 ms, p95 569 ms — **prácticamente igual que B1** (incluso el throughput por segundo subió). **0 errores, 0 `40001`, 0 reconexiones.**

Refresh/RPC generadas: de nuevo **8 en total** (4 cocina + 4 mozo, 0 caja) — igual que en B1 pese a duplicar el número de transiciones subyacentes. Latencia: media 410 ms, p50 464 ms, p95 684 ms.

### 12.3 Hallazgo reproducido: caja no generó refresh en ninguna de las dos ráfagas

El canal de caja llegó a `SUBSCRIBED` correctamente (confirmado en el log de conexión) y su función de lectura funciona bien cuando se la invoca manualmente (lo probé aparte, sin error). Aun así, **en ninguna de las dos ráfagas** (75 transiciones reales sobre `detalle_pedido` en total) el oyente de caja disparó ni un solo refresh — mientras que cocina y mozo sí, de forma consistente (4 cada uno, en ambas ráfagas). Esto se repitió igual en B1 y B2, así que no parece casualidad puntual.

**Hecho medido:** el oyente de caja no reaccionó a estos cambios de `detalle_pedido` en esta corrida, dos veces seguidas.
**Lo que NO es:** no es un error de mi script (el canal está `SUBSCRIBED`, la lectura funciona al invocarla a mano) ni una reconexión perdida (0 reconexiones registradas).
**Hipótesis abiertas, sin confirmar:** (a) alguna diferencia en cómo Supabase Realtime entrega eventos a ese canal bajo ráfaga versus los otros dos — no tengo forma de verlo sin acceso a logs del lado de Realtime/Dashboard; (b) alguna particularidad de mi implementación del oyente de caja (su lectura es la más pesada, hasta 5 RPC encadenadas) que de alguna manera no quedó bien instrumentada — lo revisé una vez a mano y funcionó, pero no descarto un problema sutil de temporización en mi propio arnés. No lo presento como conclusión, solo como algo a mirar antes de escalar a más oyentes, porque si es real, cambia la lectura del fan-out (no todos los tipos de pantalla amplifican igual).

### 12.4 Comparación contra el nivel 1

| | Nivel 1 (ritmo pausado, 1 transición/2s) | Escenario C, B1 (ráfaga, 15 detalles) | Escenario C, B2 (ráfaga, 30 detalles) |
|---|---|---|---|
| Patrón de negocio | 1 pedido, secuencial, con pausas de 2s entre pasos | 3 pedidos, transiciones simultáneas por oleada | igual, el doble de detalles |
| Transiciones de cocina | 12 (4 ciclos × 3) en ~112s | 45 en ~1.2s | 90 en ~1.3s |
| Errores/`40001` | 0 | 0 | 0 |
| Reconexiones | 0 | 0 | 0 |
| Refresh/RPC (5 oyentes) | 172 en ~112s (incluye caja activo) | 8 en ~10s tras la ráfaga | 8 en ~10s tras la ráfaga |
| Latencia mutación (avg/p95) | 296 / 413 ms | 340 / 582 ms | 349 / 569 ms |

**Hecho medido:** concentrar las mismas transiciones en ráfagas casi simultáneas (en vez de una cada 2s) no produjo errores ni degradación con 5 oyentes — ni siquiera duplicando el tamaño de la ráfaga. El número de refresh/RPC generado por el fan-out se mantuvo acotado (8) en ambas ráfagas gracias al debounce/coalescing de 80 ms del lado cliente, que colapsa múltiples señales cercanas en el tiempo en una sola lectura por oyente — funcionando tal como está diseñado, incluso bajo el patrón de "muchos botones distintos, rápido" que describiste.

**Hipótesis sobre el incidente original, actualizada con esta evidencia:** con 5 oyentes, ni el ritmo pausado (nivel 1) ni la ráfaga concentrada (escenario C) generan señales de estrés. Esto no descarta el fan-out como causa del incidente original — lo que sugiere es que, si el fan-out es la causa, probablemente necesita más oyentes conectados simultáneamente (el eje que subimos en los niveles 10/20/40, todavía no autorizados) para que el multiplicador N-oyentes × M-transiciones alcance un volumen que sí presione la CPU. La ráfaga por sí sola, con pocos oyentes, no parece ser suficiente.

### 12.5 Estado dejado en la base

Los 3 pedidos (mesas M01, M04, M05) quedaron con todos sus detalles en `LISTO` (mesas en estado `PEDIDO_LISTO`), listos para entregar y cobrar — no los entregué ni cobré porque no era parte de lo pedido en este escenario. Si prefieres que los complete (entregar + cobrar, liberando las mesas) o que los deje así para que los revises tú mismo en la app, dime cuál.

**No avanzo a nivel 2 (10 clientes) ni a ráfagas más grandes sin tu aprobación explícita.**

## 13. Causa del silencio de Caja (verificada) + Escenario C repetido en forma escalonada (2026-09-22)

### 13.1 Por qué el oyente de Caja no generó refresh en B1/B2 — verificado, no hipótesis

Leí las políticas RLS reales de `detalle_pedido`, `pedido` y `mesa` en las migraciones:

- **`detalle_pedido` no tiene ninguna política `select` para el rol CAJA.** Solo existen `detalle_pedido_select_mozo_local` (mozo) y `detalle_pedido_select_cocina_local` (cocina). Caja únicamente lee detalles a través de RPC `security definer` (`obtener_pedidos_pendientes_pago_caja`, etc.), nunca por `select` directo — y Supabase Realtime, para `postgres_changes`, filtra los eventos según la política RLS del rol que escucha. Sin política, **cero eventos de `detalle_pedido` llegan al oyente de caja, sin importar cuántas filas cambien.**
- **La política `pedido_select_caja_local_cobro`** (migración `20260830000100_h5_t06_cashier_realtime_signal_rls.sql`) solo permite a CAJA ver filas de `pedido` con `estado in ('ENTREGADO','PAGADO')`. Durante B1/B2 y esta repetición, los pedidos de prueba nunca salieron de `ENVIADO..LISTO` (no llamé `entregar_pedido` a propósito, para no mezclar la ráfaga con el flujo de entrega) — así que tampoco calificaban para esa política.
- `mesa` sí tiene una política de lectura amplia para cualquier rol autenticado del mismo local, pero ninguna transición de cocina modifica `mesa` (solo `sincronizar_estado_operativo_pedido` toca `pedido`, y solo cuando cambia el estado agregado).

**Verificación adicional (esta ronda):** instrumenté un contador de eventos *crudos* de Realtime (antes del debounce) por tipo de oyente. En la ráfaga escalonada de abajo, cocina y mozo recibieron **114 eventos crudos cada uno**; caja recibió **0** — no es que el evento llegara y el refresh se perdiera; el evento nunca llegó. Esto descarta un bug en mi arnés (el canal de caja llegó a `SUBSCRIBED` y su función de lectura funciona bien al invocarla a mano, ya lo había confirmado antes) y confirma que es el comportamiento real y esperado de `CashierPage` bajo este patrón de tráfico: **una pantalla de caja real, con estos mismos datos, tampoco se habría refrescado**, porque el fan-out de caja solo se activa cuando un pedido cruza a `ENTREGADO`/`PAGADO`, no por transiciones internas de cocina. No hace falta cambiar el bot de caja: ya reproduce fielmente las mismas llamadas que `CashierPage.refresh(false)` (sesión activa → pendientes de pago → si hay sesión: resumen + movimientos + reporte), confirmado línea por línea contra `CashierPage.tsx`.

### 13.2 Limpieza previa (no contada como medición)

Antes de repetir el escenario, completé los 3 pedidos de prueba por el flujo normal (`entregar_pedido` → `rpc_registrar_cobro_pedido` TOTAL en efectivo) y confirmé mesas M01/M04/M05 de vuelta en `LIBRE`. Esto quedó en una fase separada (`limpieza-no-medida`), excluida de todas las métricas de este informe.

### 13.3 Escenario C repetido — ráfaga escalonada (5 clientes, 15 detalles, mismo tamaño que B1)

Se armaron 3 pedidos nuevos (M01/M04/M05, 5 productos distintos cada uno = 15 detalles) y se ejecutaron las 45 transiciones (15 detalles × 3 pasos) **una a la vez, en orden round-robin entre detalles distintos** (nunca dos transiciones seguidas sobre el mismo detalle), con una pausa aleatoria de **100–250 ms** entre cada llamada — sin paralelismo, simulando un cocinero pulsando botones rápido pero sucesivo sobre varios tickets. Ventana real: **18:11:43–18:12:11 UTC** (≈27.3 s), más un minuto de enfriamiento posterior (18:12:11–18:13:11 UTC aprox.) para que pudieras observar el CPU en el Dashboard en ambas ventanas.

**Transiciones de cocina:** 45/45 OK, 0 errores, 0 `40001`, 0 reconexiones. Latencia: media 427 ms, p50 231 ms, p95 553 ms.

**Por rol, durante la ráfaga:**

| Rol | Eventos Realtime crudos recibidos | Refresh/RPC ejecutados | Latencia refresh (avg/p95) | Errores |
|---|---|---|---|---|
| Cocina (2 oyentes) | 114 | 54 | 245 / 358 ms | 0 |
| Mozo (2 oyentes) | 114 | 52 | 616 / 1078 ms | 0 |
| Caja (1 oyente) | 0 | 0 | — | 0 |

Enfriamiento: 0 eventos, 0 refresh, 0 reconexiones — drenó limpio.

### 13.4 Comparación contra B1/B2 — hallazgo principal de esta ronda

| | B1 (15 detalles, oleadas paralelas) | B2 (30 detalles, oleadas paralelas) | C2 (15 detalles, escalonado 100–250ms) |
|---|---|---|---|
| Duración de la ráfaga | ~1.2 s | ~1.3 s | ~27.3 s |
| Transiciones | 45 | 90 | 45 |
| Errores | 0 | 0 | 0 |
| Latencia transición (avg/p95) | 340 / 582 ms | 349 / 569 ms | 427 / 553 ms |
| Refresh/RPC generadas (cocina+mozo) | 8 (4+4) | 8 (4+4) | 106 (54+52) |
| Refresh/RPC de caja | 0 | 0 | 0 |

**Hecho medido, no hipótesis:** para el mismo número de transiciones (45), el patrón **escalonado generó ~13 veces más refresh/RPC** que el patrón en oleadas paralelas (106 vs 8). La razón es mecánica y verificable: el debounce de 80 ms colapsa eficazmente señales que llegan casi simultáneas (oleada paralela: 45 cambios en <100ms se funden en 1 sola lectura por oyente), pero **pierde casi toda su capacidad de coalescing cuando las señales llegan espaciadas 100–250 ms**, porque cada evento suele llegar después de que el debounce anterior ya se resolvió — entonces casi cada clic dispara su propia lectura completa. Esto es consistente con que el incidente real haya sido causado por clics humanos sucesivos (no simultáneos): **ese ritmo es precisamente el que menos beneficio saca del debounce actual.**

También se observa un aumento moderado (no una degradación) en la latencia media de las transiciones de cocina (427 ms vs 340–349 ms, +~25%), coincidente con que en este escenario las lecturas de los 5 oyentes compiten en tiempo real con las escrituras (a diferencia de B1/B2, donde el burst de escritura terminaba antes de que los oyentes reaccionaran). Sigue sin haber errores, timeouts ni reconexiones — no cumple ningún criterio de parada.

**Hipótesis actualizada sobre el incidente:** el ritmo de clic humano real (espaciado, no simultáneo) parece ser un patrón bastante peor para el fan-out que una ráfaga concentrada, porque neutraliza el debounce. Con solo 5 oyentes esto ya multiplicó por ~13 el volumen de RPC frente al mismo trabajo en paralelo, aunque todavía sin señales de estrés real (CPU/latencia). Esto refuerza —pero no confirma todavía— la hipótesis de fan-out como explicación plausible del incidente, y sugiere que al escalar a 10/20/40 oyentes (aún no autorizado) el patrón escalonado es el que hay que priorizar, no el paralelo.

### 13.5 CPU — pendiente de tu confirmación

Te avisé en el momento antes de correr la ráfaga para que pudieras mirar el Dashboard en vivo. Ventanas exactas: ráfaga **18:11:43–18:12:11 UTC**, minuto posterior **18:12:11–18:13:11 UTC** aprox. Si anotaste el % de CPU en esas ventanas (o corriste las consultas de la sección 8), compártemelo y lo agrego aquí.

**Sigo sin avanzar a 10 clientes ni a ráfagas mayores sin tu aprobación explícita.**

## 14. DETENIDO — CPU 93% observado por el usuario, origen no identificado (2026-09-22)

El usuario compartió una captura del Dashboard: **CPU 93%**, 18/60 conexiones, RAM 52%, banner permanente "Your project is currently facing high CPU usage". En "Last 60 minutes": **359.578 requests totales, 0.4% success rate**, panel Postgres con **358.111 requests / 358.102 errores** (~99.997% de error), API Gateway 1.350, Realtime 75 (24 warnings/23 errores), Auth 42.

### 14.1 Detención inmediata

- `cap.businessLoop.stopFlag = true`, `cap.stopAllListeners()` — resultado: **0 listeners abiertos, business loop no corriendo** (ya estaba así desde el enfriamiento de la sección 13, antes de este aviso).
- Recorrido de canales Realtime en todos los clientes conocidos del arnés (los 3 de rol fijo + los que quedaran en `cap.listeners`) — **0 canales encontrados abiertos** para forzar cierre.
- **Cerré la pestaña completa del navegador** donde vivía todo el arnés (todas las conexiones Realtime, timers de debounce, clientes Supabase). Esto es la confirmación más fuerte posible: sin la pestaña, no hay ningún contexto de JavaScript del arnés que pueda seguir generando tráfico. Para retomar cualquier prueba futura habría que reabrirla desde cero.
- **Confirmado: no queda ningún proceso del arnés ejecutándose.**

### 14.2 Contraste: volumen del arnés vs. 358k de Postgres

El arnés nunca hizo conexión directa a Postgres — todo pasó por PostgREST/RPC vía `supabase-js`, que cae bajo "API Gateway", no bajo "Postgres" directo. Sumando **todas** las fases de toda la sesión (nivel 1, escenario C B1/B2, limpieza, escenario C2 escalonado, más logins y lecturas de diagnóstico), el total de llamadas HTTP que generé en toda la hora es del orden de **~1.000–1.500** — consistente con el "API Gateway: 1.350" del panel. Mi conteo propio de `reconnects` en cada fase medida fue **0 en todo momento**, así que no hay evidencia, en mi instrumentación, de un loop de reconexión que se me haya escapado.

**Los 358.111 requests / 358.102 errores de Postgres no son consistentes con esto.** Es ~265 veces más que el tráfico API Gateway y ~3 órdenes de magnitud más que cualquier cosa que el arnés haya generado. No puedo, con lo que veo desde el cliente público, decir qué los originó — y no debo asumir que es el fan-out de Realtime: mi propia medición de fan-out (secciones 11–13) nunca superó unos pocos cientos de refresh/RPC en total, ni de cerca 358 mil.

**No asumo que el fan-out Realtime sea la causa raíz de esto.** Es una cifra de un orden de magnitud completamente distinto al que documenté; requiere su propia investigación con las herramientas del Dashboard, no con el arnés.

### 14.3 Pendiente — necesito que ejecutes esto en el SQL Editor

Con todo detenido, por favor corre ahora las 4 consultas de la sección 8 (`pg_stat_activity` detallado, conteo por estado, top RPC por `pg_stat_statements`, y locks) y compárteme el resultado. Especialmente 8.1/8.2 para ver si hay conexiones activas ahora mismo ejecutando algo repetitivo, y 8.3 para ver qué consulta concentra el volumen.

### 14.4 Dónde ver el mensaje concreto de los errores Postgres

En el Dashboard: **Logs → Postgres Logs** (a veces etiquetado "Database" en el menú lateral) — ahí aparece el mensaje de error real de cada consulta fallida (SQLSTATE, texto del error), no solo el conteo. Si el volumen es muy alto, filtra por severidad `ERROR` y ordena por más reciente primero; también sirve mirar **Logs → API Gateway Logs** filtrando por status ≥400 para ver qué endpoint concreto está fallando tanto, y **Database → Query Performance** (si tu plan lo expone) para ver qué consulta acumula más llamadas/tiempo total — es la vista con más probabilidad de mostrar de un vistazo cuál es la consulta que está fallando 358 mil veces.

### 14.5 Estado

**Detenido por completo.** No genero más tráfico, no ejecuto nivel 2, no ejecuto más ráfagas, no toco código ni configuración. Solo diagnóstico pasivo (leer, no escribir) hasta que se identifique el origen de los 358k errores y se confirme que el CPU vuelve a reposo.

## 15. Investigación del origen de `rpc_solicitar_descuento_pedido` (2026-09-22, solo lectura)

Restricciones respetadas: no ejecuté ninguna llamada nueva contra Supabase, no modifiqué código, no cancelé conexiones ni reinicié nada, no toqué RLS/RPC/configuración. Todo lo de abajo sale de leer el repositorio (`feature/E1-CashOperation`, working tree limpio salvo este doc) y de razonar sobre las migraciones ya existentes.

### 15.1 Hechos observados (verificados leyendo el código)

- **Mi propio arnés nunca llamó a `rpc_solicitar_descuento_pedido`.** Repasé el historial completo de `cap.metrics` de las tres rondas (nivel 1, escenario C B1/B2/limpieza, escenario C2) — la única RPC de caja que usé fue `rpc_obtener_sesion_caja_activa`, `rpc_abrir_sesion_caja`, `obtener_pedidos_pendientes_pago_caja` y `rpc_registrar_cobro_pedido`. Nunca toqué descuentos. Esto no pertenece al escenario de cocina que armé.
- **Condición exacta del error** (migración `20260914000200_e1_t06_descuento_pedido.sql`, líneas 195-205): la función busca si el pedido ya tiene una fila en `descuento_pedido`. Si existe y la nueva llamada coincide EXACTAMENTE en actor, `idempotency_key`, tipo, valor y motivo con la solicitud guardada, devuelve la misma fila sin error (replay idempotente real). Si existe y **cualquier cosa difiere** (incluida una `idempotency_key` nueva), lanza `40001 - El pedido ya tiene una solicitud de descuento`. La función no distingue "ya decidida" de "aún pendiente": una vez que un pedido tiene cualquier fila de descuento, toda solicitud nueva y distinta para ese mismo pedido falla igual, para siempre.
- **En la UI, `requestDiscount` solo se dispara desde un `<form onSubmit>` en `CashierPage.tsx`** (línea ~936-946), detrás del botón "Solicitar descuento" y del llenado manual del formulario. No hay `useEffect`, `setInterval`, `setTimeout`, retry automático ni polling que la invoque en `CashierPage.tsx` ni en `cashierService.ts` — solo encontré el `setTimeout`/`scheduleTimeout` del debounce de Realtime (`operationsRealtimeService.ts`, `kitchenRealtimeService.ts`), que no toca descuentos.
- **Sí encontré llamadas directas a esta RPC fuera de la UI**, todas en fixtures de prueba:
  - `supabase/tests/e1_t06_descuento_pedido.sql`, `e1_t06_concurrency_setup.sql`, `e1_t11_auditoria_financiera.sql` — SQL plano con IDs de pedido negativos hardcodeados (`-10659`, `-11301`..`-11305`), pensado para correr manualmente contra una base con esos fixtures ya sembrados.
  - **`scripts/testE1T09Concurrency.mjs`** — el más relevante. Llama `rpc_solicitar_descuento_pedido(-10955,20,null,'Carrera descuento','${randomUUID()}')`: **una `idempotency_key` nueva y aleatoria en cada ejecución**. Este script conecta **exclusivamente vía `docker exec <container> psql`** contra un contenedor Docker local (el nombre del contenedor y la base son argumentos de línea de comandos) — no tiene ningún código que apunte a un host remoto. Tal como está en el repo, **no puede alcanzar `ibfrrifvhvtgcxfxuinf`**.
- **Ninguno de estos scripts/fixtures está conectado a `package.json` (`npm run ...`) ni a `.github/workflows/ci.yml`.** El único workflow de CI corre solo en `main` y `feature/h1-TechnicalBasis` (no en `feature/E1-CashOperation`), usa una URL y una key de Supabase **falsas/placeholder** (`abcdefghijklmnopqrst.supabase.co`), y únicamente ejecuta typecheck, `test:environment` y build — no ejecuta SQL ni RPC de descuento, y no podría alcanzar el proyecto real aunque quisiera.

### 15.2 Hipótesis (no confirmadas, requieren lo que ves tú en logs/pg_stat)

- Si algo —una copia local o modificada de `testE1T09Concurrency.mjs` u otro script/sesión `psql` equivalente— está corriendo **repetidamente contra `ibfrrifvhvtgcxfxuinf` por conexión directa a Postgres** (no vía PostgREST) apuntando siempre al mismo `pedido_id` con una `idempotency_key` nueva cada vez, eso reproduce exactamente el patrón que describes: error masivo y repetido, porque cada intento nuevo choca con la solicitud ya guardada.
- Esto explicaría también la brecha Postgres (358k) vs API Gateway (1.3k): **una conexión directa a Postgres (psql, un pooler externo, cualquier cliente con cadena de conexión directa) nunca pasa por PostgREST/API Gateway**, así que no se cuenta ahí — pero sí queda en `pg_stat_activity`, `pg_stat_statements` y en los logs de Postgres. Es consistente con la brecha que reportas, pero no puedo confirmarlo desde el cliente público: no veo si hay una conexión directa activa contra el proyecto remoto ahora mismo.
- No tengo evidencia de que esto tenga relación con el fan-out de Realtime ni con el escenario de cocina — son sistemas de RPC completamente distintos (`rpc_solicitar_descuento_pedido` vs `actualizar_estado_detalle_cocina`), y mi arnés nunca invocó el primero.

### 15.3 Sobre `pg_stat_statements` — es acumulativo, hay que ubicar desde cuándo

Antes de interpretar los 113M `set_config` o los 156k `realtime.list_changes` que compartiste, hace falta saber desde cuándo acumula esa vista — no se resetea sola, solo al reiniciar Postgres o al llamar `pg_stat_statements_reset()` explícitamente. Consulta (solo lectura):

```sql
select stats_reset from pg_stat_statements_info;
-- si esa vista no existe en tu versión:
select pg_postmaster_start_time();
```

`set_config` en el orden de millones, por sí solo, no es necesariamente alarmante: PostgREST (y el propio patrón `set local role authenticated; select set_config('request.jwt.claim.sub',...)` que usan las funciones de esta app) llama `set_config` varias veces por cada request autenticado — con semanas o meses acumulados, 113M es plausible solo por tráfico normal. Lo mismo con `realtime.list_changes`: es la consulta interna que usa Realtime para detectar cambios de WAL, y corre en segundo plano todo el tiempo que haya algún canal `postgres_changes` activo — 156k acumulado también puede ser tráfico de fondo normal. **Sin la fecha de `stats_reset`, ninguno de los dos números por sí solo dice si son "de hoy" o de mucho antes.** Lo que sí es más directamente interpretable es el conteo de `rpc_solicitar_descuento_pedido` específico dentro de `pg_stat_statements` (filtra por `query ilike '%solicitar_descuento_pedido%'`) y, sobre todo, el gráfico de "últimos 60 minutos" del Dashboard, que sí está acotado en el tiempo.

### 15.4 Cómo identificar el origen exacto en los logs de Supabase

- **Postgres Logs** (Dashboard → Logs → Postgres Logs, o Logs Explorer con la tabla `postgres_logs`): cada línea de error trae `timestamp` y el `event_message` completo (incluye el SQLSTATE `40001` y el texto exacto). Ahí también suele aparecer el **rol de Postgres que ejecutó la consulta** (`user_name` en los metadatos, p. ej. `authenticator` si vino de PostgREST, o `postgres`/`supabase_admin`/otro si fue una conexión directa tipo `psql`) — eso solo ya distingue "vino de la API" vs "conexión directa". Consulta de ejemplo en Logs Explorer:
  ```sql
  select timestamp, event_message
  from postgres_logs
  where event_message ilike '%solicitar_descuento_pedido%' or event_message ilike '%40001%'
  order by timestamp desc
  limit 200;
  ```
- **User-agent, IP/origen y request-id** no existen a nivel de Postgres (Postgres no ve HTTP) — esos campos viven en los **logs de API Gateway** (Dashboard → Logs → API Gateway Logs / Edge Logs). Busca ahí las llamadas a `/rest/v1/rpc/rpc_solicitar_descuento_pedido` cerca de los mismos timestamps que encuentres en Postgres Logs, y vas a poder ver método, path, status, IP y user-agent del llamador. Si el `user_name` en Postgres Logs es `authenticator` (no un rol interno), esa llamada sí pasó por la API y su rastro completo (IP, user-agent, usuario autenticado vía JWT) está en API Gateway Logs, correlacionable por tiempo.
- **Usuario autenticado:** si la llamada vino por la API, el JWT que la autenticó queda asociado en API Gateway Logs (y en Auth Logs si querés confirmar de qué sesión/usuario es el token). Si vino por conexión directa a Postgres, no hay JWT — vas a ver el rol de conexión directamente (`postgres`, `service_role`, etc.) en `pg_stat_activity.usename` y en Postgres Logs.

### 15.5 Discrepancia 358k Postgres vs 1.3k API Gateway — explicación

No son la misma capa: **API Gateway** cuenta requests HTTP que pasaron por PostgREST/Auth/Realtime (lo único que ve el Dashboard como "solicitudes" del lado de app). **Postgres** cuenta directamente las consultas ejecutadas en la base, sin importar por dónde entraron. Toda mi carga de prueba pasó por PostgREST vía `supabase-js` — por eso mi tráfico (~1.000-1.500 llamadas en total en toda la sesión) es del orden del "API Gateway: 1.350" que viste, no del "Postgres: 358k". Un volumen de Postgres muy por encima del de API Gateway, con una tasa de error de ~100%, apunta a **tráfico que llega a la base sin pasar por la API** (conexión directa, pooler externo, un proceso con la cadena de conexión de Postgres en vez de la URL de Supabase) — coherente con cómo conecta `testE1T09Concurrency.mjs` (vía `psql`, no vía `supabase-js`), aunque como está en el repo no alcanza el proyecto remoto. Confirmar esto requiere mirar `usename`/`application_name`/`client_addr` en `pg_stat_activity` y Postgres Logs — no puedo verlo yo desde el cliente público.

**Sigo detenido: sin llamadas de prueba nuevas, sin cambios de código, sin tocar RLS/RPC/configuración. Esperando las consultas de `pg_stat_activity`/`pg_stat_statements` y/o lo que encuentres en los logs.**

## 16. Causa raíz confirmada: PostgREST reintenta automáticamente sobre `40001` (2026-09-22, solo lectura — no implementado)

### 16.1 Verificación de la premisa (no la di por cierta, la verifiqué)

Antes de registrar nada como "confirmado" busqué la documentación oficial, porque el comportamiento de reintento automático de PostgREST no es algo que pueda inferir del código de este repo. Encontré el artículo oficial de troubleshooting de Supabase, **"SQLSTATE 40001 (serialization_failure) in an RPC function causes infinite retries"**:

> "A custom `raise exception` using SQLSTATE `40001` (`serialization_failure`) in your PL/pgSQL function tells PostgREST the failure is transient, so PostgREST retries the transaction."

Y advierte además algo crítico para el estado actual del proyecto: **arreglar la función no detiene las transacciones que ya están en curso** — los backends colgados hay que identificarlos y terminarlos manualmente (`pg_terminate_backend`) o reiniciar el proyecto. Esto lo señalo solo como información — no cancelé conexiones ni reinicié nada, respetando la restricción.

**Con esto, registro como causa raíz confirmada (mecanismo verificado por documentación oficial, consistente con toda la evidencia de las secciones 14-15):** el reintento automático de PostgREST sobre `errcode='40001'` es lo que explica CPU alta + volumen masivo de errores Postgres con éxito casi nulo, cuando una función como `rpc_solicitar_descuento_pedido` (u otras, ver abajo) usa `40001` para un conflicto funcional permanente en vez de una condición realmente transitoria.

### 16.2 Auditoría completa: cada uso de `errcode='40001'` en `feature/E1-CashOperation`

Encontré **53 apariciones** de `errcode = '40001'` en `supabase/migrations/*.sql`. Ninguna corresponde a un error nativo de Postgres: **el proyecto nunca usa `SERIALIZABLE` isolation level** (confirmado por búsqueda — 0 resultados), así que Postgres jamás generaría un `40001` por sí solo aquí. **Las 53 son `raise exception using errcode='40001'` manuales** — es decir, un código reservado para fallos transitorios de Postgres, asignado a mano a condiciones de aplicación. Después de descartar las versiones de función ya reemplazadas por migraciones posteriores (`create or replace`), quedan **~20 funciones/mensajes distintos vigentes hoy**, que clasifico en dos categorías:

**A — Concurrencia real (verificación optimista dentro de la misma operación: se relee o se actualiza con `where estado = X` y se comprueba que la fila afectada sea la esperada).** Reintentar con los mismos parámetros a veces sí puede resolverse solo si el estado vuelve a ser válido, aunque en la práctica casi nunca ocurre porque PostgREST reenvía el mismo request tal cual.

| RPC | Mensaje | Escenario | Consumidor frontend |
|---|---|---|---|
| `crear_o_recuperar_pedido_mesa` | "La mesa cambió durante la apertura del pedido" | UPDATE mesa afectó 0 filas tras el lock (defensivo, prácticamente inalcanzable bajo el locking actual) | `waiterOrderService.ts` (mozo, abrir mesa) |
| `actualizar_estado_detalle_cocina` | "El detalle cambió durante la operación" | Detalle no encontrado tras `for update` | `kitchenRealtimeService.ts` (cocina) |
| `actualizar_estado_detalle_cocina` | "El detalle fue actualizado por otra sesión" | `estado` actual ≠ `p_estado_esperado` (choque de doble transición) | `kitchenRealtimeService.ts` → **capturado explícitamente**: `if (result.error?.code === '40001')` → UI: "Este producto fue actualizado desde otro dispositivo. Se cargó la versión más reciente." (`concurrent-conflict`) |
| `entregar_pedido` | "El pedido cambió durante la entrega" / "La mesa cambió durante la entrega" | UPDATE afectó 0 filas | `waiterOrderService.ts` → **capturado explícitamente**: `if (result.error.code === '40001')` → UI: "Este pedido ya fue procesado. Cargamos el estado más reciente." (`concurrent-conflict`, `recoverable: true`) |
| `liberar_mesa_pedido_vacio` | "El pedido cambió durante la liberación de la mesa" / "La mesa cambió durante su liberación" | UPDATE afectó 0 filas | `waiterOrderService.ts` |
| `anular_pedido_supervisado` | "El pedido cambió durante la anulación" / "La mesa cambió durante la anulación" | UPDATE afectó 0 filas | admin (no revisado en detalle, mismo patrón) |
| `rpc_abrir_sesion_caja` | "La sesión cambió; reintente la solicitud" | Colisión real de `unique_violation` en índice `uq_sesion_caja_abierta`, ya recomprobada una vez | `cashierService.ts` (helper `fail`, ver 16.3) — **el único caso del repo escrito explícitamente para reintento** |

**B — Conflicto funcional puro (regla de negocio permanente, no una carrera): reintentar con los mismos parámetros JAMÁS tiene éxito hasta que un humano cambie el estado.** Esta es la categoría peligrosa bajo el retry automático de PostgREST — cada una es, en potencia, otro `rpc_solicitar_descuento_pedido`.

| RPC | Mensaje | Escenario | Consumidor frontend |
|---|---|---|---|
| **`rpc_solicitar_descuento_pedido`** | "El pedido ya tiene una solicitud de descuento" | Ya existe una solicitud distinta para ese pedido | `cashierService.ts` (`fail`) — **el que causó el incidente actual** |
| `rpc_solicitar_descuento_pedido` | "El pedido no admite descuento" | Pedido no está en estado válido para pedir descuento | `cashierService.ts` |
| `rpc_decidir_descuento_pedido` | "No existe solicitud de descuento" / "La solicitud ya fue decidida" / "El pedido ya no admite descuento" | Nada que decidir, o ya se decidió antes | `cashierService.ts` |
| `rpc_registrar_pago_pedido_v2` / `rpc_registrar_pago_total_pedido` / `rpc_registrar_cobro_pedido` (varias versiones) | "El pedido ya no está disponible para cobro", "La mesa ya no está pendiente de pago", "El pedido ya no tiene saldo", "Pedido no disponible para cobro" | Pedido no está `ENTREGADO`, mesa no está `PENDIENTE_PAGO`, o saldo ya es 0 | `cashierService.ts` |
| `rpc_abrir_sesion_caja` / `rpc_registrar_cobro_pedido` / `rpc_cerrar_sesion_caja` / movimientos / descuento | "La sesión de caja ya no está abierta" / "La sesión de caja ya está cerrada" / "Debe abrir una sesión de caja antes de cobrar" | Sesión cerrada o inexistente — aparece en **6+ funciones distintas** | `cashierService.ts` — patrón repetido, alto riesgo de volumen si un cliente queda con un `sesion_id` obsoleto en caché |
| `rpc_obtener_sesion_caja_activa` | "Sesión activa no disponible para la caja seleccionada" | Se pidió `p_sesion_id` explícito y no coincide con la sesión abierta actual | `cashierService.ts` (mi propio bot nunca pasó `p_sesion_id`, así que nunca la disparé) |
| `anular_pedido_supervisado` | "El pedido ya fue anulado" / "Un pedido con pagos no puede anularse" / "El estado del pedido no admite anulación" | Reglas de anulación | admin |
| **Trigger `tgf_bloquear_detalle_pedido_con_pago`** (2 migraciones) | "Un pedido con pagos no admite mutaciones" | Invariante de integridad, disparado por trigger en cualquier UPDATE a un pedido/detalle ya pagado | Cualquier RPC que intente mutar un pedido pagado — el radio de alcance es el más amplio de todos, porque no es una función, es un trigger |

### 16.3 Servicios TypeScript que interpretan `40001` como `conflict` explícitamente

- **`src/services/cashierService.ts:206`** — helper `fail()`, usado por **todas** las RPC de caja de la tabla B de arriba: `kind: code === "40001" || code === "23505" ? "conflict" : "operation-error"`. Trata 40001 y 23505 (unique_violation) igual, sin distinguir cuál de los ~15 mensajes de la tabla B lo originó.
- **`src/services/kitchenRealtimeService.ts:181`** — `if (result.error?.code === '40001')` → mensaje específico de "actualizado desde otro dispositivo".
- **`src/services/waiterOrderService.ts:277`** — `if (result.error.code === '40001')` → mensaje específico de "pedido ya procesado".
- **Tests que dependen de esto:** `tests/kitchenBoard.test.mjs` (caso `H4-TH06`, simula `{ code: '40001' }` y verifica que la UI resincronice) y `tests/waiterBoard.test.mjs` (`conflictFixture` con `{ code: '40001' }`).

### 16.4 Cambio mínimo — análisis de impacto, sin elegir ni implementar todavía

Dos opciones viables, ninguna implementada:

1. **Cambiar `errcode='40001'` a `errcode='P0001'`** (código por defecto de `raise exception` sin SQLSTATE explícito) en las ~15 líneas de la categoría B — PostgREST no reintenta sobre `P0001`. Mantiene el mensaje textual sin cambios.
2. **Usar un código con prefijo `PT` (p. ej. `PT409`)** para que PostgREST lo mapee directamente a un HTTP 409 Conflict — más semántico para el frontend, pero cambia el status HTTP que hoy recibe el cliente (hoy con 40001 probablemente llega como error genérico; con `PT409` llegaría como 409), lo que podría afectar cualquier lógica que mire `status` además de `code`.

**Impacto de cualquiera de las dos, si se implementara (no ahora):**
- Las ~15 líneas SQL de la tabla B (varias migraciones nuevas de tipo "delta", nunca se editan migraciones existentes ya aplicadas).
- `cashierService.ts:206` — el helper `fail()` tendría que dejar de mirar `"40001"` y mirar el nuevo código, sin tocar los mensajes.
- La categoría A (`kitchenRealtimeService.ts:181`, `waiterOrderService.ts:277`) es un caso aparte: esos SÍ dependen de que el código siga siendo distinguible como "conflicto de concurrencia" para mostrar su mensaje específico — si se cambia su SQLSTATE también (recomendable, porque igual sufren el mismo riesgo de reintento infinito si el conflicto no es transitorio), esas dos líneas también deben actualizarse al nuevo código, en paralelo con el backend.
- `tests/kitchenBoard.test.mjs` y `tests/waiterBoard.test.mjs` — sus fixtures `{ code: '40001' }` quedarían desalineados con el nuevo código si no se actualizan a la par.
- Ninguna regla de negocio ni mensaje visible al usuario cambia — solo el SQLSTATE interno y las 3+2 líneas que lo comparan.

**No elegí ni implementé ninguna de las dos — queda para que decidas antes de tocar código.**

**Sigo sin ejecutar pruebas de carga, sin modificar RPC/migraciones/frontend/configuración, sin tocar PostgREST/Supabase ni subir compute.**

Sources:
- [Supabase Docs — SQLSTATE 40001 (serialization_failure) in an RPC function causes infinite retries](https://supabase.com/docs/guides/troubleshooting/high-cpu-and-infinite-transaction-retries-when-using-custom-error-codes-in-rpc-functions-77326b)

## 17. Correctivo E1-T18 aplicado en DEV — `PT409` pasa a ser el conflicto funcional esperado (23/09/2026)

### 17.1 Contexto reportado

Según se me indicó al iniciar esta ronda: el correctivo E1-T18 (migración `20260922000100_e1_delta_t18_migrar_errcode_conflicto_funcional.sql`, ver sección 16) está aplicado en el proyecto DEV (`ibfrrifvhvtgcxfxuinf`), y DEV presenta un baseline reportado de **CPU 0.60%, 6 conexiones, sin presión de disco**. Esto no lo verifiqué yo de forma independiente (no tengo acceso al Dashboard) — lo registro como dato reportado, no como hecho medido por mí, siguiendo la misma distinción que uso en el resto de este documento.

Confirmé por mi cuenta, leyendo el código fuente vigente en el repo (no la migración en sí, sino los archivos TypeScript ya modificados por el correctivo), que `kitchenRealtimeService.ts:181` y `waiterOrderService.ts:277` ya aceptan `PT409` como el código de conflicto, conservando `40001` solo por compatibilidad temporal — consistente con lo reportado.

### 17.2 Cambio de convención para este documento, de aquí en adelante

- **`PT409` es el conflicto funcional controlado esperado.** Cualquier ocurrencia de `PT409` durante una prueba de carga se cuenta y reporta, pero **no** se trata como señal de error ni como criterio de parada — es el resultado normal de una carrera de negocio genuina (dos actores intentando la misma transición sobre el mismo `detalle_id`/`pedido_id`), exactamente el mismo rol que cumplía `40001` en las secciones 11–16 de este documento.
- **Cualquier `40001` observado de aquí en adelante se trata como error/regresión, no como conflicto esperado.** Post-T18, ningún RPC/trigger activo de `public` debería emitir `40001` de forma manual (verificado estáticamente en la sección 16.2 y en el propio correctivo); un `40001` real solo debería poder originarse en un conflicto de serialización *nativo* de PostgreSQL, que no es el patrón que este documento ha estado ejercitando. Se actualizó la sección 4 (criterio de parada) en consecuencia.
- Todas las secciones anteriores (11–16) siguen describiendo correctamente lo que se observó **en su momento**, bajo la convención anterior (`40001` como conflicto esperado) — no se reescriben, solo se anota aquí el cambio de convención hacia adelante.

### 17.3 Próxima ejecución: repetición del escenario escalonado (C2) de la sección 13.3

Se me pidió repetir el escenario staggered de la sección 13.3 (5 clientes oyentes, 45 transiciones sobre 15 detalles, orden round-robin sin repetir `detalle_id` consecutivo, pausas aleatorias 100–250 ms), esta vez registrando **baseline, ráfaga y enfriamiento por separado** (formato de la sección 11) para poder comparar directamente contra 13.3/13.4, sin escalar a 10 clientes y sin tocar código/configuración/migraciones durante la medición. Resultados en la sección 18 (pendiente).

## 18. Resultados — Escenario C repetido post-T18, con `PT409` (23/09/2026)

Repetición del escenario escalonado de la sección 13.3 (5 clientes oyentes: 2 cocina, 2 mozo-mesas, 1 caja; 45 transiciones sobre 15 detalles nuevos, orden round-robin sin repetir `detalle_id` consecutivo, pausas aleatorias 100–250 ms entre llamadas), ahora con el correctivo E1-T18 aplicado en DEV. Arnés reconstruido desde cero en esta ronda (7 sesiones autenticadas: mozo/cocina ×3 cada uno + caja ×1, mismas credenciales `H2_*` de siempre), replicando línea por línea `operationsRealtimeService.ts` (debounce 80 ms + coalescing `refreshInFlight`/`refreshAgain`), `kitchenRealtimeService.ts`, `CashierPage.tsx` (`refresh(false)`: `getCashboxes`+`getActiveSession`+`getPendingOrders` siempre, +`getSummary`/`getMovements`/`getSessionReport` si hay sesión activa) y `WaiterTablesPage.tsx`/`waiterOrderService.getTableBoard` (4 consultas, 2 condicionales).

### 18.0 Limpieza previa (no contada como medición)

Al reconstruir el arnés encontré las 6 mesas ocupadas por 6 pedidos de prueba (`id` 18,19,20,28,29,30) dejados sin cobrar por rondas anteriores de esta misma investigación (21–22/09), todos creados por el propio bot `H2_MOZO` — confirmado por `creado_por` antes de tocar nada. Con tu autorización explícita, los completé por el flujo normal (`entregar_pedido` donde hacía falta + `rpc_registrar_cobro_pedido` TOTAL en efectivo) y verifiqué **M01–M06 de vuelta en `LIBRE`, 0 pedidos pendientes de cobro, 0 pedidos abiertos** antes de continuar. Luego dejé **~3 min de reposo** (18:28:43–18:31:45 UTC) para que se disipara cualquier señal Realtime generada por la propia limpieza, confirmando 0 eventos nuevos antes de iniciar la medición de baseline.

### 18.1 Baseline en reposo (95.8 s, 18:31:45–18:33:21 UTC)

5/5 conexiones (`SUBSCRIBED` sin errores, confirmado al conectar: 7 refresh de conexión inicial — 2 cocina ×2 c/u por `initialRefresh:true`, 2 mozo ×1 c/u, 1 caja ×1 — igual que predice el código fuente, medidos aparte del reposo). **Durante los 95.8 s de reposo puro (sin actividad de negocio): 0 eventos Realtime crudos, 0 refresh/RPC, 0 errores, 0 reconexiones**, en los 5 oyentes.

### 18.2 Configuración de la ráfaga (no contada como medición, 20.2 s)

3 pedidos nuevos (M01→`pedido 31`, M04→`pedido 32`, M05→`pedido 33`; mismos 5 productos que en 13.3), 15 detalles, enviados a cocina. `sendOk: true` en los 3.

### 18.3 Ráfaga escalonada (19.4 s, 18:34:30–18:34:50 UTC)

**Transiciones de cocina:** 45/45 OK, **0 errores, 0 `PT409`, 0 `40001`**, 0 reconexiones. Latencia: media 248.6 ms, p50 223.7 ms, p95 302.1 ms.

**Por rol, durante la ráfaga:**

| Rol | Eventos Realtime crudos | Refresh/RPC ejecutados | Latencia refresh (avg/p95) | Errores |
|---|---|---|---|---|
| Cocina (2 oyentes) | 108 | 68 | 245.9 / 329.2 ms | 0 |
| Mozo (2 oyentes) | 108 | 65 | 530.8 / 778.1 ms | 0 |
| Caja (1 oyente) | 0 | 0 | — | 0 |

Caja en 0 otra vez, consistente con la causa verificada en 13.1 (sin política `select` de `detalle_pedido` para CAJA; estos pedidos nunca cruzaron a `ENTREGADO`/`PAGADO` durante la ráfaga).

### 18.4 Enfriamiento (103.5 s, 18:34:55–18:36:39 UTC)

**0 eventos residuales, 0 refresh, 0 reconexiones** en los 5 oyentes — drenó limpio, ya asentado antes de que empezara a contar esta ventana (a los pocos segundos de terminada la ráfaga).

### 18.5 Comparación directa contra C2 (sección 13.3/13.4, pre-T18)

| | C2 — 13.3 (pre-T18, `40001`) | C3 — esta ronda (post-T18, `PT409`) |
|---|---|---|
| Duración de la ráfaga | ~27.3 s | ~19.4 s |
| Transiciones | 45 | 45 |
| Errores | 0 | 0 |
| Conflicto funcional esperado observado | `40001`: 0 | `PT409`: 0 |
| Latencia transición (avg/p95) | 427 / 553 ms | 248.6 / 302.1 ms |
| Refresh/RPC cocina (avg/p95 lat.) | 54 (245/358 ms) | 68 (245.9/329.2 ms) |
| Refresh/RPC mozo (avg/p95 lat.) | 52 (616/1078 ms) | 65 (530.8/778.1 ms) |
| Refresh/RPC caja | 0 | 0 |
| Eventos crudos cocina/mozo | 114 / 114 | 108 / 108 |
| Reconexiones | 0 | 0 |

**Hechos medidos, no hipótesis:**
- **Cero conflictos en ambas rondas** (ni `40001` en C2 ni `PT409` en C3) — un solo bot de cocina ejecutando secuencialmente no genera carreras reales sobre el mismo `detalle_id`; esto no prueba nada sobre el comportamiento de `PT409` bajo conflicto real, solo confirma que su ausencia no cambió nada más del flujo.
- **La latencia de transición bajó ~42%** (427→248.6 ms de media) y la latencia de refresh de mozo también bajó (616→531 ms de media, 1078→778 ms p95), mientras que la de cocina se mantuvo prácticamente igual (245/358 vs 245.9/329.2 ms).
- **El conteo de refresh/RPC subió** pese a mantenerse el mismo número de transiciones y una cantidad de eventos crudos similar (108 vs 114): cocina 54→68 (+26%), mozo 52→65 (+25%) — la razón refresh/crudos pasó de ≈47%/46% a ≈63%/60%, es decir, el debounce de 80 ms coalesció *menos* señales esta vez, no más.
- **0 reconexiones y 0 errores en ambas rondas.**

**Hipótesis, explícitamente sin confirmar:**
- El correctivo E1-T18 en sí (renombrar un `errcode` de `40001` a `PT409` en `raise exception`) no toca planes de consulta, índices, ni ninguna ruta caliente — **no es mecánicamente plausible que por sí solo explique la baja de latencia observada**. La explicación más probable es variabilidad de entorno entre corridas (carga concurrente distinta en DEV, hora del día, el baseline de 0.60% CPU / 6 conexiones que reportaste vs. lo que hubiera al momento de 13.3) — no lo puedo confirmar ni descartar sin métricas de servidor de ambas fechas.
- Que el debounce haya coalescido *menos* esta vez pese a menor latencia de transición es un poco contraintuitivo (menor latencia de mutación debería acercar las señales en el tiempo y favorecer más coalescing, no menos). No tengo una explicación mecánica confirmada — lo dejo como observación abierta, no como hallazgo explicado.
- Ninguna de estas hipótesis toca la conclusión ya establecida en 13.4 (el ritmo escalonado 100–250 ms sigue derrotando en gran medida al debounce de 80 ms, con o sin el correctivo T18) — si acaso, este resultado la refuerza (proporción refresh/crudos aún más alta que antes).

### 18.6 Criterio de parada y estado final

Ningún criterio de la sección 4 se activó en ningún momento (0% error/timeout, sin `40001` inesperado, sin crecimiento anómalo de p95, sin desconexiones). Al terminar, entregué y cobré (TOTAL, efectivo) los 3 pedidos de esta ronda (31, 32, 33) — **M01–M06 quedaron todas en `LIBRE`**, sesión de caja sin pedidos pendientes.

**No escalé a 10 clientes. No modifiqué código, configuración ni migraciones durante la medición — solo lectura/ejecución de RPC de negocio ya existentes, igual que en las rondas anteriores.**

### 18.7 Métricas de servidor — confirmadas por el usuario (23/09/2026)

Reportadas por vos, observadas en el Dashboard durante la corrida de la sección 18.3 (ráfaga) y 18.4 (enfriamiento) — no medidas por mí, las registro como evidencia de servidor complementaria a los hechos de cliente ya documentados:

- **CPU:** muy por debajo del 80% de la sección 4; valor puntual **0.42%**.
- **Conexiones:** pico aproximado de **15–17**, con retorno a **6** tras la prueba (mismo baseline de conexiones que el reportado antes de esta ronda, sección 17.1).
- **Network:** pico aproximado de **55–60 KB/s**.
- **IOPS:** **< 1**, sin presión de disco.
- **Recuperación:** completa al baseline después de la prueba.

**Nivel de 5 clientes queda aprobado técnicamente** — ningún indicador de servidor se acercó al criterio de parada de la sección 4 (80% CPU), consistente con los hechos de cliente de 18.1–18.6 (0 errores, 0 reconexiones, drenado limpio).

## 19. Resultados — Nivel 2 (10 clientes), escenario C escalonado (23/09/2026)

Mismo escenario que la sección 18, escalando **solo el fan-out de oyentes**: 10 clientes conectados (4 cocina, 4 mozo-mesas, 2 caja — se duplicó en la misma proporción 2:2:1 usada en 5 clientes; no había una proporción para nivel 10 definida de antemano en la sección 2, así que la elegí por consistencia con las rondas anteriores y la dejo explícita aquí). Throughput de negocio idéntico al nivel 5: 3 pedidos nuevos (15 detalles), 45 transiciones, mismo orden round-robin, mismas pausas aleatorias 100–250 ms. Arnés reconstruido sobre las mismas 7 sesiones del nivel 5 + 5 sesiones nuevas (`cocinaL3/L4`, `mozoL3/L4`, `cajaL2`), mismas credenciales `H2_*`, misma lógica portada de `operationsRealtimeService.ts`/`kitchenRealtimeService.ts`/`CashierPage.tsx`/`waiterOrderService.getTableBoard`.

Verifiqué M01–M06 en `LIBRE` y 0 pedidos abiertos antes de empezar (quedaron así al cierre de la sección 18).

### 19.1 Conexión y baseline en reposo (100.5 s)

10/10 conexiones `SUBSCRIBED` sin errores (14 refresh de conexión inicial: 4 cocina ×2 c/u + 4 mozo ×1 c/u + 2 caja ×1 c/u = 14, exactamente lo esperado por el código). Reposo previo de ~2 min 50 s antes de medir (para disipar cualquier señal residual de la conexión), luego **100.5 s de reposo puro: 0 eventos, 0 refresh, 0 errores, 0 reconexiones** en los 10 oyentes.

### 19.2 Configuración de la ráfaga (no contada, ~6.8 s)

3 pedidos nuevos (M01→`pedido 34`, M04→`pedido 35`, M05→`pedido 36`), 15 detalles, enviados a cocina. `sendOk: true` en los 3.

### 19.3 Ráfaga escalonada (17.8 s)

**Transiciones de cocina:** 45/45 OK, **0 errores, 0 `PT409`, 0 `40001`**, 0 reconexiones. Latencia: media 224.0 ms, p50 223.4 ms, p95 234.5 ms.

**Por rol, durante la ráfaga:**

| Rol | Oyentes | Eventos Realtime crudos | Refresh/RPC ejecutados | Latencia refresh (avg/p95) | Errores |
|---|---|---|---|---|---|
| Cocina | 4 | 216 | 124 | 233.5 / 280.4 ms | 0 |
| Mozo | 4 | 216 | 76 | 877.4 / 1073.9 ms | 0 |
| Caja | 2 | 0 | 0 | — | 0 |

Caja en 0 de nuevo, mismo motivo verificado en 13.1 (sin política `select` de `detalle_pedido` para CAJA; los pedidos no cruzaron a `ENTREGADO`/`PAGADO` durante la ráfaga).

### 19.4 Enfriamiento (112.3 s)

**0 eventos residuales, 0 refresh, 0 reconexiones** en los 10 oyentes — drenó limpio.

### 19.5 Comparación directa — 5 clientes (sección 18) vs. 10 clientes (esta sección)

| | 5 clientes (sección 18) | 10 clientes (esta sección) | Factor |
|---|---|---|---|
| Oyentes cocina / mozo / caja | 2 / 2 / 1 | 4 / 4 / 2 | ×2 |
| Duración de la ráfaga | 19.4 s | 17.8 s | ~igual |
| Transiciones | 45 | 45 | igual |
| Errores / `PT409` / `40001` | 0 / 0 / 0 | 0 / 0 / 0 | igual |
| Latencia transición (avg/p95) | 248.6 / 302.1 ms | 224.0 / 234.5 ms | ~igual (leve baja) |
| Eventos crudos cocina | 108 | 216 | ×2.00 |
| Refresh/RPC cocina | 68 | 124 | ×1.82 |
| Latencia refresh cocina (avg/p95) | 245.9 / 329.2 ms | 233.5 / 280.4 ms | ~igual |
| Eventos crudos mozo | 108 | 216 | ×2.00 |
| Refresh/RPC mozo | 65 | 76 | ×1.17 |
| Latencia refresh mozo (avg/p95) | 530.8 / 778.1 ms | 877.4 / 1073.9 ms | ×1.65 / ×1.38 |
| Refresh/RPC caja | 0 | 0 | igual |
| Reconexiones | 0 | 0 | igual |

**Hechos medidos, no hipótesis:**
- **Los eventos crudos escalan exactamente ×2 con el número de oyentes** (108→216 en ambos roles) para el mismo throughput de negocio (45 transiciones) — confirma con evidencia directa la hipótesis de fan-out de la sección 1.1/2.5: cada mutación se replica una vez por oyente suscrito al canal correspondiente, linealmente.
- **El refresh/RPC generado NO escaló ×2 en ninguno de los dos roles** — cocina ×1.82 (68→124) y mozo ×1.17 (65→76), ambos por debajo del escalado de eventos crudos. El debounce/coalescing de 80 ms absorbió una fracción mayor de señales al duplicar los oyentes de lo que absorbió al duplicar la carga en 13.4 — dato nuevo, no observado en las rondas anteriores (que nunca habían variado el número de oyentes, solo el ritmo de negocio).
- **0 conflictos y 0 errores en ambos niveles**, con 0 reconexiones — ningún indicador de degradación por duplicar los oyentes.
- **La latencia de transición y de refresh de cocina se mantuvieron prácticamente iguales** entre niveles (dentro de ~10% de variación, consistente con ruido normal de red, no con degradación).
- **La latencia de refresh de mozo subió ~1.4–1.65×** (531→877 ms avg, 778→1074 ms p95) al duplicar los oyentes mozo — es la única señal de costo creciente con el fan-out en esta ronda. Sigue muy por debajo de cualquier criterio de parada (no hay umbral de latencia absoluta definido en la sección 4 más allá de "crecimiento >3× el nivel anterior", y este aumento es ~1.4–1.65×).
- **Métricas de servidor (CPU, conexiones, network, IOPS) de este nivel: pendientes de que las compartas** — no tengo acceso al Dashboard; si las tomaste en paralelo a esta ventana (19:26:03–19:30:25 UTC), las agrego en una subsección aparte.

**Hipótesis, explícitamente sin confirmar:**
- Que el refresh/RPC de mozo haya subido en latencia (no en conteo, que solo escaló ×1.17) sugiere que la consulta del tablero de mozo (4 sub-consultas, 2 condicionales) es más sensible a la concurrencia de llamadas simultáneas entre sí misma (4 oyentes mozo compitiendo) que la de cocina (una sola RPC `obtener_tablero_cocina()`), consistente con el hallazgo estructural ya anotado en la sección 11.2 sobre el costo de esa lectura en particular — pero esto no está confirmado con `pg_stat_statements`, sigue siendo la misma hipótesis abierta de entonces.
- Que el coalescing haya sido proporcionalmente más efectivo al escalar oyentes que al escalar ritmo de negocio (13.4) es plausible mecánicamente (más oyentes por señal = más probabilidad de que varias señales caigan dentro de la misma ventana de 80 ms de *algún* oyente en particular, ya que el debounce es por cliente, no por señal), pero con un solo salto de nivel (5→10) no alcanza para confirmar que esto escale de forma predecible a 20/40.

### 19.6 Criterio de parada y estado final

Ningún criterio de la sección 4 se activó (0% error/timeout, sin `40001` inesperado, sin crecimiento de latencia >3×, sin desconexiones). Entregué y cobré (TOTAL, efectivo) los 3 pedidos de esta ronda (34, 35, 36) — **M01–M06 quedaron todas en `LIBRE`**.

**No escalo a 20 clientes hasta revisar juntos las métricas de este nivel — según lo acordado.**

### 19.7 Métricas de servidor — confirmadas por el usuario (23/09/2026)

Reportadas por vos, observadas en el Dashboard durante la ventana de la sección 19.3–19.4: **CPU muy baja, sin presión de memoria, disco ni conexiones.** No diste valores puntuales esta vez (a diferencia de la sección 18.7); si los tenés, los agrego. Consistente con los hechos de cliente de 19.1–19.4 (0 errores, 0 reconexiones, drenado limpio).

**Nivel de 10 clientes queda aprobado técnicamente.**

### 19.8 Cierre completo del arnés y verificación de baseline antes de escalar (23/09/2026)

Antes de preparar el nivel de 20, cerré por completo las 12 sesiones/clientes del arnés del nivel 10 (10 oyentes + `mozoDriver` + `cocinaDriver`): confirmé 0 canales Realtime residuales en cada cliente, desconecté explícitamente el socket de Realtime de cada uno (`client.realtime.disconnect()`), hice `signOut()` de las 12 sesiones, y recargué por completo la pestaña del navegador — verificado como pizarra limpia (`window.supabase`/`window.__cap` inexistentes tras la recarga). Esperé 3 minutos.

No tengo acceso al Dashboard, así que te pedí que confirmaras `Database Connections`. **Confirmaste que volvió a ~6**, junto con CPU/memoria/disco en baseline. Con esto, el nivel de 20 queda autorizado a preparar.

## 20. Resultados — Nivel 3 (20 clientes), escenario C escalonado (23/09/2026)

Mismo escenario, escalando otra vez solo el fan-out de oyentes, misma proporción 2:2:1: **8 cocina, 8 mozo-mesas, 4 caja** (22 sesiones totales: 20 oyentes + `mozoDriver` + `cocinaDriver`). Throughput de negocio idéntico a los niveles anteriores: 3 pedidos nuevos (15 detalles), 45 transiciones, mismo orden round-robin, mismas pausas aleatorias 100–250 ms. Arnés reconstruido desde cero (pizarra limpia, sección 19.8) para evitar arrastrar estado del nivel 10.

Verifiqué M01–M06 en `LIBRE` y 0 pedidos abiertos antes de empezar.

### 20.1 Conexión y baseline en reposo (106.0 s)

20/20 conexiones `SUBSCRIBED` sin errores (28 refresh de conexión inicial: 8 cocina ×2 c/u + 8 mozo ×1 c/u + 4 caja ×1 c/u = 28, exacto). Reposo previo de ~2 min 50 s, luego **106.0 s de reposo puro: 0 eventos, 0 refresh, 0 errores, 0 reconexiones** en los 20 oyentes.

### 20.2 Configuración de la ráfaga (no contada, ~8.2 s)

3 pedidos nuevos (M01→`pedido 37`, M04→`pedido 38`, M05→`pedido 39`), 15 detalles, enviados a cocina. `sendOk: true` en los 3.

### 20.3 Ráfaga escalonada (18.6 s)

**Transiciones de cocina:** 45/45 OK, **0 errores, 0 `PT409`, 0 `40001`**, 0 reconexiones. Latencia: media 230.4 ms, p50 224.8 ms, p95 250.8 ms.

**Por rol, durante la ráfaga:**

| Rol | Oyentes | Eventos Realtime crudos | Refresh/RPC ejecutados | Latencia refresh (avg/p95) | Errores |
|---|---|---|---|---|---|
| Cocina | 8 | 456 | 253 | 243.5 / 274.3 ms | 0 |
| Mozo | 8 | 456 | 82 | 1683.8 / 1778.5 ms | 0 |
| Caja | 4 | 0 | 0 | — | 0 |

### 20.4 Enfriamiento (121.9 s)

**0 eventos residuales, 0 refresh, 0 reconexiones** en los 20 oyentes — drenó limpio.

### 20.5 Comparación directa — 5 / 10 / 20 clientes

| | 5 (sec. 18) | 10 (sec. 19) | 20 (esta sección) |
|---|---|---|---|
| Oyentes cocina/mozo/caja | 2/2/1 | 4/4/2 | 8/8/4 |
| Duración ráfaga | 19.4 s | 17.8 s | 18.6 s |
| Transiciones | 45 | 45 | 45 |
| Errores / `PT409` / `40001` | 0/0/0 | 0/0/0 | 0/0/0 |
| Latencia transición (avg/p95) | 248.6/302.1 ms | 224.0/234.5 ms | 230.4/250.8 ms |
| Eventos crudos cocina | 108 | 216 | 456 |
| Refresh/RPC cocina | 68 | 124 | 253 |
| Latencia refresh cocina (avg/p95) | 245.9/329.2 ms | 233.5/280.4 ms | 243.5/274.3 ms |
| Eventos crudos mozo | 108 | 216 | 456 |
| Refresh/RPC mozo | 65 | 76 | 82 |
| Latencia refresh mozo (avg/p95) | 530.8/778.1 ms | 877.4/1073.9 ms | **1683.8/1778.5 ms** |
| Refresh/RPC caja | 0 | 0 | 0 |
| Reconexiones | 0 | 0 | 0 |

**Hechos medidos, no hipótesis:**
- **Eventos crudos siguen escalando exactamente lineal con los oyentes** en ambos roles (108→216→456 cocina y mozo — el pequeño salto 216→456 en vez de 432 en mozo es ×2.11, no ×2.00 exacto, pero dentro de ruido normal de timing entre corridas). Confirma fan-out lineal también en el segundo salto de nivel.
- **Cocina se mantiene estable en todo:** refresh/RPC escala sub-linealmente (68→124→253, aprox. ×1.82 y ×2.04) y su latencia de refresh se mantiene prácticamente plana en los tres niveles (245.9→233.5→243.5 ms de media) — ninguna señal de degradación al triplicar los oyentes de cocina de 2 a 8.
- **Mozo es distinto: el conteo de refresh/RPC casi dejó de crecer (65→76→82, solo +8% en el segundo salto pese a duplicar oyentes de 4 a 8) pero su latencia se disparó (531→877→1684 ms de media, ×3.17 acumulado desde el nivel 5; ×1.92 solo en este salto).** Es la señal más fuerte de las tres rondas: al mismo tiempo que el debounce coalesce cada vez más señales de mozo en menos refrescos, cada uno de esos refrescos tarda notablemente más — consistente con **contención**, no con más volumen de llamadas (el conteo casi no subió, la latencia sí).
- **0 errores, 0 conflictos, 0 reconexiones en los tres niveles.** Ningún criterio de parada de la sección 4 se activó: el aumento de latencia de mozo (877→1684 ms, ×1.92) queda por debajo del umbral de "p95 >3× el nivel anterior" (1073.9×3=3221.7 ms; 1778.5 ms medido).

**Hipótesis, explícitamente sin confirmar:**
- La contención en la latencia de mozo (no en el conteo) apunta a que la consulta del tablero de mozo (`getTableBoard`: 4 sub-consultas, 2 condicionales) compite por recursos cuando varios oyentes mozo la disparan cerca en el tiempo — más plausible que un problema de índices (que ya se descartó a simple vista en la sección 1.5) y más consistente con el costo estructural ya anotado en 11.2. Sigue sin confirmarse con `pg_stat_statements`; con 3 niveles ahora tengo una tendencia (no solo un punto), pero no una causa verificada.
- Que cocina no muestre el mismo patrón sugiere que la diferencia está en la forma de la consulta (`obtener_tablero_cocina()`, una sola RPC con joins) vs. la de mozo (4 llamadas separadas, 2 de ellas en `Promise.all` condicional) — una consulta compuesta de varias llamadas tiene más puntos donde la concurrencia entre sí misma puede generar espera, pero esto es una hipótesis de diseño, no algo que haya medido directamente (no tengo visibilidad de locks ni de planes de ejecución).
- Ninguna de estas hipótesis está confirmada por CPU/servidor todavía para este nivel — pendiente de que compartas esas métricas (sección 20.6).

### 20.6 Métricas de servidor — confirmadas por el usuario (23/09/2026)

Reportadas por vos, observadas en el Dashboard durante la ventana 20:13:00–20:17:37 UTC: **CPU muy baja, conexiones con máximo aproximado de 20/60 (dentro del límite del proyecto, sin saturación), memoria estable, IOPS <1, red/disco sin presión.**

**Nivel de 20 clientes queda aprobado técnicamente.** Señalaste explícitamente algo importante para la interpretación del hallazgo de la sección 20.5: **la degradación observada en el refresh de mozo (877→1684 ms de latencia media) es end-to-end (cliente + red + servidor combinados) y no debe atribuirse todavía a PostgreSQL, porque las métricas de servidor no muestran contención** (CPU baja, sin presión de IOPS/disco/memoria, conexiones lejos del máximo). Esto descarta parcialmente mi hipótesis de la sección 20.5 sobre contención *en el servidor* específicamente — deja abierto que el costo esté en otro punto del camino end-to-end (cliente, red, PostgREST, o el propio patrón de 4 sub-consultas de `getTableBoard` compitiendo entre sí sin que eso se traduzca en presión visible de CPU/IOPS del lado de Postgres). Corrijo la sección 20.5 con esta aclaración en vez de dejarla como estaba escrita.

### 20.7 Cierre completo del arnés

Detuve los 20 oyentes (`handle.stop()`, 0 canales residuales) y entregué+cobré (TOTAL, efectivo) los 3 pedidos de esta ronda (37, 38, 39) — **M01–M06 quedaron todas en `LIBRE`**. Las 22 sesiones de este arnés siguen abiertas en el navegador (no las cerré todavía porque no se pidió escalar de inmediato); si vas a revisar resultados antes de decidir sobre el nivel 40, las cierro también apenas lo confirmes, siguiendo el mismo protocolo de la sección 19.8.

**No escalé a 40 clientes — queda pendiente de revisión conjunta, según lo acordado.**

### 20.8 Cierre del arnés de 22 sesiones (23/09/2026)

Al ir a cerrar explícitamente las 22 sesiones del nivel 20 (mismo protocolo que 19.8: `removeChannel` + `realtime.disconnect()` + `signOut()` + recarga), encontré que la pestaña del navegador ya se había reiniciado sola entre turnos (pizarra limpia: `window.supabase`/`window.__cap` inexistentes). Esto cierra las conexiones de forma más abrupta que el protocolo manual — la destrucción del proceso de la pestaña corta inmediatamente los 22 sockets de Realtime a nivel de SO/navegador — pero no me permite confirmar programáticamente el `signOut()` de esas 22 sesiones específicas (sus JWT de auth pueden seguir técnicamente vigentes hasta expirar, aunque eso no mantiene ninguna conexión de Postgres/Realtime abierta, que es lo que importa para `Database Connections`). Antes de reconstruir para el nivel 40, esperé el mismo período de reposo de referencia (~3 min) para que el servidor termine de notar la desconexión abrupta.

## 21. Resultados — Nivel 4 (40 clientes), prueba de estrés (23/09/2026)

**Tratado como prueba de estrés/margen, no como requisito de aceptación del MVP**, según lo señalaste. Misma proporción 2:2:1: **16 cocina, 16 mozo-mesas, 8 caja** (42 sesiones: 40 oyentes + `mozoDriver` + `cocinaDriver`). Mismo throughput de negocio de siempre: 3 pedidos nuevos (15 detalles), exactamente 45 transiciones, mismo orden round-robin, mismas pausas 100–250 ms.

Reconstruí el arnés desde cero. Al autenticar las 42 sesiones, las primeras 8 de caja + 1 mozo fallaron por *rate limit* transitorio de auth (demasiadas llamadas `signInWithPassword` seguidas) — reintenté con una pausa de 400 ms entre llamadas y las 42 quedaron autenticadas; no es un hallazgo de capacidad de la app, es un límite del propio flujo de autenticación de Supabase ante 42 logins casi simultáneos desde mi arnés, algo que no ocurre en operación real. Antes de conectar, verifiqué M01–M06 en `LIBRE` y 0 pedidos abiertos.

### 21.1 Conexión y baseline en reposo (105.2 s)

40/40 conexiones `SUBSCRIBED` sin errores (56 refresh de conexión inicial: 16 cocina ×2 + 16 mozo ×1 + 8 caja ×1 = 56, exacto). Reposo previo de ~2 min 40 s, luego **105.2 s de reposo puro: 0 eventos, 0 refresh, 0 errores, 0 reconexiones** en los 40 oyentes.

### 21.2 Configuración de la ráfaga (no contada, ~7.0 s)

3 pedidos nuevos (M01→`pedido 40`, M04→`pedido 41`, M05→`pedido 42`), 15 detalles, enviados a cocina. `sendOk: true` en los 3.

### 21.3 Ráfaga escalonada (18.3 s)

**Transiciones de cocina:** 45/45 OK, **0 errores, 0 `PT409`, 0 `40001`**, 0 reconexiones. Latencia: media 232.8 ms, p50 221.6 ms, p95 261.6 ms — igual que en los niveles anteriores.

**Por rol, durante la ventana estricta de la ráfaga (18.3 s):**

| Rol | Oyentes | Eventos Realtime crudos | Refresh/RPC ejecutados | Latencia refresh (avg/p95) | Errores |
|---|---|---|---|---|---|
| Cocina | 16 | 864 | 472 | 248.1 / 295.8 ms | 0 |
| Mozo | 16 | 864 | 76 (+17 en cola, ver 21.4) | 3274.1 / 3740.2 ms | 0 |
| Caja | 8 | 0 | 0 | — | 0 |

### 21.4 Hallazgo nuevo en este nivel: cola/backlog de refresh de mozo que se derrama al enfriamiento

A diferencia de los niveles 5/10/20 (enfriamiento en 0 eventos desde el primer segundo), acá **17 refresh de mozo que ya estaban en curso cuando terminó la ráfaga se registraron recién durante los primeros 3.6 s del enfriamiento** (no son señales nuevas — no hay ningún evento crudo nuevo en el enfriamiento, son la cola final de señales ya disparadas durante la ráfaga que el patrón `refreshInFlight`/`refreshAgain` de cada oyente mozo todavía no había terminado de procesar). Sus latencias: **3401–3449 ms**, uniformemente altas, una por cada uno de los 16 oyentes mozo (`mozoL14` aparece dos veces: tenía dos refresh encolados).

**Cifra combinada de mozo (76 de la ventana estricta + 17 de la cola derramada = 93 refresh/RPC totales, todos disparados por señales de la ráfaga):** latencia media **3301.5 ms**, p95 **3732.5 ms**. Después de ese derrame de 3.6 s, el resto de los 131.5 s de enfriamiento quedó en 0 eventos — drenó limpio, solo que la cola tardó más en vaciarse que en los niveles anteriores.

### 21.5 Comparación directa — 5 / 10 / 20 / 40 clientes

| | 5 | 10 | 20 | 40 |
|---|---|---|---|---|
| Oyentes cocina/mozo/caja | 2/2/1 | 4/4/2 | 8/8/4 | 16/16/8 |
| Transiciones | 45 | 45 | 45 | 45 |
| Errores / `PT409` / `40001` | 0/0/0 | 0/0/0 | 0/0/0 | 0/0/0 |
| Latencia transición (avg/p95) | 248.6/302.1 | 224.0/234.5 | 230.4/250.8 | 232.8/261.6 ms |
| Refresh/RPC cocina | 68 | 124 | 253 | 472 |
| Latencia refresh cocina (avg/p95) | 245.9/329.2 | 233.5/280.4 | 243.5/274.3 | 248.1/295.8 ms |
| Refresh/RPC mozo (total, incl. cola) | 65 | 76 | 82 | **93** |
| Latencia refresh mozo (avg/p95) | 530.8/778.1 | 877.4/1073.9 | 1683.8/1778.5 | **3301.5/3732.5 ms** |
| Refresh/RPC caja | 0 | 0 | 0 | 0 |
| Reconexiones | 0 | 0 | 0 | 0 |
| Derrame al enfriamiento | no | no | no | **sí (17 refresh, 3.6 s)** |

**Hechos medidos, no hipótesis:**
- **Cocina se mantiene estable en los cuatro niveles** — latencia de refresh prácticamente plana (246→234→244→248 ms de media) pese a que los oyentes pasaron de 2 a 16 (×8) y el refresh/RPC escaló de 68 a 472 (×6.9, sublineal frente a ×8 de oyentes). Ninguna señal de degradación en cocina en todo el rango probado.
- **Mozo escala mal y empeora con cada salto**, con una curva que se acelera: ×1.65 (5→10), ×1.92 (10→20), **×1.96 (20→40, sobre la cifra combinada)** — no se estabiliza, cada duplicación de oyentes mozo cuesta proporcionalmente más en latencia, no menos.
- **Primera vez que aparece un efecto de cola/backlog que sobrevive a la ráfaga** — en los tres niveles anteriores el enfriamiento fue 0 eventos desde el primer instante; acá 16 de los 40 oyentes (uno con doble cola) todavía tenían un refresh pendiente de resolver 3.6 s después de terminada la ráfaga.
- **0 errores, 0 conflictos, 0 reconexiones en los cuatro niveles.** Ningún criterio de parada de la sección 4 se activó formalmente: el crecimiento de p95 de mozo (20→40) es ×2.10 (1778.5→3732.5 ms), por debajo del umbral de ×3, aunque es el salto más grande de los tres y el más cercano al límite.

**Hipótesis, explícitamente sin confirmar:**
- Con las métricas de servidor del nivel 20 mostrando CPU baja y sin contención (sección 20.6), y asumiendo que el nivel 40 se comporta de forma similar del lado de Postgres (todavía sin confirmar — pendiente de que compartas las métricas de este nivel), el cuello de botella parece estar en el lado cliente/red del patrón end-to-end, no en la base de datos: 16 oyentes mozo ejecutando en paralelo su lectura de 4 sub-consultas cada uno, compitiendo entre sí por el mismo canal HTTP/conexión del navegador hacia PostgREST, es un mecanismo plausible — pero sigue siendo hipótesis, no algo que haya medido directamente (no tengo visibilidad de colas HTTP del lado del navegador ni del pooler).
- La curva de mozo (×1.65, ×1.92, ×1.96) no muestra señales de estabilizarse en el rango probado — si esta tendencia continuara, un nivel 80 (no autorizado, no ejecutado) podría cruzar el umbral de ×3 sobre el p95 de 40. Esto es proyección, no medición: me detuve en 40 según lo acordado y no hay datos de un nivel más alto que la confirmen o la descarten.

### 21.6 Métricas de servidor — pendientes

No tengo acceso al Dashboard. Si tomaste CPU/conexiones/memoria/disco/network durante esta ventana, las agrego — en particular si `Database Connections` y CPU se mantuvieron en el mismo orden que en el nivel 20 (sección 20.6) pese al salto de latencia de mozo, eso reforzaría la lectura de que el cuello de botella es end-to-end/cliente y no de PostgreSQL.

### 21.7 Cierre completo del arnés y estado final

Detuve los 40 oyentes (0 canales residuales), entregué y cobré (TOTAL, efectivo) los 3 pedidos de esta ronda (40, 41, 42) — **M01–M06 quedaron todas en `LIBRE`** — y cerré por completo las 42 sesiones (`removeChannel` + `realtime.disconnect()` + `signOut()`, las 42 confirmadas).

**Me detengo acá. No preparé ni ejecuté el nivel 80, según lo acordado.**

## 22. Conclusión de la campaña de pruebas de capacidad (23/09/2026)

Cierre de la campaña completa (niveles 5, 10, 20 y 40 clientes, secciones 11–21), en tus palabras:

> MikuyApp fue probado progresivamente con 5, 10, 20 y 40 listeners concurrentes sobre Supabase Free.
>
> Hasta 20 listeners no se observó degradación funcional relevante ni presión significativa de infraestructura.
>
> Con 40 listeners todas las operaciones continuaron completándose correctamente, sin errores, conflictos ni desconexiones, pero se observó degradación del refresh del tablero de mozo, con latencias del orden de 3–4 segundos y cola residual durante el cooldown.
>
> Las métricas de CPU, conexiones, memoria, red y disco no evidenciaron saturación del servidor, por lo que esta degradación se registra como comportamiento end-to-end del flujo del mozo y no como límite demostrado de Supabase/PostgreSQL.
>
> No se justifica continuar a 80 listeners para el alcance operativo actual.

**Estado de la app tras la campaña:** el correctivo E1-T18 (`PT409`, sección 16–18) sigue implementado localmente y aplicado en DEV, sin cerrar hasta la revalidación humana pendiente (sección 2, restricción vigente desde el inicio de esta serie de correctivos). `acceptance.md` sigue sin tocar, a la espera de tu aprobación explícita posterior a la prueba humana/build en Windows. M01–M06 quedaron en `LIBRE` al cierre de cada nivel; no queda ningún arnés de prueba conectado a DEV.

**No se ejecutan más niveles de carga sin una nueva autorización explícita.**
