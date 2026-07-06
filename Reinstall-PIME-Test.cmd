@echo off
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
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0dev-stop-pime.ps1"
set "EXIT_CODE=%errorlevel%"

if "%EXIT_CODE%"=="2" goto dll_locked
if not "%EXIT_CODE%"=="0" goto preflight_failed
goto after_preflight

:dll_locked
echo.
echo PIMETextService.dll is still loaded - often explorer.exe.
echo Skipping full uninstall and doing an in-place install instead.
echo For a completely clean reinstall, reboot first, then run this script again.
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
echo YIME test uninstall failed with exit code %EXIT_CODE%.
echo.
echo If files are locked, reboot Windows, then run this script again before
echo switching back to Yime. You can also retry now for an in-place install:
set /p "RETRY=Try in-place install without uninstall? [Y/N] "
if /I "%RETRY%"=="Y" goto install
pause
exit /b %EXIT_CODE%

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
pause
exit /b 0
