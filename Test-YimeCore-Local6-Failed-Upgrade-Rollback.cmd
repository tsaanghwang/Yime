@echo off
setlocal
set "PSModulePath=%SystemRoot%\System32\WindowsPowerShell\v1.0\Modules"
echo Trigger the reviewed failure-only local.6 upgrade and verify automatic rollback.
echo Save and close Word and Notepad first. Use normal File Explorer double-click.
echo The failure is expected; PASS means the current package, data, registry, and ordinary runtime were restored.
echo.
"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\yimecore\invoke-local6-failed-upgrade-rollback.ps1" -Execute
set "YIME_LOCAL6_ROLLBACK_EXIT=%ERRORLEVEL%"
echo.
echo Acceptance exit code: %YIME_LOCAL6_ROLLBACK_EXIT%
echo Keep the PASS or BLOCKED line and evidence directory.
if /I not "%~1"=="/nopause" pause
exit /b %YIME_LOCAL6_ROLLBACK_EXIT%
