# E7-T12 / TH06 — Reproducción/verificación del defecto posterior al cobro total en el stack Supabase LOCAL.
# Uso: doble clic en scripts\e7_t12_th06.cmd. Registro: e7-t12-th06.log (ignorado por git). Nunca link/--linked/db push.
param([string]$Script = 'scripts/e7_t12_th06_repro.mjs')
$ErrorActionPreference = 'Continue'
$root = Split-Path -Parent $PSScriptRoot
Set-Location $root
$log = Join-Path $root 'e7-t12-th06.log'
Set-Content -Path $log -Value "E7-T12 TH06 $(Get-Date -Format o)" -Encoding utf8
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
$code = Step 'supabase start (servicios minimos)' { npx supabase start -x $exclude }
if ($code -ne 0) { exit 1 }
$status = npx supabase status -o env 2>$null
$vars = @{}
foreach ($line in $status) { if ($line -match '^([A-Z_]+)="?([^"]*)"?$') { $vars[$Matches[1]] = $Matches[2] } }
$env:E7_VALIDATION_SUPABASE_URL = $vars['API_URL']
$env:E7_VALIDATION_PUBLISHABLE_KEY = $(if ($vars['ANON_KEY']) { $vars['ANON_KEY'] } else { $vars['PUBLISHABLE_KEY'] })
$env:E7_VALIDATION_SERVICE_ROLE_KEY = $(if ($vars['SERVICE_ROLE_KEY']) { $vars['SERVICE_ROLE_KEY'] } else { $vars['SECRET_KEY'] })
Start-Sleep -Seconds 15
Step "TH06 $Script" { node --experimental-strip-types $Script } | Out-Null
Remove-Item Env:E7_VALIDATION_SERVICE_ROLE_KEY, Env:E7_VALIDATION_PUBLISHABLE_KEY, Env:E7_VALIDATION_SUPABASE_URL -ErrorAction SilentlyContinue
Step 'db reset (limpia la fixture)' { npx supabase db reset --local } | Out-Null
Step 'supabase stop' { npx supabase stop } | Out-Null
"== FIN" | Out-File -FilePath $log -Append -Encoding utf8
