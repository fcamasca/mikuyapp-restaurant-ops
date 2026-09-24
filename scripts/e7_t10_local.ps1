# E7-T10 — Validación en el stack Supabase LOCAL real (Docker + Supabase CLI del repositorio).
# Desviación de ambiente aprobada (PM-002 TRANSITIONING): no usa ningún proyecto cloud.
# Nunca ejecuta comandos --linked, db push ni link. Registro en e7-t10-local.log (ignorado por git: *.log).
# Uso (PowerShell, raíz del repositorio):  powershell -ExecutionPolicy Bypass -File scripts\e7_t10_local.ps1
$ErrorActionPreference = 'Continue'
$root = Split-Path -Parent $PSScriptRoot
Set-Location $root
$log = Join-Path $root 'e7-t10-local.log'
Set-Content -Path $log -Value "E7-T10 local $(Get-Date -Format o)" -Encoding utf8

function Step([string]$label, [scriptblock]$block) {
  "== $label" | Tee-Object -Variable head | Out-Host
  $head | Out-File -FilePath $log -Append -Encoding utf8
  $out = & $block 2>&1 | ForEach-Object { "$_" }
  $code = $LASTEXITCODE
  $out | Out-Host
  $out | Out-File -FilePath $log -Append -Encoding utf8
  "-- exit $code" | Out-File -FilePath $log -Append -Encoding utf8
  return $code
}

Step 'git' { git rev-parse --short HEAD; git status --short } | Out-Null
Step 'docker' { docker version --format 'server {{.Server.Version}}' } | Out-Null
Step 'imagenes supabase previas' { docker images --format '{{.Repository}}:{{.Tag}}' | Select-String 'supabase' } | Out-Null
Step 'supabase cli' { npx supabase --version } | Out-Null

# Servicios estrictamente necesarios: db, auth (gotrue), rest (postgrest), realtime, kong (gateway).
$exclude = 'studio,imgproxy,mailpit,storage-api,edge-runtime,logflare,vector,supavisor,postgres-meta'
# Un stack previo (p. ej. de E1) arranca todos los servicios; se detiene para iniciar sólo los necesarios.
Step 'supabase stop (stack previo, conserva volumen)' { npx supabase stop } | Out-Null
$code = Step 'supabase start (servicios minimos)' { npx supabase start -x $exclude | Select-String -NotMatch 'sb_|eyJ|Publishable|Secret' }
if ($code -ne 0) {
  $exclude = 'studio,imgproxy,inbucket,storage-api,edge-runtime,logflare,vector,supavisor,postgres-meta'
  $code = Step 'supabase start (reintento con nombre inbucket)' { npx supabase start -x $exclude | Select-String -NotMatch 'sb_|eyJ|Publishable|Secret' }
}
if ($code -ne 0) { Step 'ABORTADO: supabase start fallo' { 'ver salida anterior' } | Out-Null; exit 1 }
Step 'imagenes supabase tras start' { docker images --format '{{.Repository}}:{{.Tag}} {{.CreatedSince}}' | Select-String 'supabase' } | Out-Null

# Reconstruccion limpia desde migraciones del repositorio + seed (sólo local).
$code = Step 'supabase db reset --local (57 migraciones + seed)' { npx supabase db reset --local }
if ($code -ne 0) { Step 'ABORTADO: db reset fallo' { 'ver salida anterior' } | Out-Null; exit 1 }

$db = 'supabase_db_mikuyapp-restaurant-ops'
$psql = @('exec', '-e', 'PGPASSWORD=postgres', $db, 'psql', '-h', '127.0.0.1', '-U', 'postgres', '-d', 'postgres', '-X', '-v', 'ON_ERROR_STOP=1')
Step 'servicios levantados' { docker ps --filter 'name=supabase_' --format '{{.Names}} {{.Image}} {{.Status}}' } | Out-Null
Step 'versiones' {
  docker @psql -At -c 'select version()' -c 'show server_version' -c 'select count(*) || '' migraciones, ultima '' || max(version) from supabase_migrations.schema_migrations'
} | Out-Null
Step 'publicacion realtime' { docker @psql -At -c "select string_agg(tablename, ',' order by tablename) from pg_publication_tables where pubname = 'supabase_realtime'" } | Out-Null
Step 'privilegios service_role (E7 vs E1)' {
  docker @psql -At -c @"
select 'tabla ' || t || ' service_role=' || has_table_privilege('service_role', 'public.' || t, 'SELECT,INSERT,UPDATE,DELETE,TRUNCATE') || ' authenticated=' || has_table_privilege('authenticated', 'public.' || t, 'SELECT,INSERT,UPDATE,DELETE,TRUNCATE') || ' anon=' || has_table_privilege('anon', 'public.' || t, 'SELECT,INSERT,UPDATE,DELETE,TRUNCATE')
from unnest(array['historial_detalle_pedido','comanda','descuento_pedido','anulacion_pedido']) t
union all
select 'funcion ' || p.oid::regprocedure || ' service_role=' || has_function_privilege('service_role', p.oid, 'EXECUTE') || ' authenticated=' || has_function_privilege('authenticated', p.oid, 'EXECUTE') || ' anon=' || has_function_privilege('anon', p.oid, 'EXECUTE')
from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname in ('rpc_obtener_tablero_cocina','rpc_recibir_pedido_cocina','rpc_cancelar_detalle_pedido','rpc_obtener_cancelaciones_pedido','rpc_modificar_detalle_pedido','rpc_retirar_detalle_pedido','rpc_registrar_impresion_comanda','tgf_detalle_pedido_historial_estado','tgf_historial_detalle_pedido_inmutable','tgf_comanda_contenido_inmutable')
order by 1;
"@
} | Out-Null

# Pruebas SQL dentro del contenedor (archivos copiados con docker cp para conservar UTF-8).
docker exec $db rm -rf /tmp/e7 | Out-Null
docker exec $db mkdir -p /tmp/e7/supabase /tmp/e7/scripts | Out-Null
docker cp "$root\supabase\tests" "${db}:/tmp/e7/supabase/tests" | Out-Null
docker cp "$root\scripts\e7_concurrency.sh" "${db}:/tmp/e7/scripts/e7_concurrency.sh" | Out-Null
foreach ($t in 'e7_t02_modelo', 'e7_t03_envio', 'e7_t04_recepcion_tablero', 'e7_t05_cancelacion', 'e7_t05b_edicion_retiro', 'e7_t09_impresion_comanda', 'e7_t10_integracion') {
  Step "sql $t" { docker @psql -q -f "/tmp/e7/supabase/tests/$t.sql" } | Out-Null
}
Step 'carreras R1-R15' {
  docker exec -e PGPASSWORD=postgres -e 'PSQL_CONN=-h 127.0.0.1 -U postgres -d postgres' $db bash /tmp/e7/scripts/e7_concurrency.sh all
} | Out-Null

# Recorrido vía Auth + PostgREST + Realtime reales con los servicios del frontend.
$status = npx supabase status -o env 2>$null
$vars = @{}
foreach ($line in $status) { if ($line -match '^([A-Z_]+)="?([^"]*)"?$') { $vars[$Matches[1]] = $Matches[2] } }
$env:E7_VALIDATION_LOCAL = '1'
$env:E7_VALIDATION_SUPABASE_URL = $vars['API_URL']
$env:E7_VALIDATION_PUBLISHABLE_KEY = $(if ($vars['ANON_KEY']) { $vars['ANON_KEY'] } else { $vars['PUBLISHABLE_KEY'] })
$env:E7_VALIDATION_SERVICE_ROLE_KEY = $(if ($vars['SERVICE_ROLE_KEY']) { $vars['SERVICE_ROLE_KEY'] } else { $vars['SECRET_KEY'] })
Step "api local $($vars['API_URL'])" { 'claves locales tomadas de supabase status (no se registran)' } | Out-Null
Step 'recorrido e7_t10_validation.mjs' { node --experimental-strip-types scripts/e7_t10_validation.mjs } | Out-Null
Remove-Item Env:E7_VALIDATION_SERVICE_ROLE_KEY, Env:E7_VALIDATION_PUBLISHABLE_KEY -ErrorAction SilentlyContinue

Step 'supabase stop' { npx supabase stop } | Out-Null
"== FIN" | Out-File -FilePath $log -Append -Encoding utf8
