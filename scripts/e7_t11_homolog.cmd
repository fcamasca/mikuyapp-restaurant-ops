@echo off
REM E7-T11: suite historica homologada pre-E7 vs E7.
cd /d "%~dp0.."
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\e7_t11_homolog.ps1
echo.
echo Terminado. Revise e7-t11-homolog.log. Puede cerrar esta ventana.
pause
