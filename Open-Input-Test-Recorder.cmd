@echo off
setlocal
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\open-input-test-recorder.ps1" %*
exit /b %errorlevel%
