@echo off
setlocal
cd /d "%~dp0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File ".\scripts\RpstEtlAgent.ps1" -ConfigPath ".\config.json"
exit /b %errorlevel%
