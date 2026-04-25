@echo off
setlocal EnableExtensions

set "SCRIPT_DIR=%~dp0"
set "MSI_PATH=%SCRIPT_DIR%Yinyuan_amd64.msi"
set "LOG_PATH=%SCRIPT_DIR%install-amd64-admin.log"
set "STAGE_DIR=%ProgramData%\Yinyuan-msklc-install"
set "STAGED_MSI_PATH=%STAGE_DIR%\Yinyuan_amd64.msi"
set "STAGED_LOG_PATH=%STAGE_DIR%\install-amd64-admin.log"

if not exist "%MSI_PATH%" (
    echo MSI not found: "%MSI_PATH%"
    pause
    exit /b 1
)

if /I not "%~1"=="--elevated" (
    echo Requesting administrator privileges...
    powershell -NoProfile -ExecutionPolicy Bypass -Command "Start-Process -FilePath '%~f0' -WorkingDirectory '%SCRIPT_DIR%' -Verb RunAs -ArgumentList '--elevated'"
    if errorlevel 1 (
        echo UAC request was cancelled or failed.
        pause
        exit /b 1
    )
    exit /b 0
)

echo Running elevated MSI install...
echo MSI: "%MSI_PATH%"
echo Log: "%LOG_PATH%"
echo.

if exist "%STAGE_DIR%" rmdir /s /q "%STAGE_DIR%" >nul 2>&1
mkdir "%STAGE_DIR%"
if errorlevel 1 (
    echo Failed to create staging directory "%STAGE_DIR%"
    pause
    exit /b 1
)

echo Staging package to local system directory...
xcopy "%SCRIPT_DIR%*" "%STAGE_DIR%\" /E /I /Y /Q >nul
if errorlevel 1 (
    echo Failed to copy package to "%STAGE_DIR%"
    pause
    exit /b 1
)

icacls "%STAGE_DIR%" /grant *S-1-5-18:(OI)(CI)F Administrators:(OI)(CI)F >nul 2>&1

if not exist "%STAGED_MSI_PATH%" (
    echo Staged MSI not found: "%STAGED_MSI_PATH%"
    pause
    exit /b 1
)

echo Staged MSI: "%STAGED_MSI_PATH%"
echo Staged log: "%STAGED_LOG_PATH%"
echo.

msiexec.exe /i "%STAGED_MSI_PATH%" /l*v "%STAGED_LOG_PATH%"
set "EXITCODE=%ERRORLEVEL%"

if exist "%STAGED_LOG_PATH%" copy /y "%STAGED_LOG_PATH%" "%LOG_PATH%" >nul

echo.
echo msiexec exit code: %EXITCODE%
if "%EXITCODE%"=="0" echo Install completed successfully.
if "%EXITCODE%"=="3010" echo Install succeeded and Windows requested a reboot.
if not "%EXITCODE%"=="0" if not "%EXITCODE%"=="3010" echo Installation failed. Check the log above.
if not "%EXITCODE%"=="0" if not "%EXITCODE%"=="3010" echo Rebuild the package in MSKLC or inspect "%LOG_PATH%" for details.
pause

endlocal
