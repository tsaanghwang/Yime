@echo off
setlocal EnableExtensions

set "SCRIPT_DIR=%~dp0"
set "PS1_PATH=%SCRIPT_DIR%install-amd64-manual.ps1"

if not exist "%PS1_PATH%" (
    echo Manual installer script not found: "%PS1_PATH%"
    pause
    exit /b 1
)

powershell -NoProfile -ExecutionPolicy Bypass -File "%PS1_PATH%"
set "EXITCODE=%ERRORLEVEL%"

echo.
echo manual installer exit code: %EXITCODE%
if "%EXITCODE%"=="0" echo Manual install completed successfully.
if not "%EXITCODE%"=="0" echo Manual install failed.
pause

endlocal
