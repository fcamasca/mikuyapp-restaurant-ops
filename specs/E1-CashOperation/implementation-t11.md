# E1 — Entrega parcial de construcción: T11

Fecha: 2026-09-17. No constituye aceptación de E1.

E1-T11 queda **COMPLETADA técnicamente en PostgreSQL local aislado**. La migración consolida el catálogo append-only ya producido por T04–T09, añade índices de reconstrucción por sesión/pedido y expone `rpc_obtener_auditoria_financiera` únicamente a CAJA y ADMINISTRADOR activos del mismo local. No modifica las RPC de escritura ni crea infraestructura genérica.

El catálogo final contiene exclusivamente `APERTURA`, `ENTRADA`, `SALIDA`, `SOLICITUD_DESCUENTO`, `AUTORIZACION_DESCUENTO`, `RECHAZO_DESCUENTO`, `PAGO`, `ANULACION`, `CIERRE` y `CIERRE_SUPERVISOR`. Una decisión de descuento es inmutable y no existe RPC, evento ni flujo de revocación en E1.

Entorno: contenedor local aislado `mikuyapp-e1-t09-validation-20260914`, base de validación `e1_t11_validation_20260917`, sin red ni bind mounts. La baseline ya contenía T10; se aplicó únicamente la migración T11 y no se hizo replay completo.

- TP49–TP55: aprobados.
- Regresión T04: 132 comprobaciones aprobadas.
- Regresión T05: 15 comprobaciones aprobadas.
- Regresiones T06, T07 y T09: aprobadas.
- Catálogo exacto y ausencia de revocación: confirmados mediante constraint PostgreSQL.
- Escritura directa `INSERT/UPDATE/DELETE`: denegada.
- FK, rollback atómico, RLS, grants, owner y `search_path`: aprobados.
- Auditorías con actor inexistente: cero.

El primer intento de TP49/TP50 informó una aserción genérica y no reprodujo al repetirla. Se mejoró exclusivamente el diagnóstico del fixture; no hubo defecto productivo ni cambio de migración. El runner se corrigió para clonar una baseline local validada y aplicar sólo T11 en ejecuciones futuras.

No se ejecutaron la suite Node integral, `typecheck`, `build`, TP62–TP64 ni la regresión integral T13. No se inició T12, no se tocaron ambientes alojados, PM-002 ni `PLAN_MVP.md`, y no hubo commit, push o merge.
