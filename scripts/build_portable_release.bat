@echo off
setlocal

set "SCRIPT_DIR=%~dp0"
set "PROJECT_ROOT=%SCRIPT_DIR%.."

if "%PYTHON%"=="" (
    if exist "%PROJECT_ROOT%\.venv\Scripts\python.exe" (
        set "PYTHON=%PROJECT_ROOT%\.venv\Scripts\python.exe"
    ) else (
        set "PYTHON=python"
    )
)

pushd "%PROJECT_ROOT%"
%PYTHON% -m PyInstaller --noconfirm yime_portable.spec
if errorlevel 1 (
    popd
    exit /b %errorlevel%
)

echo Portable build ready at dist\Yime\
popd
exit /b 0
