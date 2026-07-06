@echo off
setlocal
cd /d "%~dp0"
if not exist "%~dp0config.json" (
  echo config.json not found.
  echo Copy config.sample.json to config.json and edit it first.
  pause
  exit /b 1
)
schtasks /Create /TN "RPST Daily ETL Agent" /SC DAILY /ST 00:15 /TR "\"%~dp0run-silent.bat\"" /F
if errorlevel 1 (
  echo.
  echo Cannot create scheduled task. Run this file as Administrator.
  pause
  exit /b 1
)
echo.
echo Scheduled task installed: RPST Daily ETL Agent at 00:15 every day.
pause
