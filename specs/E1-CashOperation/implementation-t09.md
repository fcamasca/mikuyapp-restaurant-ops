# E1 — Entrega parcial de construcción: T09

Fecha: 2026-09-14. No constituye aceptación de E1.

E1-T09 queda **COMPLETADA técnicamente en PostgreSQL local aislado**. `rpc_registrar_pago_pedido_v2` permite N pagos, calcula subtotal/descuento/neto/pagado/saldo en servidor, separa propina y conserva sesión, actor, medio, hora e idempotencia. El orden definitivo es `sesion_caja → pedido → mesa`.

Un parcial conserva `ENTREGADO/PENDIENTE_PAGO`; saldo cero produce `PAGADO`, historial y mesa `LIBRE`. Cada pago genera auditoría atómica y las mutaciones de detalle se bloquean después del primero. No se creó UI, `pago_detalle`, subcuentas, recibos, reversos ni devoluciones.

Base final: `mikuyapp-e1-t09-validation-20260914/e1_t09_3932f2a7cc654cf3b3da5d2f64a05d99`, sin red ni bind mounts.

- Replay limpio: 35 migraciones; constraint previo preservado más `PAGO`.
- TP32–TP47 backend aplicables y cuatro carreras independientes aprobados.
- Checkpoint: T04 132, T05 15, T06/T07 8 grupos y T08 27; T03 reutilizada.

Se corrigieron dos precedencias reales del adaptador H5: reintento idempotente posterior al pago y validación de argumentos/otro local antes de terminalidad. T08 y T07 volvieron a aprobar.

No se ejecutaron Node, `typecheck`, `build` ni regresión integral H1–H6/PM-001. No se modificaron `PLAN_MVP.md`, PM-002, ambientes alojados ni migraciones históricas; no hubo commit, push/merge ni `acceptance.md`.
