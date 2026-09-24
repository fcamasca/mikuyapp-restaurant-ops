# E7-T11 — Campaña técnica integral (una sola ejecución) sobre el stack Supabase LOCAL real.
# Nunca usa link, --linked ni db push; no toca proyectos cloud. Registro: e7-t11-campaign.log (ignorado por git).
# Uso: doble clic en scripts\e7_t11_campaign.cmd, o PowerShell desde la raíz:
#   powershell -ExecutionPolicy Bypass -File scripts\e7_t11_campaign.ps1
$ErrorActionPreference = 'Continue'
$root = Split-Path -Parent $PSScriptRoot
Set-Location $root
$log = Join-Path $root 'e7-t11-campaign.log'
Set-Content -Path $log -Value "E7-T11 campaña $(Get-Date -Format o)" -Encoding utf8

function Step([string]$label, [scriptblock]$block) {
  "== $label" | Tee-Object -Variable head | Out-Host
  $head | Out-File -FilePath $log -Append -Encoding utf8
  $out = & $block 2>&1 | ForEach-Object { "$_" } | Select-String -NotMatch 'sb_publishable_|sb_secret_|eyJhbGci'
  $code = $LASTEXITCODE
  $out | Out-Host
  $out | Out-File -FilePath $log -Append -Encoding utf8
  "-- exit $code" | Out-File -FilePath $log -Append -Encoding utf8
  return $code
}

# 1. Repositorio y versiones
Step 'git' { git rev-parse --abbrev-ref HEAD; git rev-parse --short HEAD; git status --short } | Out-Null
Step 'git diff --check (árbol de trabajo)' { git diff --check } | Out-Null
Step 'git diff --check (E7 desde main)' { git diff --check main...HEAD } | Out-Null
Step 'versiones herramientas' { "node $(node -v)"; "npm $(npm -v)"; docker version --format 'docker server {{.Server.Version}}'; "supabase cli $(npx supabase --version)" } | Out-Null

# 2. Frontend
Step 'npm run typecheck' { npm run typecheck } | Out-Null
Step 'npm run build' { npm run build } | Out-Null
$tests = (Get-ChildItem tests -Filter '*.test.mjs' | Sort-Object Name | ForEach-Object { "tests/$($_.Name)" })
Step "suite Node completa ($($tests.Count) archivos)" { node --experimental-strip-types --test --test-reporter=spec @tests } | Out-Null

# 3. Stack local mínimo y replay limpio
$exclude = 'studio,imgproxy,mailpit,storage-api,edge-runtime,logflare,vector,supavisor,postgres-meta'
Step 'imagenes supabase previas' { docker images --format '{{.Repository}}:{{.Tag}}' | Select-String 'supabase' } | Out-Null
Step 'supabase stop (stack previo, conserva volumen)' { npx supabase stop } | Out-Null
$code = Step 'supabase start (servicios minimos)' { npx supabase start -x $exclude }
if ($code -ne 0) { Step 'ABORTADO: supabase start fallo' { 'ver salida anterior' } | Out-Null; exit 1 }
$code = Step 'REPLAY 1: supabase db reset --local (migraciones + seed)' { npx supabase db reset --local }
if ($code -ne 0) { Step 'ABORTADO: db reset fallo' { 'ver salida anterior' } | Out-Null; npx supabase stop | Out-Null; exit 1 }
Step 'imagenes supabase tras start' { docker images --format '{{.Repository}}:{{.Tag}}' | Select-String 'supabase' } | Out-Null
Step 'servicios levantados' { docker ps --filter 'name=supabase_' --format '{{.Names}} {{.Image}} {{.Status}}' } | Out-Null

$db = 'supabase_db_mikuyapp-restaurant-ops'
docker exec $db rm -rf /tmp/e7 | Out-Null
docker exec $db mkdir -p /tmp/e7/supabase /tmp/e7/scripts | Out-Null
foreach ($d in 'migrations', 'tests', 'rollbacks') { if (Test-Path "$root\supabase\$d") { docker cp "$root\supabase\$d" "${db}:/tmp/e7/supabase/$d" | Out-Null } }
docker cp "$root\supabase\seed.sql" "${db}:/tmp/e7/supabase/seed.sql" | Out-Null
docker cp "$root\scripts\e7_concurrency.sh" "${db}:/tmp/e7/scripts/e7_concurrency.sh" | Out-Null
docker cp "$root\scripts\e7_t11_sql_campaign.sh" "${db}:/tmp/e7/scripts/e7_t11_sql_campaign.sh" | Out-Null

# 4. Base real del stack: SQL E7, integración, privilegios con roles reales, catálogo de seguridad, 40001
Step 'FASE real (postgres del stack)' { docker exec $db bash /tmp/e7/scripts/e7_t11_sql_campaign.sh real } | Out-Null
Step 'carreras E7 R1-R15 (postgres del stack)' {
  docker exec -e PGPASSWORD=postgres -e 'PSQL_CONN=-h 127.0.0.1 -U postgres -d postgres' $db bash /tmp/e7/scripts/e7_concurrency.sh all
} | Out-Null

# 5. Base aislada con replay completo: suite SQL del repositorio, E1 con fixtures, carreras H4/H5 y E1-T09
Step 'FASE aislada (REPLAY 2 + suite SQL completa + carreras históricas)' { docker exec $db bash /tmp/e7/scripts/e7_t11_sql_campaign.sh aislada } | Out-Null
$iso = (docker exec $db cat /tmp/e7/t11_db 2>$null)
if ($iso) {
  Step "carreras E1-T09 (testE1T09Concurrency.mjs sobre $iso)" { node scripts/testE1T09Concurrency.mjs $db $iso } | Out-Null
}
Step 'FASE baseline pre-E7 (reproducción HZ-01)' { docker exec $db bash /tmp/e7/scripts/e7_t11_sql_campaign.sh baseline } | Out-Null
Step 'FASE dbstd (prueba compensatoria histórica DBSTD-T09)' { docker exec $db bash /tmp/e7/scripts/e7_t11_sql_campaign.sh dbstd } | Out-Null

# 6. Recorrido vía Auth + PostgREST + Realtime reales (dos mozos, dos cocinas)
$status = npx supabase status -o env 2>$null
$vars = @{}
foreach ($line in $status) { if ($line -match '^([A-Z_]+)="?([^"]*)"?$') { $vars[$Matches[1]] = $Matches[2] } }
$env:E7_VALIDATION_LOCAL = '1'
$env:E7_VALIDATION_SUPABASE_URL = $vars['API_URL']
$env:E7_VALIDATION_PUBLISHABLE_KEY = $(if ($vars['ANON_KEY']) { $vars['ANON_KEY'] } else { $vars['PUBLISHABLE_KEY'] })
$env:E7_VALIDATION_SERVICE_ROLE_KEY = $(if ($vars['SERVICE_ROLE_KEY']) { $vars['SERVICE_ROLE_KEY'] } else { $vars['SECRET_KEY'] })
Step "recorrido API/Realtime e7_t10_validation.mjs ($($vars['API_URL']))" { node --experimental-strip-types scripts/e7_t10_validation.mjs } | Out-Null
Remove-Item Env:E7_VALIDATION_SERVICE_ROLE_KEY, Env:E7_VALIDATION_PUBLISHABLE_KEY, Env:E7_VALIDATION_SUPABASE_URL, Env:E7_VALIDATION_LOCAL -ErrorAction SilentlyContinue

# 7. Residuos: base aislada, conexiones y fixtures; replay final para dejar el volumen local limpio
if ($iso) { Step 'eliminar base aislada y conexiones residuales' { docker exec $db bash /tmp/e7/scripts/e7_t11_sql_campaign.sh drop $iso } | Out-Null }
docker exec $db rm -rf /tmp/e7 | Out-Null
Step 'REPLAY 3: db reset final (elimina fixtures del recorrido API)' { npx supabase db reset --local } | Out-Null
Step 'residuos tras reset' {
  docker exec -e PGPASSWORD=postgres $db psql -h 127.0.0.1 -U postgres -d postgres -X -At -c "select 'locales_validacion='||count(*) from public.local where codigo like 'E7-VAL-%'" -c "select 'usuarios_validacion='||count(*) from auth.users where email like 'e7-val-%'" -c "select 'bases_efimeras='||count(*) from pg_database where datname like 'e7_t11%' or datname like 'e1_t%'" -c "select 'conexiones_por_aplicacion '||coalesce(nullif(application_name,''),'(sin nombre)')||'='||count(*) from pg_stat_activity where backend_type='client backend' and pid<>pg_backend_pid() group by application_name order by 1"
} | Out-Null

# 8. Secretos y archivos temporales
Step 'secretos en archivos versionados' { git grep -n -I -E 'sb_secret_[A-Za-z0-9_-]{10,}|eyJhbGciOi[A-Za-z0-9_-]{20,}|service_role_key\s*=\s*\S{20,}|SUPABASE_SERVICE_ROLE_KEY=\S+' -- . ':!package-lock.json'; 'fin busqueda' } | Out-Null
Step 'archivos no versionados (incluye ignorados relevantes)' { git status --short --ignored -- . ':!node_modules' ':!dist' } | Out-Null

# 9. Apagar stack
Step 'supabase stop' { npx supabase stop } | Out-Null
Step 'contenedores supabase tras stop' { docker ps --filter 'name=supabase_' --format '{{.Names}}'; 'fin listado' } | Out-Null
Step 'git status final' { git status --short } | Out-Null
"== FIN" | Out-File -FilePath $log -Append -Encoding utf8
