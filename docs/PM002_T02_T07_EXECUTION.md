# PM-002 — Evidencia de ejecución T02–T07

## Alcance y estado

- Rama: `feature/Environment-Separation`.
- Estado conservado: `LEGACY_SHARED`.
- No se creó PROD, no se modificó Cloudflare y no se ejecutó DDL/DML remoto.
- Las 28 migraciones históricas permanecen intactas.

## Estado por tarea

| Tarea | Estado | Evidencia |
|---|---|---|
| PM002-T02 | **Completada** | Inventario y rutas por estado en `docs/PM002_ENVIRONMENTS.md`; estado vigente `LEGACY_SHARED`, sin cambios de variables. |
| PM002-T03 | **Completada** | Matriz por contexto/estado y nombres de variables públicas en `.env.example`; ningún valor sensible documentado. |
| PM002-T04 | **Completada** | Guardia acotada en `scripts/environmentGuard.mjs`, integrada a `predev`/`prebuild`; TP07–TP12 aprobaron 8/8. |
| PM002-T05 | **Completada** | Contrato local, `.env.local` ignorado, CI con valores públicos sintéticos y separación de secretos documentada; scan sin secretos detectados. |
| PM002-T06 | **Completada** | Reset local sin seed: 28/28 migraciones, catálogo reconciliado y lint limpio. En reset aislado con fixtures: 25/25 suites SQL autocontenidas y 5/5 escenarios concurrentes. Regresión: 305/305, typecheck y build aprobados. |
| PM002-T07 | **Completada** | Migraciones local/remoto 28/28 alineadas; configuración alojada Supabase y configuración vigente de Cloudflare inventariadas y clasificadas en `docs/PM002_T07_HOSTED_AUDIT.md`. |

## Evidencia técnica consolidada

- Baseline production-equivalent, creado con `supabase db reset --local --no-seed`: 10 tablas públicas, RLS en 10/10, 27 policies, 17 funciones, 2 triggers de usuario y cero filas en `local`/`rol`.
- Publicación `supabase_realtime`: `detalle_pedido`, `mesa` y `pedido`; `pago` permanece excluida.
- `supabase db lint --local --level error`: cero errores de esquema.
- SQL local: 25 suites autocontenidas y cinco carreras reales; todas aprobaron y sus limpiezas verificaron cero fixtures residuales.
- Automatización: 305/305 tests; guardia de ambientes 8/8; `npm run typecheck` y `npm run build` exitosos.
- Auditoría remota de solo lectura: las 28 versiones de migración coinciden. El esquema lógico coincide salvo grants/default privileges provistos por plataforma para `service_role`; no se aplicó ninguna corrección remota.

## Hallazgo y cierre de T07

El remoto concede a `service_role` privilegios completos sobre funciones, tablas y secuencias, además de defaults más amplios; el runtime local reconstruido desde migraciones presenta un subconjunto. La evidencia alojada lo clasifica como comportamiento/configuración administrada observada de Supabase: debe verificarse en PROD, pero no justifica por sí sola una migración.

Cloudflare conserva scopes separados Production/Preview, rama Production `main`, build `npm run build` → `dist` y las tres variables vigentes en ambos scopes. Ambos apuntan al proyecto actual en estado `LEGACY_SHARED`. Las variables adicionales de la guardia aún no existen: deben prepararse primero para Preview en T12 y posteriormente para Production en T13, pues desplegar antes puede hacer fallar el build.

El historial/auditoría de variables no está disponible con la evidencia actual y se registra como **N/A para PM002-TP06**, sin inferir datos históricos. Esto no impide cerrar T07 porque la configuración vigente, sus diferencias y todas las dependencias productivas relevantes quedaron identificadas.
