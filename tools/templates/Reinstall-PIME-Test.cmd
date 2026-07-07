@echo off
rem CANONICAL SOURCE for Reinstall-PIME-Test.cmd (do not simplify).
rem Copied to repo root by tools/refresh-dev-test-cmds.ps1 after each build.
setlocal EnableExtensions

net session >nul 2>&1
if not "%errorlevel%"=="0" (
    powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
    exit /b
)

cd /d "%~dp0"
set "SKIP_UNINSTALL=0"

echo.
echo === Pre-flight: switch input method and stop PIME ===
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0dev-stop-pime.ps1" -Auto
set "EXIT_CODE=%errorlevel%"

if "%EXIT_CODE%"=="2" goto dll_locked
if not "%EXIT_CODE%"=="0" goto preflight_failed
goto after_preflight

:dll_locked
echo.
echo PIMETextService.dll is still loaded - continuing with in-place install.
echo go-backend and other unlocked files will still update.
echo Reboot first only if you need a completely clean DLL replacement.
echo.
set "SKIP_UNINSTALL=1"
goto after_preflight

:preflight_failed
echo.
echo Pre-flight failed with exit code %EXIT_CODE%.
pause
exit /b %EXIT_CODE%

:after_preflight
if not "%SKIP_UNINSTALL%"=="0" goto install

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0dev-uninstall.ps1"
set "EXIT_CODE=%errorlevel%"
if "%EXIT_CODE%"=="0" goto install

echo.
echo Uninstall reported exit code %EXIT_CODE%; continuing with in-place install...
goto install

:install
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0dev-install.ps1"
set "EXIT_CODE=%errorlevel%"

echo.
if "%EXIT_CODE%"=="0" goto install_ok
echo YIME test install failed with exit code %EXIT_CODE%.
pause
exit /b %EXIT_CODE%

:install_ok
echo YIME test reinstall completed.
echo Switch away from Yime, then switch back to refresh the language bar.
exit /b 0
