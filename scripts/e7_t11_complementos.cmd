@echo off
REM E7-T11: escenarios complementarios SQL en el stack Supabase local.
cd /d "%~dp0.."
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\e7_t11_complementos.ps1
echo.
echo Terminado. Revise e7-t11-complementos.log. Puede cerrar esta ventana.
pause
