@echo off
setlocal
set "PSModulePath=%SystemRoot%\System32\WindowsPowerShell\v1.0\Modules"
echo Repair the completed local.5 identity migration only.
echo Restore the frozen legacy user TIP and verify the required shared TSF profile mirror.
echo No reinstall, user-data restore, default-input change, production PIME change, or reboot.
echo Use normal File Explorer double-click. The script requests one UAC confirmation.
echo.
"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\yimecore\repair-local5-identity-migration.ps1" -Execute
set "YIME_LOCAL_REPAIR_EXIT=%ERRORLEVEL%"
echo.
echo Repair exit code: %YIME_LOCAL_REPAIR_EXIT%
echo Keep the PASS or error line and evidence directory.
if /I not "%~1"=="/nopause" pause
exit /b %YIME_LOCAL_REPAIR_EXIT%
