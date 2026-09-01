# MikuyApp — Bitácora de cambios post-MVP

Esta bitácora registra los cambios realizados después del cierre y aceptación del MVP v1.0.0. Cada cambio usa un identificador consecutivo independiente con formato `PM-###`.

La numeración PM no reemplaza, modifica ni renumera las evoluciones funcionales definidas en [PLAN_MVP.md](PLAN_MVP.md): Evolución 1 — Operación de caja, Evolución 2 — Inventario y las siguientes conservan su identidad original.

## Formato de entradas

Cada entrada debe indicar ID, fecha, tipo, nombre, estado, descripción, impactos, despliegue, evidencia, referencias y pendientes derivados. El detalle de implementación y aceptación permanece en sus specs; esta bitácora conserva solo el resumen maestro.

## PM-001 — DB Standardization

| Campo | Registro |
|---|---|
| ID | `PM-001` |
| Fecha | 2026-08-31 |
| Tipo | Técnica / Seguridad |
| Baseline | MVP v1.0.0 |
| Estado | `ACCEPTED + DEPLOYED` |
| Descripción | Estandarización selectiva y hardening del modelo PostgreSQL/Supabase posterior al cierre H1–H6, sin ampliar el alcance funcional del MVP. |
| Impacto funcional | Único cambio intencional: contextos autenticados inexistentes o inválidos rechazan con SQLSTATE `42501` y mensaje `No autorizado`. Los casos válidos conservan contratos y resultados. |
| Impacto técnico | Tres RPC centralizadas mediante `obtener_contexto_autenticado()`; cuatro funciones read-only declaradas `STABLE`; 16 `COMMENT ON`; 28 migraciones vigentes; RLS preservado en 10 tablas públicas y 27 policies. |
| Despliegue | Migración DBSTD aplicada y validada en Supabase remoto; frontend y versión `1.0.0` sin cambios. |
| Evidencia | DBSTD-TP01–TP26, regresión SQL, 297/297 tests automatizados, lint, typecheck, build, rollback compensatorio y validación remota aprobados. |
| Referencias | [Aceptación](../specs/DB-Standardization/acceptance.md), [despliegue](../specs/DB-Standardization/deployment.md), [estándar](DATABASE_STANDARD.md), [matriz de cumplimiento](DATABASE_COMPLIANCE_MATRIX.md) |
| Pendientes derivados | Semántica definitiva de `pedido.modificado_en/modificado_por`; posible separación futura del trigger; campaña futura y de baja prioridad de renombrado `rpc_`/`fn_`/`tgf_`/`trg_`/`pol_`. |
