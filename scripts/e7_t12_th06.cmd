@echo off
REM E7-T12 TH06: reproduccion/verificacion del defecto posterior al cobro total (stack Supabase local).
cd /d "%~dp0.."
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\e7_t12_th06.ps1
echo.
echo Terminado. Revise e7-t12-th06.log. Puede cerrar esta ventana.
pause
