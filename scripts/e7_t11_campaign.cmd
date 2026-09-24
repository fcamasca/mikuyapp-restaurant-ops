@echo off
REM E7-T11: campaña técnica integral en el stack Supabase local (doble clic desde el Explorador).
cd /d "%~dp0.."
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\e7_t11_campaign.ps1
echo.
echo Campana E7-T11 terminada. Revise e7-t11-campaign.log. Puede cerrar esta ventana.
pause
