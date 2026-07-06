@echo off
setlocal
cd /d "%~dp0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File ".\scripts\RpstEtlAgent.ps1" -ConfigPath ".\config.json"
if errorlevel 1 (
  echo.
  echo Send failed. See logs folder for details.
  pause
  exit /b 1
)
echo.
echo Send completed.
pause
