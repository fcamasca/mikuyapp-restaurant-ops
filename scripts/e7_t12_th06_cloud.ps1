# E7-T12/TH06 — Monitor Realtime de sólo lectura contra el Supabase cloud del Preview (DEV). Registro: e7-t12-th06-cloud.log
$root = Split-Path -Parent $PSScriptRoot
Set-Location $root
node --env-file=.env.local --experimental-strip-types scripts/e7_t12_th06_cloud_monitor.mjs
