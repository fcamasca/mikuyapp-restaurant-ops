# E7 — Evidencia de validación humana: T12

Rama `feature/E7-OrderOperationalImprovements`, sobre `9cdba08` (T11 técnicamente completa). No constituye aceptación; no existe `acceptance.md`. T12 **en curso**.

## 1. Estado de las pruebas humanas

| ID | Estado | Observación |
|---|---|---|
| E7-TH01 | Aprobada (responsable) | — |
| E7-TH02 | Aprobada (responsable) | — |
| E7-TH03 | Aprobada (responsable) | — |
| E7-TH04 | Aprobada (responsable) | — |
| E7-TH05 | Aprobada (responsable) | Impresión física de comandas |
| E7-TH06 | **FALLIDA (dos fallas humanas) — correcciones aplicadas, pendiente de revalidación humana** | 1ª: respuesta vacía tratada como error (§2). 2ª: la vista del mozo no se resincronizaba por Realtime tras el cobro (§5) |
| E7-TH07 | No ejecutada | Pendiente |

Mejora UX registrada aparte y **no resuelta** en esta corrección: texto “1 línea” → “1 producto”.

## 2. Defecto TH06 — vista del mozo tras el cobro total

**Observado:** pedido mixto completado, entregado (`ENTREGADO` / mesa `PENDIENTE_PAGO`) y cobrado por caja con saldo total. Después del cobro, la pantalla del MOZO seguía mostrando el pedido #43 como `ENTREGADO` / `PENDIENTE_PAGO` con “No pudimos cargar el pedido vigente. Intenta nuevamente.”; `Reintentar` no se recuperaba.

**Reproducción (antes de corregir):**

- Servicio: `getOrderReview` sobre un pedido que ya no devuelve filas → `operation-error` “No pudimos cargar el pedido vigente…”.
- Stack Supabase local real (`scripts/e7_t12_th06.cmd` → `scripts/e7_t12_th06_repro.mjs`, servicios reales del frontend, sesiones MOZO/COCINA/CAJA y suscripción Realtime del mozo): cobro TOTAL confirmado; BD `PAGADO` / mesa `LIBRE`; el tablero de mesas del mozo ya mostraba la mesa `LIBRE` sin pedido; pero `getOrderReview` (resincronización y `Reintentar`) devolvía el mismo error → **DEFECTO REPRODUCIDO**.

**Causa:** la base de datos y el cobro son correctos. Para el MOZO, un pedido `PAGADO` (o `ANULADO`) deja de ser legible (RLS `pedido_select_vigente_mozo_local` y filtro de estados vigentes en `getOrderReview`). El servicio trataba esa consulta vacía como error de conexión y `WaiterOrderPage` no tenía un caso para “el pedido dejó de ser vigente”; la señal Realtime, la carga inicial y `Reintentar` terminaban siempre en el mismo error. Comportamiento heredado de H5 (idéntico en `main`), no introducido por E7.

**Corrección (frontend, mínima; sin migraciones ni cambios en pagos, H5 o E1):**

- `src/services/waiterOrderService.ts`: `getOrderReview` devuelve `{ kind: 'order-not-current', recoverable: false }` cuando la consulta no falla pero el pedido ya no está vigente; un error real de lectura sigue siendo `operation-error` recuperable.
- `src/pages/WaiterOrderPage.tsx`: ante `order-not-current` la vista vuelve a mesas (mismo flujo existente que tras liberar la mesa) desde la resincronización Realtime, la carga inicial y `Reintentar`. `onBack` se usa vía referencia para no recrear la suscripción Realtime en cada render.

## 3. Pruebas ejecutadas tras la corrección

| Prueba | Resultado |
|---|---|
| Nuevas en `tests/waiterBoard.test.mjs`: pedido PAGADO → `order-not-current`; fallo real → `operation-error` recuperable; la página vuelve a mesas desde señal, carga y `Reintentar` | PASS |
| Focales mozo / Realtime / caja / impresión / rutas (`waiterBoard`, `waiterRealtime`, `h5Realtime`, `cashierService`, `cashierPage`, `cashierPrint`, `appRoutes`) | 124/124 PASS |
| Suite Node completa | 389/389 PASS |
| `tsc --noEmit` | PASS |
| Stack Supabase local real (`scripts/e7_t12_th06.cmd`): reapertura antes del primer pago (bebida → `LISTO`/`PEDIDO_LISTO`, segunda entrega), cobro TOTAL, BD `PAGADO`/`LIBRE`, señal Realtime al mozo (220 ms) y `Reintentar` → `order-not-current`, tablero de mesas `LIBRE` sin pedido | **TH06 CORREGIDO** (exit 0) |

No se ejecutó SQL: la corrección no toca la base de datos. La fixture del stack local se eliminó (`db reset`) y el stack se apagó.

## 4. Pendiente (tras la primera falla)

- **Revalidación humana de TH06** en dispositivos reales (no se marca aprobada aquí).
- TH07.
- Mejora UX “1 línea” → “1 producto” (registrada aparte).
- Revalidación cloud segura por PM-002.

## 5. Segunda falla humana de TH06 — sincronización Realtime del mozo

**Observado (revalidación humana, app en `localhost` con `npm run dev` contra el Supabase cloud de `.env.local`, ref `ibfr…uinf`; incluye `94f98ee`):** tras el cobro total la BD quedó `PAGADO` / mesa `LIBRE`, pero la vista del MOZO no se actualizó sola; sólo con un refresh manual apareció el estado correcto.

**Diagnóstico con instrumentación temporal** (`07cec57`, panel `?rtdebug=1`: canales, estados, señales, refetch, navegación, auth y perfil). Registro del mozo antes de corregir:

- Cada montaje de `WaiterOrderPage` / `WaiterTablesPage` registraba `suscribiendo (canales=0 …)` e inmediatamente `suscribiendo (canales=1 mismo_topic=joining)`, seguido de `stop` y `CLOSED`; **nunca** `SUBSCRIBED` para la vista visible ni ninguna `SEÑAL`.
- Lo mismo tras `auth SIGNED_IN` (al volver a la pestaña), que recarga el perfil y desmonta/remonta la vista operativa.
- El paso a mesas observado no vino de Realtime: lo produjo el remontaje por `SIGNED_IN` (carga inicial con la corrección de `94f98ee`).

**Causa:** `supabase-js` (`RealtimeClient.channel(topic)`) devuelve el canal existente con el mismo topic. Cuando una vista se desmonta y se vuelve a montar antes de que Realtime confirme la salida del canal anterior (React `StrictMode` en desarrollo; recarga del contexto de perfil tras `SIGNED_IN`/`TOKEN_REFRESHED` en cualquier ambiente), la vista nueva recibe el canal saliente; `subscribe()` no registra callback sobre un canal no cerrado y, al completarse la salida, la vista queda sin suscripción y sin error. Afecta a todos los usuarios de `subscribeToOperationsChanges` (mozo, cocina, caja). No es un problema de publicación, RLS ni permisos: las señales de `mesa` sí se emiten para el MOZO. La señal `pedido` `ENTREGADO → PAGADO` no llega al MOZO por diseño (la RLS de MOZO sólo expone pedidos vigentes); la señal `mesa` `PENDIENTE_PAGO → LIBRE` sí, y basta para disparar el refetch autoritativo.

**Corrección (`bbf9edd`, mínima, sin cambios de BD, pagos ni polling):** `operationsRealtimeService` usa un topic propio por suscripción (`<channelName>:<n>`), de modo que un remontaje nunca hereda un canal saliente. Se mantiene el patrón señal Realtime → refetch autoritativo.

**Pruebas:**

| Prueba | Resultado |
|---|---|
| Nueva regresión en `tests/waiterRealtime.test.mjs` con un cliente que reproduce la semántica de `supabase-js` (reutilización por topic, salida asíncrona): remontaje antes de la salida sigue recibiendo la señal `mesa` `LIBRE` y dispara el refetch; topics únicos por suscripción | **Falla sin la corrección, pasa con ella** |
| Focales Realtime/mozo/cocina/caja (`waiterRealtime`, `h5Realtime`, `kitchenRealtimeService`, `kitchenBoard`, `waiterBoard`, `cashierService`, `cashierPage`, `cashierPrint`) | 144/144 PASS |
| Suite Node completa | 391/391 PASS |
| `tsc --noEmit` | PASS |
| Cloud (localhost contra `ibfr…uinf`, instrumentación activa), pedidos #46 y #47 | Cada montaje: topic nuevo, `mismo_topic=ninguno`, `SUBSCRIBED`; señales de detalle/pedido/mesa recibidas y refetch en todo el flujo (envío, cocina, entrega). Con el mozo en mesas, los dos cobros totales produjeron `SEÑAL mesa UPDATE … estado=LIBRE` (#47 y #46) y el tablero pasó a `LIBRE` **sin refresh manual** |

**Pendiente para cerrar la verificación técnica:** repetir el cobro total con el MOZO **dentro de la pantalla del pedido** (esperado: `SEÑAL mesa … LIBRE` → `resync revisión=order-not-current` → navegación a mesas) y comprobar `Reintentar`. Después, retirar la instrumentación temporal y revalidación humana de TH06. TH06 **no** se marca aprobada.
