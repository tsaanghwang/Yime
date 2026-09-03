@echo off
setlocal
set "PSModulePath=%SystemRoot%\System32\WindowsPowerShell\v1.0\Modules"
echo Upgrade the repaired local.5 baseline to the reviewed local.6 package.
echo Use normal File Explorer double-click. Do not run as administrator.
echo This performs a fresh backup, requests UAC through the package, and does not reboot.
echo.
"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\yimecore\invoke-local6-native-upgrade.ps1" -Execute
set "YIME_LOCAL6_EXIT=%ERRORLEVEL%"
echo.
echo Acceptance exit code: %YIME_LOCAL6_EXIT%
echo Keep the PASS or BLOCKED line and evidence directory.
if /I not "%~1"=="/nopause" pause
exit /b %YIME_LOCAL6_EXIT%
