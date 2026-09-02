@echo off
setlocal
rem Start by normal double-click in native File Explorer, not from an admin console.
rem This wrapper never elevates or changes compatibility/security settings.
set "PSModulePath=%SystemRoot%\System32\WindowsPowerShell\v1.0\Modules"
echo YimeCore standard-user launch verification ONLY.
echo No input-method stop, backup, installation or reboot.
echo Use normal double-click; do not choose Run as administrator.
echo The verified PowerShell probe will request UAC when needed.
echo.
"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\yimecore\test-native-standard-user-launch.ps1"
set "YIME_STANDARD_PROBE_EXIT=%ERRORLEVEL%"
echo.
echo Probe exit code: %YIME_STANDARD_PROBE_EXIT%
echo Please keep the PASS or BLOCKED line and evidence directory.
if /I not "%~1"=="/nopause" pause
exit /b %YIME_STANDARD_PROBE_EXIT%
