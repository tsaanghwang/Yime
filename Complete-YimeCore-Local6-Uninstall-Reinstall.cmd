@echo off
setlocal
set "PSModulePath=%SystemRoot%\System32\WindowsPowerShell\v1.0\Modules"
echo Complete the verified local.6 partial uninstall and reinstall the preserved pinned package.
echo This restores the frozen user TIP snapshot, requests UAC once, and does not reboot.
echo Run by normal File Explorer double-click, not as administrator.
echo.
"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\yimecore\complete-local6-uninstall-reinstall.ps1" -Execute
set "YIME_LOCAL6_COMPLETION_EXIT=%ERRORLEVEL%"
echo.
echo Completion exit code: %YIME_LOCAL6_COMPLETION_EXIT%
echo Keep the PASS or BLOCKED line and evidence directory.
if /I not "%~1"=="/nopause" pause
exit /b %YIME_LOCAL6_COMPLETION_EXIT%
