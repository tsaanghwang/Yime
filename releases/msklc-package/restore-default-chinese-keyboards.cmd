@echo off
setlocal EnableExtensions

set "SCRIPT_DIR=%~dp0"
set "PS1_PATH=%SCRIPT_DIR%restore-default-chinese-keyboards.ps1"

if not exist "%PS1_PATH%" (
    echo Restore script not found: "%PS1_PATH%"
    pause
    exit /b 1
)

powershell -NoProfile -ExecutionPolicy Bypass -File "%PS1_PATH%"
set "EXITCODE=%ERRORLEVEL%"

echo.
echo restore script exit code: %EXITCODE%
if "%EXITCODE%"=="0" echo Default Chinese keyboard preload restored for the current user.
if not "%EXITCODE%"=="0" echo Failed to restore the default Chinese keyboard preload.
pause

endlocal
