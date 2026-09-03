@echo off
setlocal
set "PSModulePath=%SystemRoot%\System32\WindowsPowerShell\v1.0\Modules"
echo Complete read-only verification of the existing failed-upgrade rollback evidence.
echo This does not repeat the failure, install, restore data, request UAC, or reboot.
echo Use normal File Explorer double-click.
echo.
"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\yimecore\complete-local6-failed-upgrade.ps1" -Execute
set "YIME_LOCAL6_COMPLETE_EXIT=%ERRORLEVEL%"
echo.
echo Acceptance exit code: %YIME_LOCAL6_COMPLETE_EXIT%
echo Keep the PASS or error line and evidence directory.
if /I not "%~1"=="/nopause" pause
exit /b %YIME_LOCAL6_COMPLETE_EXIT%
