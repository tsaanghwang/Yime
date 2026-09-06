@echo off
rem CANONICAL SOURCE for Reinstall-PIME-Test.cmd (do not simplify).
rem Copied to repo root by tools/refresh-dev-test-cmds.ps1 after each build.
setlocal EnableExtensions EnableDelayedExpansion
set "TARGET_USER_SID="
set "TARGET_USER_ARGUMENT=%~1"
if defined TARGET_USER_ARGUMENT if /I not "%TARGET_USER_ARGUMENT:~0,15%"=="/TargetUserSid=" goto invalid_target_sid
if defined TARGET_USER_ARGUMENT set "TARGET_USER_SID=%TARGET_USER_ARGUMENT:~15%"
if defined TARGET_USER_ARGUMENT if not defined TARGET_USER_SID goto invalid_target_sid

net session >nul 2>&1
if not "%errorlevel%"=="0" (
    for /f "usebackq delims=" %%S in (`powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "%~dp0tools\dual-product\invoke-rime-pime-target-user.ps1" -Action CaptureInitiator`) do set "CAPTURED_USER_SID=%%S"
    if not defined CAPTURED_USER_SID goto target_sid_failed
    if defined TARGET_USER_SID if /I not "!TARGET_USER_SID!"=="!CAPTURED_USER_SID!" goto invalid_target_sid
    set "TARGET_USER_SID=!CAPTURED_USER_SID!"
    powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -Command "$p=Start-Process -FilePath '%~f0' -Verb RunAs -ArgumentList '/TargetUserSid=!TARGET_USER_SID!' -PassThru; $p.WaitForExit(); exit $p.ExitCode"
    exit /b !errorlevel!
)
if not defined TARGET_USER_SID goto target_sid_failed

cd /d "%~dp0"
set "SKIP_UNINSTALL=0"

echo.
echo === Pre-flight: switch input method and stop PIME ===
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0dev-stop-pime.ps1" -TargetUserSid "%TARGET_USER_SID%" -Auto
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

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0dev-uninstall.ps1" -TargetUserSid "%TARGET_USER_SID%"
set "EXIT_CODE=%errorlevel%"
if "%EXIT_CODE%"=="0" goto install

echo.
echo Uninstall reported exit code %EXIT_CODE%; continuing with in-place install...
goto install

:install
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0dev-install.ps1" -TargetUserSid "%TARGET_USER_SID%"
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

:invalid_target_sid
echo Invalid or mismatched /TargetUserSid argument.
exit /b 3

:target_sid_failed
echo Could not preserve the non-elevated initiating user SID; no maintenance was run.
exit /b 3
