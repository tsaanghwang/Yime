@echo off
setlocal
set "PSModulePath=%SystemRoot%\System32\WindowsPowerShell\v1.0\Modules"
echo Recover the reviewed local.7 uninstall state by installing the pinned local.8 fix.
echo Use normal File Explorer double-click. Do not run as administrator.
echo This preserves the existing recovery archive and user data. It does not reboot.
echo.
"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\yimecore\recover-local8-from-local7-uninstall.ps1" -Execute
set "YIME_LOCAL8_EXIT=%ERRORLEVEL%"
echo.
echo Acceptance exit code: %YIME_LOCAL8_EXIT%
echo Keep the PASS or BLOCKED line and evidence directory.
if /I not "%~1"=="/nopause" pause
exit /b %YIME_LOCAL8_EXIT%
