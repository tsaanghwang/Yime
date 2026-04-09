@echo off
setlocal EnableExtensions

set "SCRIPT_DIR=%~dp0"
set "PS1_PATH=%SCRIPT_DIR%enable-yinyuan-for-current-user.ps1"

if not exist "%PS1_PATH%" (
    echo Enable script not found: "%PS1_PATH%"
    pause
    exit /b 1
)

powershell -NoProfile -ExecutionPolicy Bypass -File "%PS1_PATH%"
set "EXITCODE=%ERRORLEVEL%"

echo.
echo enable script exit code: %EXITCODE%
if "%EXITCODE%"=="0" echo Yinyuan was added for the current user.
if not "%EXITCODE%"=="0" echo Failed to add Yinyuan for the current user.
pause

endlocal
