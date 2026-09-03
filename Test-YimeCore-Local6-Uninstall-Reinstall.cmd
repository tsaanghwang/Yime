@echo off
setlocal
set "PSModulePath=%SystemRoot%\System32\WindowsPowerShell\v1.0\Modules"
echo Uninstall local.6 while preserving user data, then reinstall the pinned complete package.
echo Close Word and input-method tools first. This requests UAC but does not reboot.
echo Run by normal File Explorer double-click, not as administrator.
echo.
"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\yimecore\invoke-local6-uninstall-reinstall.ps1" -Execute
set "YIME_LOCAL6_REINSTALL_EXIT=%ERRORLEVEL%"
echo.
echo Acceptance exit code: %YIME_LOCAL6_REINSTALL_EXIT%
echo Keep the PASS or BLOCKED line and evidence directory.
if /I not "%~1"=="/nopause" pause
exit /b %YIME_LOCAL6_REINSTALL_EXIT%
