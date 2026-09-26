@echo off
REM Double-click this. The -ExecutionPolicy Bypass applies to this one run only;
REM it changes nothing about your machine's settings.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0phone-connection-info.ps1"
echo.
pause
