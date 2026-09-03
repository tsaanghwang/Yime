@echo off
setlocal
set "PSModulePath=%SystemRoot%\System32\WindowsPowerShell\v1.0\Modules"
echo Uninstall and reinstall the reviewed local.7 package while preserving user data.
echo Use normal File Explorer double-click. Do not run as administrator.
echo Close Word and all YimeCore tools first. This does not reboot.
echo.
"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\yimecore\invoke-local7-uninstall-reinstall.ps1" -Execute
set "YIME_LOCAL7_EXIT=%ERRORLEVEL%"
echo.
echo Acceptance exit code: %YIME_LOCAL7_EXIT%
echo Keep the PASS or BLOCKED line and evidence directory.
if /I not "%~1"=="/nopause" pause
exit /b %YIME_LOCAL7_EXIT%
