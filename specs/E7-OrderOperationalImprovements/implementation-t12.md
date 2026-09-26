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
| E7-TH06 | **Falló inicialmente — corregida, pendiente de revalidación humana** | Defecto posterior al cobro total (§2) |
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

## 4. Pendiente

- **Revalidación humana de TH06** en dispositivos reales (no se marca aprobada aquí).
- TH07.
- Mejora UX “1 línea” → “1 producto” (registrada aparte).
- Revalidación cloud segura por PM-002.
