@echo off
REM E7-T11: ejecucion complementaria (linea base pre-E7 y repeticion del recorrido API/Realtime).
cd /d "%~dp0.."
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\e7_t11_followup.ps1
echo.
echo Terminado. Revise e7-t11-followup.log. Puede cerrar esta ventana.
pause
