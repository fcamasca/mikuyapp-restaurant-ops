# MikuyApp — Aceptación de H5: entrega, caja, cobro e impresión

**Fecha de aceptación:** 2026-08-30  
**Estado:** Cerrado, validado y aceptado.

## Alcance entregado

H5 incorpora la entrega segura por `MOZO`, la lectura autoritativa y aislada de consumos para `CAJA`, el cobro transaccional con pago único, precuenta, ticket interno, sincronización Realtime y presentación imprimible mediante navegador para papel térmico de 80 mm.

La solución mantiene PostgreSQL como autoridad para estados, total, concurrencia, historial, aislamiento por local y privilegio mínimo. El nombre visible del producto proviene de `producto.nombre` vigente; `detalle_pedido.precio_unitario` conserva el precio histórico.

## Decisiones funcionales finales

- `MOZO` entrega mediante `entregar_pedido(p_pedido_id)` y `CAJA` cobra mediante `registrar_pago_pedido(p_pedido_id, p_medio)`.
- `ADMINISTRADOR` conserva las funciones administrativas aprobadas en H2, pero no ejecuta entrega ni cobro H5.
- La entrega exige al menos un detalle y todos los detalles en `LISTO`; estos permanecen `LISTO` después de entregar.
- `ENTREGADO` no es terminal. Antes del pago, el `MOZO` del mismo local puede agregar productos: el nuevo detalle nace `ABIERTO`, los anteriores siguen `LISTO`, el pedido vuelve al flujo operativo derivado y la mesa pasa de `PENDIENTE_PAGO` a `OCUPADA`.
- Tras completar cocina nuevamente, puede realizarse otra entrega y la mesa vuelve a `PENDIENTE_PAGO`.
- Solo `PAGADO` y `ANULADO` son terminales.
- El total de cobro se calcula en PostgreSQL desde `sum(cantidad * precio_unitario)` y existe un único pago por pedido.
- Realtime continúa exclusivamente sobre `detalle_pedido`, `pedido` y `mesa`; `pago` no se publica.
- La precuenta está disponible para `ENTREGADO`; el ticket interno, únicamente después de `PAGADO`.
- La impresión usa `window.print()` y CSS para 80 mm; no incorpora ESC/POS, impresión silenciosa ni comprobantes fiscales.
- La presentación usa `local.nombre`, locale `es-PE` y zona horaria `America/Lima`.

## Evidencia de aceptación

- Pruebas automatizadas: **289/289 aprobadas**.
- Pruebas SQL remotas: **19/19 aprobadas**.
- Pruebas humanas H5-TH01–H5-TH09: **9/9 aprobadas**.
- Typecheck, build, `supabase db lint --linked --level error` y `git diff --check`: aprobados.
- Migraciones local/remoto: **26/26 alineadas**; última migración H5 aplicada: `20260830000200_h5_reopen_delivered_order.sql`.
- Fixtures residuales H5: **0**.
- Concurrencia, rollback, pago único, aislamiento entre locales, separación de roles y regresión H1–H4: aprobados.

## Observaciones y pendientes

El build conserva un aviso no bloqueante porque el bundle principal supera ligeramente 500 kB. No representa un defecto funcional ni bloquea la aceptación.

No existen pendientes bloqueantes de H5. Esta aceptación cierra H5, pero no declara terminado el MVP: H6 permanece pendiente como siguiente hito.
