# E7-T10 — Procedimiento del ambiente Supabase aislado de validación

Objetivo: cerrar T10 en Supabase real (PostgreSQL 17, PostgREST, Auth y Realtime) **sin tocar el proyecto compartido con Production** (PM-002 `TRANSITIONING`). Este ambiente es sólo de validación de E7: sin tráfico productivo, sin Cloudflare, sin cambios a PM-002.

> Nunca ejecutar `supabase link` para este proyecto: cambiaría el enlace local que hoy apunta al proyecto compartido. Todos los comandos usan la URL de conexión explícita. Ningún valor secreto se guarda en `.env.local`, `.env.example`, el repositorio ni la evidencia.

## 0. Requisitos y cuota

- Cuenta Supabase del responsable, Docker Desktop (ya usado en E1 con `public.ecr.aws/supabase/postgres:17.6.1.166`) y Node 22 del proyecto (`node_modules` instalados).
- **Cuota:** el plan Free admite 2 proyectos activos y la organización ya tiene `mikuyapp` (compartido) y `mikuyapp-prod`. Si Supabase no permite crear un tercer proyecto, **detener T10-DEV y reportarlo**: no pausar `mikuyapp-prod` ni aplicar E7 en `mikuyapp` sin una decisión explícita, porque ambos pertenecen a PM-002.

## 1. Crear el proyecto aislado

1. Dashboard → New project: nombre `mikuyapp-e7-validacion`, misma región del proyecto actual, PostgreSQL 17 (versión por defecto vigente), contraseña de base nueva y exclusiva.
2. Anotar fuera del repositorio: URL `https://<ref>.supabase.co`, clave publicable, `service_role` y la cadena de conexión **directa** (Project Settings → Database → Connection string, modo *session*/directo, puerto 5432).
3. Confirmar que `<ref>` es distinto de los refs de `.env.local` y `supabase/.temp/project-ref` (el script de validación lo vuelve a comprobar y aborta si coincide).

## 2. Baseline y migraciones

Baseline requerida: **las 49 migraciones vigentes hasta `20260922000100_e1_delta_t18_migrar_errcode_conflicto_funcional.sql`** (H1–H6, PM-001, E1 incluida E1-T18). Luego E7: `20260924000100` … `20260924000800`. Total 57, en orden, desde la rama `feature/E7-OrderOperationalImprovements`.

PowerShell, desde la raíz del repositorio:

```powershell
$env:E7_VALIDATION_DB_URL = "<cadena de conexión directa del proyecto de validación>"
npx supabase db push --db-url $env:E7_VALIDATION_DB_URL --dry-run   # debe listar las 57 migraciones
npx supabase db push --db-url $env:E7_VALIDATION_DB_URL
npx supabase migration list --db-url $env:E7_VALIDATION_DB_URL      # 57 aplicadas, remoto = local
```

Si una migración falla: detener, **no** corregir a mano en la base; reportar el error completo. La corrección se hará con una migración nueva.

## 3. Seed, usuarios, roles y Realtime

- Seed: no es necesario (`supabase/seed.sql` sólo crea el local demo). Los datos de validación los crea el script del paso 5 con un identificador de corrida: un local `E7-VAL-<run>`, 4 usuarios de Auth (`MOZO` ×2, `COCINA` ×2) con contraseña aleatoria efímera y correo `@example.invalid`, sus `perfil_usuario`, una mesa y dos productos (con y sin cocina).
- Roles: los cuatro códigos de `rol` los crea la baseline. El script usa `service_role` **sólo** para crear usuarios y la fixture; todas las operaciones E7 se ejecutan con sesiones `authenticated` reales vía PostgREST.
- Realtime: la migración `20260827000900_kitchen_realtime_signals.sql` deja la publicación `supabase_realtime` con `detalle_pedido`, `pedido` y `mesa`. Verificar en Database → Publications que sean exactamente esas tres. Realtime debe estar habilitado (por defecto).

## 4. Verificaciones SQL en PostgreSQL 17 real (Docker + psql)

```powershell
$img = "public.ecr.aws/supabase/postgres:17.6.1.166"
docker run --rm -v "${PWD}:/repo" $img psql $env:E7_VALIDATION_DB_URL -X -At -c "select version()" -c "select count(*) from supabase_migrations.schema_migrations"
foreach ($t in "e7_t02_modelo","e7_t03_envio","e7_t04_recepcion_tablero","e7_t05_cancelacion","e7_t05b_edicion_retiro","e7_t09_impresion_comanda","e7_t10_integracion") {
  docker run --rm -v "${PWD}:/repo" $img psql $env:E7_VALIDATION_DB_URL -X -q -v ON_ERROR_STOP=1 -f "/repo/supabase/tests/$t.sql"
  "$t -> exit $LASTEXITCODE"
}
docker run --rm -v "${PWD}:/repo" -e PSQL_CONN=$env:E7_VALIDATION_DB_URL $img bash /repo/scripts/e7_concurrency.sh all
```

- Todas las pruebas terminan en `ROLLBACK` salvo la fixture de concurrencia, que se limpia al final con `e7_concurrency_cleanup.sql`.
- `e7_t10_integracion.sql` incluye la verificación de privilegios de `service_role` (migración `…800`) y la visibilidad RLS de las filas-señal Realtime.
- Si Supabase rechaza `insert into auth.users` desde el rol `postgres`, anotarlo como diferencia de plataforma y continuar con el paso 5 (cubre el recorrido vía API).

## 5. Recorrido integrado vía PostgREST/Auth/Realtime reales

```powershell
$env:E7_VALIDATION_SUPABASE_URL = "https://<ref>.supabase.co"
$env:E7_VALIDATION_PUBLISHABLE_KEY = "<clave publicable del proyecto de validación>"
$env:E7_VALIDATION_SERVICE_ROLE_KEY = "<service_role del proyecto de validación>"
node --experimental-strip-types scripts/e7_t10_validation.mjs
Remove-Item Env:E7_VALIDATION_SERVICE_ROLE_KEY, Env:E7_VALIDATION_DB_URL
```

`scripts/e7_t10_validation.mjs` usa los mismos servicios del frontend (`waiterOrderService`, `kitchenRealtimeService`, `kitchenCommandService`, `operationsRealtimeService`) con dos mozos y dos cocinas autenticados:

1. pedido mixto, edición y retiro vía RPC; `PT409` de PostgREST ante snapshot antiguo;
2. envío: bebida `LISTO`; **Realtime** entrega el cambio a la cocina (sin bebida, con comanda 1);
3. primera solicitud de impresión concurrente de dos cocinas (una OK, otra `PT409`), reimpresión = 2;
4. recepción completa (cocina 2) → **Realtime** a cocina 1; reintento = 0 sin error;
5. cancelación (mozo B) → **Realtime** a cocina (señal `UPDATE` de `pedido`) y resincronización del mozo B con la sección de cancelados; transición sobre el cancelado → `PT409`;
6. resincronización del snapshot autoritativo y documento imprimible (`COPIA 1`, línea `CANCELADO`);
7. avance individual hasta `LISTO`, cancelación bloqueada en `EN_PREPARACION`, pedido `LISTO`/mesa `PEDIDO_LISTO`.

Salida esperada: `== E7-T10 validación aislada: N/N OK` y código de salida 0. La impresión física no forma parte de T10 (E7-TH05).

## 6. Evidencia a devolver

Pegar (sin secretos) la salida de los pasos 2, 4 y 5: `migration list`, `version()`, resultado de cada SQL, salida de `e7_concurrency.sh` y del script Node. Con eso se actualiza `implementation-t10.md` y se decide el cierre de T10.

Opcional, tras la validación: pausar o eliminar el proyecto `mikuyapp-e7-validacion`.
