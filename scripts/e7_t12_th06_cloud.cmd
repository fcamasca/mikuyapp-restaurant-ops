@echo off
REM E7-T12 TH06: monitor Realtime de solo lectura contra el Supabase del Preview (DEV). Dura 15 minutos.
cd /d "%~dp0.."
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\e7_t12_th06_cloud.ps1
echo.
echo Terminado. Revise e7-t12-th06-cloud.log. Puede cerrar esta ventana.
pause
