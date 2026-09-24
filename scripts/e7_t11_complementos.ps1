# E7-T11 — Ejecuta supabase/tests/e7_t11_complementos.sql en el stack Supabase LOCAL (termina con ROLLBACK).
# Registro: e7-t11-complementos.log (ignorado por git). Nunca link/--linked/db push.
$ErrorActionPreference = 'Continue'
$root = Split-Path -Parent $PSScriptRoot
Set-Location $root
$log = Join-Path $root 'e7-t11-complementos.log'
Set-Content -Path $log -Value "E7-T11 complementos $(Get-Date -Format o)" -Encoding utf8
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
$exclude = 'studio,imgproxy,mailpit,storage-api,edge-runtime,logflare,vector,supavisor,postgres-meta'
Step 'git' { git rev-parse --short HEAD; git status --short } | Out-Null
Step 'supabase start (servicios minimos)' { npx supabase start -x $exclude } | Out-Null
$db = 'supabase_db_mikuyapp-restaurant-ops'
Step 'estado del volumen' { docker exec -e PGPASSWORD=postgres $db psql -h 127.0.0.1 -U postgres -d postgres -X -At -c "select count(*)||' migraciones; última '||max(version) from supabase_migrations.schema_migrations" } | Out-Null
docker exec $db rm -rf /tmp/e7t11 | Out-Null
docker exec $db mkdir -p /tmp/e7t11 | Out-Null
docker cp "$root\supabase\tests\e7_t11_complementos.sql" "${db}:/tmp/e7t11/e7_t11_complementos.sql" | Out-Null
Step 'sql e7_t11_complementos' { docker exec -e PGPASSWORD=postgres $db psql -h 127.0.0.1 -U postgres -d postgres -X -q -v ON_ERROR_STOP=1 -v VERBOSITY=verbose -f /tmp/e7t11/e7_t11_complementos.sql } | Out-Null
docker exec $db rm -rf /tmp/e7t11 | Out-Null
Step 'residuos (debe ser 0)' { docker exec -e PGPASSWORD=postgres $db psql -h 127.0.0.1 -U postgres -d postgres -X -At -c "select 'locales_t11='||count(*) from public.local where codigo like 'E7-T11%'" } | Out-Null
Step 'supabase stop' { npx supabase stop } | Out-Null
"== FIN" | Out-File -FilePath $log -Append -Encoding utf8
