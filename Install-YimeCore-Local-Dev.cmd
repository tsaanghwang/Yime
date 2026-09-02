@echo off
setlocal
rem Native File Explorer normal double-click only. The PowerShell flow owns UAC.
set "PSModulePath=%SystemRoot%\System32\WindowsPowerShell\v1.0\Modules"
echo YimeCore local x64 candidate installation acceptance.
echo Close Word and input-method settings/tools first.
echo Use normal double-click; do not choose Run as administrator.
echo This backs up user data, installs the pinned candidate and verifies it.
echo Two same-account UAC prompts: read-only launch check, then installation.
echo Keep this window open until PASS or BLOCKED. No automatic reboot.
echo.
"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\yimecore\invoke-local-product-native-install.ps1" -Execute
set "YIME_LOCAL_INSTALL_EXIT=%ERRORLEVEL%"
echo.
echo Acceptance exit code: %YIME_LOCAL_INSTALL_EXIT%
echo Please keep the PASS or BLOCKED line and evidence directory.
if /I not "%~1"=="/nopause" pause
exit /b %YIME_LOCAL_INSTALL_EXIT%
