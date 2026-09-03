# PM-002 — Evidencia de ejecución T10

## Estado

**PM002-T10 COMPLETADA.** Las 28 migraciones versionadas fueron aplicadas a `mikuyapp-prod` y el baseline técnico fue reconciliado sin seed, datos DEV ni cambios manuales.

PM-002 permanece en **`TRANSITIONING`**. Local, Preview y Production continúan en el proyecto actual; Cloudflare no apunta todavía al nuevo PROD.

## Preflight

| Control | Resultado |
|---|---|
| Rama | `feature/Environment-Separation` |
| Estado Git previo | Limpio |
| Target enlazado | `mikuyapp-prod`, ref `snfm…pavp` |
| DEV descartado | La CLI no estaba enlazada a `ibfr…uinf` al ejecutar el push |
| Estado target | `ACTIVE_HEALTHY`, `sa-east-1`, PostgreSQL 17 GA |
| Historial inicial | 0 migraciones remotas; 28 locales pendientes |
| Dry-run | Exactamente 28 migraciones; `seeds: []`; `roles: []` |

El enlace se autenticó mediante el rol temporal administrado por Supabase; no se almacenó una contraseña en el repositorio.

## Aplicación e historial

`supabase db push --linked` aplicó, en orden, los 28 archivos de `supabase/migrations/`, desde `20260823235106_h1_initial_schema.sql` hasta `20260831000100_dbstd_t02_authenticated_context_hardening.sql`.

- Resultado: 28/28 aplicadas, cero errores.
- Historial posterior: 28 versiones locales y remotas alineadas.
- Migraciones desconocidas: 0.
- Migraciones nuevas o históricas modificadas: 0.
- `supabase/seed.sql`: no ejecutado.

## Catálogo PROD

| Contrato | Resultado |
|---|---|
| Tablas públicas | 10 |
| RLS | 10/10 habilitadas |
| Policies | 27 |
| Funciones públicas | 17; firmas y metadatos reconciliados con el dump local |
| Triggers de aplicación | 2 |
| Secuencias | 5 asociadas a identidades del baseline |
| Índices explícitos | 15 |
| Constraints | 38 |
| Owners / `SECURITY DEFINER` / `search_path` | Sin diferencias frente al baseline local normalizado |
| Lint remoto | Cero errores de esquema |

La comparación normalizada del dump local contra PROD fue exacta al excluir exclusivamente sentencias de grants/default privileges administradas por la plataforma.

## Realtime

La publicación `supabase_realtime` contiene exactamente tres tablas MikuyApp habilitadas:

- `detalle_pedido`
- `mesa`
- `pedido`

`pago` está excluida. Las otras siete tablas públicas también permanecen excluidas.

## Grants y default privileges

Los grants explícitos de `anon` y `authenticated` definidos por las migraciones se conservaron. PROD añadió el mismo patrón alojado observado en T07:

- `service_role` recibe `ALL` sobre las 17 funciones, 10 tablas y 5 secuencias;
- los default privileges alojados para tablas, funciones y secuencias son más amplios que en el runtime local;
- existen defaults adicionales administrados para `anon`, `authenticated` y `service_role`.

Clasificación: **comportamiento administrado/operativo de Supabase**, reproducido automáticamente en el nuevo proyecto. No es drift accidental del esquema MikuyApp y no justifica una migración correctiva.

## Ausencia de datos

El dump `data-only` del schema `public` contiene cero sentencias `COPY`/`INSERT`:

- `MIKUY-DEMO`: ausente.
- locales, maestros y roles cargados: 0.
- perfiles: 0.
- pedidos: 0.
- detalles: 0.
- pagos: 0.
- usuarios Auth: la consola confirma “No users in your project”.
- datos o transacciones copiados desde DEV: 0.

Las migraciones crearon estructura, no carga productiva.

## Pruebas ejecutadas

- Target/ref y exclusión de DEV: aprobados.
- Dry-run 28 migraciones sin seeds: aprobado.
- `db push`: aprobado 28/28.
- Reconciliación de historial: aprobada 28/28.
- Dump de catálogo y comparación normalizada: aprobados.
- Conteos de tablas, RLS, policies, funciones, triggers, secuencias, índices y constraints: aprobados.
- Realtime mediante catálogo alojado: 3 tablas esperadas; `pago` excluida.
- `supabase db lint --linked --level error`: aprobado, cero errores.
- Dump `data-only`: cero datos públicos.
- Auth dashboard: cero usuarios.

No se ejecutaron suites funcionales que crean fixtures o requieren Auth/maestros. Las pruebas de cuatro roles, maestros y flujo mesa → pago quedan diferidas a T11/T13 porque sus precondiciones aún no existen.

## Restricciones preservadas

No se ejecutó T08/T11, seed, carga inicial, creación de usuarios/perfiles, modificación Auth/Data API/SSL/red, cambio Cloudflare, cutover, copia DEV, replicación, refresh, sincronización, reset remoto, `DROP` o `TRUNCATE`.
