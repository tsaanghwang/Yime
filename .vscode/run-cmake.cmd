@echo off
setlocal
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0..\tools\invoke-cmake.ps1" %*
exit /b %errorlevel%
