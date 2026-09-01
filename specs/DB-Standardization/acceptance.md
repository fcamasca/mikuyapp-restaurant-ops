# DB-Standardization — Aceptación

## Estado

**ACCEPTED**

- Fecha de aceptación: 2026-08-31 (America/Lima).
- Línea base: `b04e56e`.
- Aprobación humana: AH-01 a AH-06 aprobadas explícitamente.

## Alcance aceptado

- Tres RPC H6 centralizadas mediante `public.obtener_contexto_autenticado()`.
- Hardening `42501 / No autorizado` para contextos inexistentes o inválidos, como único cambio funcional intencional aprobado.
- Cuatro funciones declaradas `STABLE`.
- Dieciséis `COMMENT ON` aprobados.
- Preservación de tablas, datos, constraints, índices, RLS, 27 policies, grants, auditoría, triggers y comportamiento vigente de `pedido.modificado_*`.
- Migración DBSTD nueva posterior a H6, sin editar migraciones históricas.

## Evidencia aprobada

- DBSTD-TP01 a DBSTD-TP26: aprobadas.
- Migraciones desde base vacía: 28/28.
- Archivos SQL: 43/43.
- Suites SQL autocontenidas: 25/25.
- Escenarios concurrentes: 5/5.
- Tests automatizados: 297/297.
- Lint PostgreSQL local: exitoso.
- Typecheck: exitoso.
- Build: exitoso.
- Rollback compensatorio: probado; restaura H6 y permite reaplicar DBSTD correctamente.

## Pendientes fuera de alcance

- Semántica definitiva de `pedido.modificado_en` y `pedido.modificado_por`.
- Posible separación futura de responsabilidades del trigger de auditoría.
- Posible campaña futura de renombrado de objetos.

## Entorno remoto

Supabase remoto no fue intervenido. Esta aceptación no declara realizado ni autoriza un despliegue remoto.
