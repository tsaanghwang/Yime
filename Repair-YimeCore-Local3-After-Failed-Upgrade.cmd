@echo off
setlocal
set "PSModulePath=%SystemRoot%\System32\WindowsPowerShell\v1.0\Modules"
echo Recover the verified local.3 installation after the failed local.4 cutover.
echo The script restores only the pinned x64 COM, local.3 Run/uninstall metadata,
echo the trial language-list entry, runtime configuration and standard-user runtime.
echo Production PIME/Rime, the frozen x86 registration and the default IME are protected.
echo.
"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\yimecore\recover-local3-after-failed-upgrade.ps1" -Execute
set "YIME_RECOVERY_EXIT=%ERRORLEVEL%"
echo.
echo Recovery exit code: %YIME_RECOVERY_EXIT%
if /I not "%~1"=="/nopause" pause
exit /b %YIME_RECOVERY_EXIT%
