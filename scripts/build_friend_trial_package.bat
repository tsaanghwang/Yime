@echo off
setlocal EnableExtensions

set "SCRIPT_DIR=%~dp0"
set "PROJECT_ROOT=%SCRIPT_DIR%.."

if "%PYTHON%"=="" (
    if exist "%PROJECT_ROOT%\.venv\Scripts\python.exe" (
        set "PYTHON=%PROJECT_ROOT%\.venv\Scripts\python.exe"
    ) else (
        set "PYTHON=python"
    )
)

for /f %%V in ('"%PYTHON%" scripts\print_project_version.py') do set "APP_VERSION=%%V"
if not defined APP_VERSION (
    echo Failed to read project version from pyproject.toml.
    exit /b 1
)

call "%PROJECT_ROOT%\scripts\build_setup_release.bat"
if errorlevel 1 exit /b %errorlevel%

set "SETUP_EXE=%PROJECT_ROOT%\dist\setup\Yime-Setup-%APP_VERSION%.exe"
if not exist "%SETUP_EXE%" (
    echo Setup package is missing at "%SETUP_EXE%".
    exit /b 1
)

set "TRIAL_DIR=%PROJECT_ROOT%\dist\friend-trial"
if exist "%TRIAL_DIR%" rmdir /s /q "%TRIAL_DIR%"
mkdir "%TRIAL_DIR%"

copy /y "%SETUP_EXE%" "%TRIAL_DIR%\" >nul
copy /y "%PROJECT_ROOT%\docs\install\friend-trial-one-page.md" "%TRIAL_DIR%\FRIEND-TRIAL-START-HERE.md" >nul
copy /y "%PROJECT_ROOT%\docs\install\friend-trial-checklist.md" "%TRIAL_DIR%\FRIEND-TRIAL-CHECKLIST.md" >nul
copy /y "%PROJECT_ROOT%\docs\install\friend-trial-message-template.md" "%TRIAL_DIR%\FRIEND-TRIAL-MESSAGE-TEMPLATE.md" >nul
copy /y "%PROJECT_ROOT%\docs\install\friend-trial-package-readme.txt" "%TRIAL_DIR%\README.txt" >nul

echo Friend-trial bundle ready at dist\friend-trial\
exit /b 0
