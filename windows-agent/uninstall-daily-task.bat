@echo off
schtasks /Delete /TN "RPST Daily ETL Agent" /F
echo.
echo Scheduled task removed if it existed.
pause
