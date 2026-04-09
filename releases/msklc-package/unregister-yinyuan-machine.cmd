@echo off
setlocal EnableExtensions

set "SCRIPT_DIR=%~dp0"
set "PS1_PATH=%SCRIPT_DIR%unregister-yinyuan-machine.ps1"

if not exist "%PS1_PATH%" (
    echo Unregister script not found: "%PS1_PATH%"
    pause
    exit /b 1
)

powershell -NoProfile -ExecutionPolicy Bypass -File "%PS1_PATH%"
set "EXITCODE=%ERRORLEVEL%"

echo.
echo unregister script exit code: %EXITCODE%
if "%EXITCODE%"=="0" echo Yinyuan machine-level registration removed.
if not "%EXITCODE%"=="0" echo Failed to remove Yinyuan machine-level registration.
pause

endlocal
