@echo off
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
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0dev-install.ps1" -TargetUserSid "%TARGET_USER_SID%"
set "EXIT_CODE=%errorlevel%"

echo.
if "%EXIT_CODE%"=="0" (
    echo YIME test install completed.
) else (
    echo YIME test install failed with exit code %EXIT_CODE%.
)
pause
exit /b %EXIT_CODE%

:invalid_target_sid
echo Invalid or mismatched /TargetUserSid argument.
exit /b 3

:target_sid_failed
echo Could not preserve the non-elevated initiating user SID; no maintenance was run.
exit /b 3
