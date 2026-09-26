@echo off
REM E7-T12 TH06: experimento local de remontaje de canal Realtime (stack Supabase local).
cd /d "%~dp0.."
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\e7_t12_th06.ps1 -Script scripts/e7_t12_th06_race_local.mjs
echo.
echo Terminado. Revise e7-t12-th06.log. Puede cerrar esta ventana.
pause
