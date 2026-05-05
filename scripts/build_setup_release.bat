@echo off
setlocal EnableExtensions EnableDelayedExpansion

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

call "%PROJECT_ROOT%\scripts\build_portable_release.bat"
if errorlevel 1 exit /b %errorlevel%

set "DIST_DIR=%PROJECT_ROOT%\dist\Yime"
if not exist "%DIST_DIR%\Yime.exe" (
    echo Portable app is missing at "%DIST_DIR%\Yime.exe".
    exit /b 1
)

set "INNO_COMPILER=%ISCC%"
if not defined INNO_COMPILER if exist "%ProgramFiles(x86)%\Inno Setup 6\ISCC.exe" set "INNO_COMPILER=%ProgramFiles(x86)%\Inno Setup 6\ISCC.exe"
if not defined INNO_COMPILER if exist "%ProgramFiles%\Inno Setup 6\ISCC.exe" set "INNO_COMPILER=%ProgramFiles%\Inno Setup 6\ISCC.exe"

if not defined INNO_COMPILER (
    echo Inno Setup compiler not found.
    echo Install Inno Setup 6 and retry, or set ISCC to the full path of ISCC.exe.
    exit /b 1
)

pushd "%PROJECT_ROOT%"
"%INNO_COMPILER%" /DMyAppVersion=%APP_VERSION% /DMyPortableDistDir="%DIST_DIR%" /DMySetupOutputDir="%PROJECT_ROOT%\dist\setup" yime_setup.iss
set "BUILD_EXIT=%ERRORLEVEL%"
popd

if not "%BUILD_EXIT%"=="0" exit /b %BUILD_EXIT%

echo Setup build ready at dist\setup\Yime-Setup-%APP_VERSION%.exe
exit /b 0
