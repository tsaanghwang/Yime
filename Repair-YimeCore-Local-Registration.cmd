@echo off
setlocal
set "PSModulePath=%SystemRoot%\System32\WindowsPowerShell\v1.0\Modules"
echo YimeCore local.3 targeted registration repair ONLY.
echo Restore OneDrive autostart and two original frozen profile strings.
echo No input-method stop, installation, user-data restore or reboot.
echo Use normal File Explorer double-click. The script requests UAC itself.
echo.
"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\yimecore\repair-local3-registration.ps1" -Execute
set "YIME_LOCAL_REPAIR_EXIT=%ERRORLEVEL%"
echo.
echo Repair exit code: %YIME_LOCAL_REPAIR_EXIT%
echo Keep the PASS or error line and evidence directory.
if /I not "%~1"=="/nopause" pause
exit /b %YIME_LOCAL_REPAIR_EXIT%
