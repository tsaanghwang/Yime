@echo off
chcp 65001 >nul
setlocal

set "ROOT=%~dp0"
cd /d "%ROOT%"

if "%YIME_NO_PAUSE%"=="1" (
    set "SHOULD_PAUSE=0"
) else (
    set "SHOULD_PAUSE=1"
)

if exist "%ROOT%venv312\Scripts\python.exe" (
    set "PYTHON_EXE=%ROOT%venv312\Scripts\python.exe"
) else if exist "%ROOT%.venv\Scripts\python.exe" (
    set "PYTHON_EXE=%ROOT%.venv\Scripts\python.exe"
) else (
    echo Python virtual environment not found.
    echo.
    echo Expected one of these interpreters:
    echo   %ROOT%venv312\Scripts\python.exe
    echo   %ROOT%.venv\Scripts\python.exe
    echo.
    echo Run activate_py312.bat first, or create the virtual environment.
    echo.
    call :maybe_pause
    exit /b 1
)

echo ============================================================
echo Yinjie Encoder Launcher
echo ============================================================
echo Using: %PYTHON_EXE%
echo Output: %ROOT%yinjie_code.json
echo.

"%PYTHON_EXE%" "%ROOT%yinjie_encoder.py"
set "EXIT_CODE=%ERRORLEVEL%"

echo.
if "%EXIT_CODE%"=="0" (
    echo Encoding completed successfully.
) else (
    echo Encoding failed with exit code %EXIT_CODE%.
)

echo.
call :maybe_pause
exit /b %EXIT_CODE%

:maybe_pause
if "%SHOULD_PAUSE%"=="1" pause
exit /b 0
