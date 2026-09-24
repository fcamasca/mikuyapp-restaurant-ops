@echo off
REM E7-T10: ejecuta la validacion en el stack Supabase local (doble clic desde el Explorador).
cd /d "%~dp0.."
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\e7_t10_local.ps1
echo.
echo Validacion terminada. Revise e7-t10-local.log. Puede cerrar esta ventana.
pause
