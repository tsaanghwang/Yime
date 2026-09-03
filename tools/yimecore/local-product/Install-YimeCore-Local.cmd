@echo off
setlocal
rem Avoid inheriting incompatible PowerShell 7 module discovery into PS 5.1.
rem setlocal limits this to the child; user/system environment is unchanged.
set "PSModulePath=%SystemRoot%\System32\WindowsPowerShell\v1.0\Modules"
rem Native Explorer-launched console only. Never restarts Windows automatically.
"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -File "%~dp0maintenance\manage-local-product.ps1" -Action Install
set "YIME_LOCAL_INSTALL_EXIT=%ERRORLEVEL%"
echo.
if "%YIME_LOCAL_INSTALL_EXIT%"=="0" (
  echo PASS: YimeCore local product install or upgrade completed.
) else (
  echo BLOCKED: YimeCore local product install or upgrade failed.
)
echo Exit code: %YIME_LOCAL_INSTALL_EXIT%
if /I not "%~1"=="/nopause" pause
exit /b %YIME_LOCAL_INSTALL_EXIT%
