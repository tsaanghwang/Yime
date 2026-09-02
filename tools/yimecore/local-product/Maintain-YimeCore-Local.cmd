@echo off
setlocal
rem Use only the native Windows PowerShell modules, even when called from PS7.
set "PSModulePath=%SystemRoot%\System32\WindowsPowerShell\v1.0\Modules"
rem Default action is read-only Plan. Pass -Action Backup/Restore/Verify/Upgrade/Uninstall.
"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -File "%~dp0maintenance\manage-local-product.ps1" %*
exit /b %errorlevel%
