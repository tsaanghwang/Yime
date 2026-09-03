@echo off
setlocal
set "PSModulePath=%SystemRoot%\System32\WindowsPowerShell\v1.0\Modules"
echo Test the installed local.6 package's fresh backup and data-only restore.
echo Save and close Word and Notepad first. Use normal File Explorer double-click.
echo This stops and restarts the local Runtime/Broker, preserves the original model, and does not reboot.
echo.
"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\yimecore\invoke-local6-backup-restore.ps1" -Execute
set "YIME_LOCAL6_RESTORE_EXIT=%ERRORLEVEL%"
echo.
echo Acceptance exit code: %YIME_LOCAL6_RESTORE_EXIT%
echo Keep the PASS or BLOCKED line and evidence directory.
if /I not "%~1"=="/nopause" pause
exit /b %YIME_LOCAL6_RESTORE_EXIT%
