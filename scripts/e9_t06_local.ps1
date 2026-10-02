# E9 — Verificación en el stack Supabase LOCAL real (Docker + Supabase CLI del repositorio), patrón E7-T10.
# Cubre lo que el entorno de construcción no puede: TP22 con clientes Realtime programáticos contra un servidor
# Realtime real, las pruebas SQL de E9 sobre la imagen PostgreSQL de Supabase, y `npm run build` (binarios
# nativos win32 de rolldown/lightningcss). Sin proyectos cloud: nunca --linked, db push ni link (DC-12).
# ATENCIÓN: `supabase db reset --local` reconstruye la base LOCAL de Docker desde las migraciones del repositorio.
# Registro en e9-t06-local.log (ignorado por git: *.log). Uso (PowerShell, raíz del repositorio):
#   powershell -ExecutionPolicy Bypass -File scripts\e9_t06_local.ps1
$ErrorActionPreference = 'Continue'
$root = Split-Path -Parent $PSScriptRoot
Set-Location $root
$validationFailures = @()
$log = Join-Path $root 'e9-t06-local.log'
Set-Content -Path $log -Value "E9 local $(Get-Date -Format o)" -Encoding utf8

function Step([string]$label, [scriptblock]$block) {
  "== $label" | Tee-Object -Variable head | Out-Host
  $head | Out-File -FilePath $log -Append -Encoding utf8
  $out = & $block 2>&1 | ForEach-Object { "$_" }
  $code = $LASTEXITCODE
  if ($code -ne 0 -and $label -match '^(sql |TP22 |npm run |versiones |publicacion )') {
    $script:validationFailures += $label
  }
  $out | Out-Host
  $out | Out-File -FilePath $log -Append -Encoding utf8
  "-- exit $code" | Out-File -FilePath $log -Append -Encoding utf8
  return $code
}

Step 'git' { git rev-parse --short HEAD; git branch --show-current; git status --short } | Out-Null
Step 'docker' { docker version --format 'server {{.Server.Version}}' } | Out-Null
Step 'supabase cli' { npx supabase --version } | Out-Null

# Servicios estrictamente necesarios: db, auth (gotrue), rest (postgrest), realtime, kong (gateway).
$exclude = 'studio,imgproxy,mailpit,storage-api,edge-runtime,logflare,vector,supavisor,postgres-meta'
Step 'supabase stop (stack previo, conserva volumen)' { npx supabase stop } | Out-Null
$code = Step 'supabase start (servicios minimos)' { npx supabase start -x $exclude | Select-String -NotMatch 'sb_|eyJ|Publishable|Secret' }
if ($code -ne 0) {
  $exclude = 'studio,imgproxy,inbucket,storage-api,edge-runtime,logflare,vector,supavisor,postgres-meta'
  $code = Step 'supabase start (reintento con nombre inbucket)' { npx supabase start -x $exclude | Select-String -NotMatch 'sb_|eyJ|Publishable|Secret' }
}
if ($code -ne 0) { Step 'ABORTADO: supabase start fallo' { 'ver salida anterior' } | Out-Null; exit 1 }

$code = Step 'supabase db reset --local (61 migraciones + seed)' { npx supabase db reset --local }
if ($code -ne 0) { Step 'ABORTADO: db reset fallo' { 'ver salida anterior' } | Out-Null; exit 1 }

$db = 'supabase_db_mikuyapp-restaurant-ops'
$psql = @('exec', '-e', 'PGPASSWORD=postgres', $db, 'psql', '-h', '127.0.0.1', '-U', 'postgres', '-d', 'postgres', '-X', '-v', 'ON_ERROR_STOP=1')
Step 'servicios levantados' { docker ps --filter 'name=supabase_' --format '{{.Names}} {{.Image}} {{.Status}}' } | Out-Null
Step 'versiones y migraciones' {
  docker @psql -At -c 'show server_version' -c "select count(*) || ' migraciones, ultima ' || max(version) from supabase_migrations.schema_migrations"
} | Out-Null
Step 'publicacion realtime' { docker @psql -At -c "select string_agg(tablename, ',' order by tablename) from pg_publication_tables where pubname = 'supabase_realtime'" } | Out-Null

# Pruebas SQL de E9 dentro del contenedor (copiadas con docker cp para conservar UTF-8).
docker exec $db rm -rf /tmp/e9 | Out-Null
docker exec $db mkdir -p /tmp/e9 | Out-Null
docker cp "$root\supabase\tests" "${db}:/tmp/e9/tests" | Out-Null
foreach ($t in 'e9_t02_modelo', 'e9_t03_rpc', 'e9_t06_integracion', 'e9_t07_matriz_local_cerrado') {
  Step "sql $t" { docker @psql -q -f "/tmp/e9/tests/$t.sql" } | Out-Null
}

# TP22: clientes Realtime reales (Auth + PostgREST + Realtime) con los servicios del frontend.
$status = npx supabase status -o env 2>$null
$vars = @{}
foreach ($line in $status) { if ($line -match '^([A-Z_]+)="?([^"]*)"?$') { $vars[$Matches[1]] = $Matches[2] } }
$env:E9_VALIDATION_SUPABASE_URL = $vars['API_URL']
$env:E9_VALIDATION_PUBLISHABLE_KEY = $(if ($vars['ANON_KEY']) { $vars['ANON_KEY'] } else { $vars['PUBLISHABLE_KEY'] })
$env:E9_VALIDATION_SERVICE_ROLE_KEY = $(if ($vars['SERVICE_ROLE_KEY']) { $vars['SERVICE_ROLE_KEY'] } else { $vars['SECRET_KEY'] })
Step "api local $($vars['API_URL'])" { 'claves locales tomadas de supabase status (no se registran)' } | Out-Null
Step 'TP22 e9_realtime_verificacion.mjs' { node --experimental-strip-types scripts/e9_realtime_verificacion.mjs } | Out-Null
Remove-Item Env:E9_VALIDATION_SERVICE_ROLE_KEY, Env:E9_VALIDATION_PUBLISHABLE_KEY, Env:E9_VALIDATION_SUPABASE_URL -ErrorAction SilentlyContinue

Step 'supabase stop' { npx supabase stop } | Out-Null

Step 'npm run typecheck' { npm run typecheck } | Out-Null
Step 'npm run build' { npm run build } | Out-Null
"== FIN: $($validationFailures.Count) verificaciones fallidas" | Tee-Object -FilePath $log -Append | Out-Host
if ($validationFailures.Count -gt 0) { exit 1 }
exit 0
