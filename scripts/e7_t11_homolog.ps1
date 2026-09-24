# E7-T11 — Suite histórica homologada (pre-E7 vs E7) para clasificar fallos
# y repetición del recorrido API/Realtime. Stack Supabase LOCAL; nunca link/--linked/db push. Registro: e7-t11-homolog.log
$ErrorActionPreference = 'Continue'
$root = Split-Path -Parent $PSScriptRoot
Set-Location $root
$log = Join-Path $root 'e7-t11-homolog.log'
Set-Content -Path $log -Value "E7-T11 complementaria $(Get-Date -Format o)" -Encoding utf8
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
Step 'git' { git rev-parse --short HEAD; git status --short } | Out-Null
$exclude = 'studio,imgproxy,mailpit,storage-api,edge-runtime,logflare,vector,supavisor,postgres-meta'
Step 'supabase stop (previo)' { npx supabase stop } | Out-Null
$code = Step 'supabase start (servicios minimos)' { npx supabase start -x $exclude }
if ($code -ne 0) { exit 1 }
Step 'servicios' { docker ps --filter 'name=supabase_' --format '{{.Names}} {{.Image}} {{.Status}}' } | Out-Null
$db = 'supabase_db_mikuyapp-restaurant-ops'
Step 'estado del volumen (debe ser 57 migraciones, sin fixtures)' { docker exec -e PGPASSWORD=postgres $db psql -h 127.0.0.1 -U postgres -d postgres -X -At -c "select count(*)||' migraciones; última '||max(version) from supabase_migrations.schema_migrations" -c "select 'locales_validacion='||count(*) from public.local where codigo like 'E7-VAL-%'" } | Out-Null

# Línea base pre-E7 de la suite SQL (misma campaña, replay hasta 20260922000100)
docker exec $db rm -rf /tmp/e7 | Out-Null
docker exec $db mkdir -p /tmp/e7/supabase /tmp/e7/scripts | Out-Null
foreach ($d in 'migrations', 'tests', 'rollbacks') { if (Test-Path "$root\supabase\$d") { docker cp "$root\supabase\$d" "${db}:/tmp/e7/supabase/$d" | Out-Null } }
docker cp "$root\supabase\seed.sql" "${db}:/tmp/e7/supabase/seed.sql" | Out-Null
docker cp "$root\scripts\e7_t11_sql_campaign.sh" "${db}:/tmp/e7/scripts/e7_t11_sql_campaign.sh" | Out-Null
Step 'FASE homolog pre (baseline pre-E7)' { docker exec $db bash /tmp/e7/scripts/e7_t11_sql_campaign.sh homolog pre } | Out-Null
Step 'FASE homolog e7 (esquema completo)' { docker exec $db bash /tmp/e7/scripts/e7_t11_sql_campaign.sh homolog e7 } | Out-Null
docker exec $db rm -rf /tmp/e7 | Out-Null

Step 'residuos' { docker exec -e PGPASSWORD=postgres $db psql -h 127.0.0.1 -U postgres -d postgres -X -At -c "select 'locales_validacion='||count(*) from public.local where codigo like 'E7-VAL-%'" -c "select 'bases_efimeras='||count(*) from pg_database where datname like 'e7_t11%' or datname like 'e1_t%'" } | Out-Null
Step 'supabase stop' { npx supabase stop } | Out-Null
Step 'contenedores supabase tras stop' { docker ps --filter 'name=supabase_' --format '{{.Names}}'; 'fin listado' } | Out-Null
"== FIN" | Out-File -FilePath $log -Append -Encoding utf8
