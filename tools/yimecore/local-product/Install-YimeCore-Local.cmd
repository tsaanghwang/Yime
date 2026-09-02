@echo off
setlocal
rem Avoid inheriting incompatible PowerShell 7 module discovery into PS 5.1.
rem setlocal limits this to the child; user/system environment is unchanged.
set "PSModulePath=%SystemRoot%\System32\WindowsPowerShell\v1.0\Modules"
rem Native Explorer-launched console only. Never restarts Windows automatically.
"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -File "%~dp0maintenance\manage-local-product.ps1" -Action Install
exit /b %errorlevel%
