@echo off
setlocal
set "PSModulePath=%SystemRoot%\System32\WindowsPowerShell\v1.0\Modules"
echo Repair the installed local.6 taskbar entry for the current user.
echo Run by normal File Explorer double-click, not as administrator.
echo This changes only the active YimeCore user TIP Enable value from 0 to 1.
echo It does not change the language-list order, default input method, or production Yime.
echo.
"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\yimecore\repair-local6-active-user-tip.ps1" -Execute
set "YIME_LOCAL6_TASKBAR_EXIT=%ERRORLEVEL%"
echo.
echo Repair exit code: %YIME_LOCAL6_TASKBAR_EXIT%
echo Keep the PASS or BLOCKED line and evidence directory.
if /I not "%~1"=="/nopause" pause
exit /b %YIME_LOCAL6_TASKBAR_EXIT%
