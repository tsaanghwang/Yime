@echo off
setlocal
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0maintenance\Manage-YimeCoreTrial.ps1" -Action Uninstall -Force
set "YIME_EXIT=%ERRORLEVEL%"
if not "%YIME_EXIT%"=="0" pause
exit /b %YIME_EXIT%
